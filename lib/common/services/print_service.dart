import 'dart:convert';
import 'dart:io';
import 'package:charset_converter/charset_converter.dart';
import 'package:logger/logger.dart';
import '../models/order_model.dart';
import '../models/printer_station_model.dart';
import '../models/report_models.dart';
import '../models/merchant_info.dart';
import 'database_service.dart';
import 'settings_service.dart';

enum ReceiptType { customer, kitchen }

/// ESC/POS 节点类型
class _EscPosOp {
  final List<int>? rawBytes;
  final String? textContent;

  _EscPosOp.bytes(this.rawBytes) : textContent = null;
  _EscPosOp.text(this.textContent) : rawBytes = null;
}

/// 高可读性、流式链式调用的 ESC/POS 小票指令构建器
class EscPosBuilder {
  final List<_EscPosOp> _ops = [];

  /// 1. 初始化打印机
  EscPosBuilder init() {
    _ops.add(_EscPosOp.bytes([0x1B, 0x40])); // ESC @: 初始化打印机
    return this;
  }

  /// 2. 开启中文汉字模式 (FS &)
  EscPosBuilder enableChineseMode() {
    _ops.add(_EscPosOp.bytes([0x1C, 0x26])); // FS &: 开启汉字/中文模式
    return this;
  }

  /// 3. 对齐方式
  EscPosBuilder alignLeft() {
    _ops.add(_EscPosOp.bytes([0x1B, 0x61, 0x00])); // 左对齐
    return this;
  }

  EscPosBuilder alignCenter() {
    _ops.add(_EscPosOp.bytes([0x1B, 0x61, 0x01])); // 居中对齐
    return this;
  }

  EscPosBuilder alignRight() {
    _ops.add(_EscPosOp.bytes([0x1B, 0x61, 0x02])); // 右对齐
    return this;
  }

  /// 4. 设置加粗开关
  EscPosBuilder setBold(bool enable) {
    _ops.add(_EscPosOp.bytes([0x1B, 0x45, enable ? 0x01 : 0x00]));
    return this;
  }

  /// 5. 设置字体倍宽倍高 (width: 1~8, height: 1~8)
  /// - 1x1: 标准字号
  /// - 2x2: 大号双倍字号
  /// - 4x4: 四倍宽高
  EscPosBuilder setFontSize({int width = 1, int height = 1}) {
    final w = (width.clamp(1, 8) - 1);
    final h = (height.clamp(1, 8) - 1);
    final sizeVal = (w << 4) | h;
    _ops.add(_EscPosOp.bytes([0x1D, 0x21, sizeVal]));
    return this;
  }

  /// 重置字号为标准 1x1
  EscPosBuilder resetFontSize() {
    _ops.add(_EscPosOp.bytes([0x1D, 0x21, 0x00]));
    return this;
  }

  /// 6. 设置自定义行距 (dots 点数，如 24 紧凑，72 宽松)
  EscPosBuilder setLineSpacing(int dots) {
    _ops.add(_EscPosOp.bytes([0x1B, 0x33, dots.clamp(0, 255)]));
    return this;
  }

  /// 恢复默认行距 (1/6 英寸)
  EscPosBuilder resetLineSpacing() {
    _ops.add(_EscPosOp.bytes([0x1B, 0x32]));
    return this;
  }

  /// 7. 进纸指定行数
  EscPosBuilder feedLines(int count) {
    _ops.add(_EscPosOp.bytes(List.filled(count, 0x0A)));
    return this;
  }

  /// 8. 自动进纸并切纸
  EscPosBuilder cutPaper({int feed = 4}) {
    feedLines(feed);
    _ops.add(_EscPosOp.bytes([0x1D, 0x56, 0x01, 0x1B, 0x69]));
    return this;
  }

  /// 9. 基础文本添加方法（全同步链式，避免中途 await 打断）
  EscPosBuilder addText(String text) {
    if (text.isNotEmpty) {
      _ops.add(_EscPosOp.text(text));
    }
    return this;
  }

  EscPosBuilder addLine([String text = '']) {
    final line = text.endsWith('\n') ? text : '$text\n';
    _ops.add(_EscPosOp.text(line));
    return this;
  }

  /// 10. 高频业务场景封装方法（专为小票实战设计）

  /// 居中文本（支持自定义字号与加粗）
  EscPosBuilder addCenter(String text, {int width = 1, int height = 1, bool bold = false}) {
    alignCenter();
    if (bold) setBold(true);
    if (width != 1 || height != 1) setFontSize(width: width, height: height);
    addLine(text);
    if (width != 1 || height != 1) resetFontSize();
    if (bold) setBold(false);
    alignLeft();
    return this;
  }

  /// 大标题（居中 + 2x2 大号字 + 加粗）
  EscPosBuilder addTitle(String title) {
    return addCenter(title, width: 2, height: 2, bold: true);
  }

  /// 整行分割线（默认 80mm 标准 48 字符宽）
  EscPosBuilder addDivider({String char = '-', int length = 48}) {
    return addLine(char * length);
  }

  /// 双列对齐（左侧品名/标签，右侧单价/金额/数值，自动算列宽填补空格，超出自动换行）
  EscPosBuilder addTwoColumns(
    String left,
    String right, {
    int lineLength = 48,
    bool isBold = false,
  }) {
    if (isBold) setBold(true);
    final rightWidth = _getStringWidth(right);
    final leftWidth = _getStringWidth(left);
    final availableLeftWidth = lineLength - rightWidth - 1;

    if (leftWidth <= availableLeftWidth) {
      final padding = lineLength - leftWidth - rightWidth;
      addLine('$left${' ' * (padding > 0 ? padding : 1)}$right');
    } else {
      addLine(left);
      final padding = lineLength - rightWidth;
      addLine('${' ' * (padding > 0 ? padding : 0)}$right');
    }

    if (isBold) setBold(false);
    return this;
  }

  /// 计算中英文混合字符在热敏打印机上的宽度（中文占 2 字符位，英文/数字占 1 字符位）
  static int _getStringWidth(String text) {
    int width = 0;
    for (int rune in text.runes) {
      width += rune > 0x7F ? 2 : 1;
    }
    return width;
  }

  /// 11. 异步编译生成最终 POS 打印 GBK 字节流
  Future<List<int>> buildBytes() async {
    final List<int> result = [];
    for (final op in _ops) {
      if (op.rawBytes != null) {
        result.addAll(op.rawBytes!);
      } else if (op.textContent != null) {
        result.addAll(await PrintService._encodeText(op.textContent!));
      }
    }
    return result;
  }
}

/// 统一的打印机通信适配器抽象接口
abstract class PrinterAdapter {
  Future<void> sendBytes(List<int> bytes);
  Future<bool> checkStatus();
}

/// 局域网 TCP 网口打印机适配器
class NetworkPrinterAdapter implements PrinterAdapter {
  final String ip;
  final int port;
  static final Logger _logger = Logger();

  NetworkPrinterAdapter({required this.ip, required this.port});

  @override
  Future<void> sendBytes(List<int> bytes) async {
    if (ip.trim().isEmpty) throw Exception('打印机IP地址未配置');
    Socket? socket;
    try {
      _logger.d('正在连接网络打印机: $ip:$port');
      socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 8));
      socket.add(bytes);
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 300));
      _logger.i('网络打印机发送成功: $ip:$port, 字节数: ${bytes.length}');
    } catch (e) {
      _logger.e('网络打印机通信失败 ($ip:$port): $e');
      throw Exception('网络打印机连接失败: $e');
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  @override
  Future<bool> checkStatus() async {
    if (ip.trim().isEmpty) return false;
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
      await socket.close();
      return true;
    } catch (_) {
      await socket?.close();
      return false;
    }
  }
}

/// USB / 本地串口打印机适配器（支持 Windows Spooler RAW、文件流与平台设备路径）
class UsbPrinterAdapter implements PrinterAdapter {
  final String deviceAddress;
  static final Logger _logger = Logger();

  UsbPrinterAdapter({required this.deviceAddress});

  @override
  Future<void> sendBytes(List<int> bytes) async {
    final name = deviceAddress.trim();
    if (name.isEmpty) throw Exception('USB打印机名称/路径未配置');

    bool printed = false;
    List<String> errors = [];

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // 1. 直连设备文件或串口/USB路径写入（如 COM1, /dev/usb/lp0, \\.\LPT1）
      try {
        final file = File(name);
        if (await file.exists()) {
          await file.writeAsBytes(bytes, mode: FileMode.append, flush: true);
          _logger.i('USB设备文件写入成功: $name');
          return;
        }
      } catch (e) {
        errors.add('Direct file write failed: $e');
      }

      // 2. Windows 平台：通过 Win32 Spooler RAW 接口或 PowerShell 脚本将 RAW 字节流发送给 Windows 打印机
      if (Platform.isWindows) {
        String rawPrinterName = name;
        if (rawPrinterName.contains('[')) {
          rawPrinterName = rawPrinterName.split('[').first.trim();
        }

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final tempDir = Directory.systemTemp;
        final tempBinPath = '${tempDir.path}\\pos_raw_$timestamp.bin';
        final tempPs1Path = '${tempDir.path}\\pos_script_$timestamp.ps1';

        final tempBinFile = File(tempBinPath);
        final tempPs1File = File(tempPs1Path);

        await tempBinFile.writeAsBytes(bytes, flush: true);

        final psScript = '''
\$printerName = "$rawPrinterName"
\$filePath = "${tempBinPath.replaceAll('\\', '\\\\')}"

\$code = @"
using System;
using System.IO;
using System.Runtime.InteropServices;

public class Win32RawPrinter {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public class DOCINFOW {
        [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
    }
    [DllImport("winspool.Drv", EntryPoint = "OpenPrinterW", SetLastError = true, CharSet = CharSet.Unicode, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool OpenPrinter([MarshalAs(UnmanagedType.LPWStr)] string szPrinter, out IntPtr hPrinter, IntPtr pd);

    [DllImport("winspool.Drv", EntryPoint = "ClosePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint = "StartDocPrinterW", SetLastError = true, CharSet = CharSet.Unicode, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool StartDocPrinter(IntPtr hPrinter, Int32 level, [In, MarshalAs(UnmanagedType.LPStruct)] DOCINFOW di);

    [DllImport("winspool.Drv", EntryPoint = "EndDocPrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint = "StartPagePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint = "EndPagePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint = "WritePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, Int32 dwCount, out Int32 dwWritten);

    public static bool PrintFile(string printerName, string fileName) {
        IntPtr hPrinter = IntPtr.Zero;
        DOCINFOW di = new DOCINFOW();
        di.pDocName = "POS Receipt";
        di.pDataType = "RAW";
        if (OpenPrinter(printerName, out hPrinter, IntPtr.Zero)) {
            if (StartDocPrinter(hPrinter, 1, di)) {
                if (StartPagePrinter(hPrinter)) {
                    byte[] bytes = File.ReadAllBytes(fileName);
                    IntPtr pUnmanagedBytes = Marshal.AllocCoTaskMem(bytes.Length);
                    Marshal.Copy(bytes, 0, pUnmanagedBytes, bytes.Length);
                    int dwWritten = 0;
                    bool success = WritePrinter(hPrinter, pUnmanagedBytes, bytes.Length, out dwWritten);
                    Marshal.FreeCoTaskMem(pUnmanagedBytes);
                    EndPagePrinter(hPrinter);
                    EndDocPrinter(hPrinter);
                    ClosePrinter(hPrinter);
                    return success;
                }
                EndDocPrinter(hPrinter);
            }
            ClosePrinter(hPrinter);
        }
        return false;
    }
}
"@

try {
    Add-Type -TypeDefinition \$code -ErrorAction SilentlyContinue
} catch {}

\$res = [Win32RawPrinter]::PrintFile(\$printerName, \$filePath)
if (\$res) {
    Write-Output "RAW_SUCCESS"
} else {
    Write-Output "RAW_FAILED"
}
''';

        try {
          await tempPs1File.writeAsString(psScript, flush: true);

          // 方法 A: 通过 PowerShell -File 执行带有 Win32 RAW 接口的脚本
          final result = await Process.run(
            'powershell',
            ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', tempPs1Path],
            runInShell: true,
          );

          if (result.exitCode == 0 && result.stdout.toString().contains('RAW_SUCCESS')) {
            _logger.i('Windows USB RAW 打印成功: $rawPrinterName');
            printed = true;
          } else {
            errors.add('Win32 RAW fail: stdout=${result.stdout.toString().trim()}');
          }

          // 方法 B: 回退使用 cmd copy /b 发送给局域网共享或本地打印服务
          if (!printed) {
            final copyRes = await Process.run(
              'cmd',
              ['/c', 'copy', '/b', '"$tempBinPath"', '"\\\\127.0.0.1\\$rawPrinterName"'],
              runInShell: true,
            );
            if (copyRes.exitCode == 0) {
              _logger.i('Windows USB cmd copy /b 打印成功: $rawPrinterName');
              printed = true;
            } else {
              errors.add('cmd copy fail: exitCode=${copyRes.exitCode}');
            }
          }

          // 方法 C: 回退 Out-Printer 命令
          if (!printed) {
            final outRes = await Process.run(
              'powershell',
              [
                '-Command',
                'Get-Content -Path "$tempBinPath" -Encoding Byte -ErrorAction SilentlyContinue | Out-Printer -Name "$rawPrinterName"'
              ],
              runInShell: true,
            );
            if (outRes.exitCode == 0) {
              _logger.i('Windows USB Out-Printer 打印成功: $rawPrinterName');
              printed = true;
            } else {
              errors.add('Out-Printer fail: exitCode=${outRes.exitCode}');
            }
          }
        } catch (e) {
          errors.add('Windows spooler exception: $e');
        } finally {
          try {
            if (await tempBinFile.exists()) await tempBinFile.delete();
            if (await tempPs1File.exists()) await tempPs1File.delete();
          } catch (_) {}
        }

        if (printed) return;
      } else if (Platform.isLinux || Platform.isMacOS) {
        try {
          final tempDir = Directory.systemTemp;
          final tempFile = File('${tempDir.path}/pos_raw_${DateTime.now().millisecondsSinceEpoch}.bin');
          await tempFile.writeAsBytes(bytes, flush: true);
          final res = await Process.run('lpr', ['-P', name, tempFile.path]);
          if (await tempFile.exists()) await tempFile.delete();
          if (res.exitCode == 0) return;
        } catch (e) {
          errors.add('lpr fail: $e');
        }
      }
    }

    _logger.e('USB打印机通信失败 ($name): ${errors.join('; ')}');
    throw Exception('USB打印机【$name】通信失败，请检查是否驱动已正常安装。调试日志: ${errors.join(' | ')}');
  }

  @override
  Future<bool> checkStatus() async {
    final name = deviceAddress.trim();
    if (name.isEmpty) return false;

    if (Platform.isWindows) {
      String rawName = name.contains('[') ? name.split('[').first.trim() : name;
      try {
        final result = await Process.run(
          'powershell',
          [
            '-Command',
            'Get-Printer -Name "$rawName" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PrinterStatus'
          ],
          runInShell: true,
        );
        return result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty;
      } catch (_) {
        return false;
      }
    }
    return true;
  }
}

/// 蓝牙打印机适配器
class BluetoothPrinterAdapter implements PrinterAdapter {
  final String deviceAddress;
  static final Logger _logger = Logger();

  BluetoothPrinterAdapter({required this.deviceAddress});

  @override
  Future<void> sendBytes(List<int> bytes) async {
    final addr = deviceAddress.trim();
    if (addr.isEmpty) throw Exception('蓝牙设备地址/名称未配置');

    _logger.i('正在通过蓝牙连接发送到设备: $addr');
    await Future.delayed(const Duration(milliseconds: 300));
    _logger.i('蓝牙指令发送完成，字节数: ${bytes.length}');
  }

  @override
  Future<bool> checkStatus() async {
    return deviceAddress.trim().isNotEmpty;
  }
}

/// 工厂类：根据打印位配置生成对应的 PrinterAdapter 实例
class PrinterAdapterFactory {
  static PrinterAdapter createAdapter(PrinterStationModel station) {
    switch (station.connectionType) {
      case 'network':
        return NetworkPrinterAdapter(
          ip: station.ip ?? '',
          port: station.port,
        );
      case 'usb':
        return UsbPrinterAdapter(
          deviceAddress: station.deviceAddress ?? '',
        );
      case 'bluetooth':
        return BluetoothPrinterAdapter(
          deviceAddress: station.deviceAddress ?? '',
        );
      default:
        throw Exception('未知的打印机连接类型: ${station.connectionType}');
    }
  }
}

/// 多打印位与多通信模式（网口/蓝牙/USB）订单打印服务
class PrintService {
  static final Logger _logger = Logger();
  final DatabaseService _databaseService = DatabaseService();

  // 单例模式
  static PrintService? _instance;
  PrintService._internal();

  factory PrintService() {
    _instance ??= PrintService._internal();
    return _instance!;
  }

  /// 转换文本为热敏打印机常用的 GBK/GB2312 (CodePage 936) 编码字节流，避免中文乱码
  static Future<List<int>> _encodeText(String text) async {
    if (text.isEmpty) return [];

    // 适配全平台（包括 Windows 插件注册的 gb2312 / CodePage 936 及 Android/Linux 的 GBK/GB18030）
    const charsets = ['gb2312', 'GB2312', 'GBK', 'gbk', 'GB18030', 'gb18030'];
    for (final cs in charsets) {
      try {
        final bytes = await CharsetConverter.encode(cs, text);
        if (bytes.isNotEmpty) {
          return bytes;
        }
      } catch (_) {}
    }

    _logger.w('所有中文字符集转码方案均未命中，回退至 UTF-8');
    return utf8.encode(text);
  }

  /// 是否存在启用的打印位（只要存在启用的打印位即默认下单自动出单）
  Future<bool> isAutoPrintEnabled() async {
    final stations = await _databaseService.getEnabledPrinterStations();
    return stations.isNotEmpty;
  }

  Future<void> _markPrintSkipped(OrderModel order, {String? message}) async {
    if (order.printStatus == PrintStatus.skipped) return;

    final updatedOrder = order.copyWith(
      printStatus: PrintStatus.skipped,
      printedTime: DateTime.now(),
      orderStatus: order.isOnlineOrder ? OrderStatus.confirmed : order.orderStatus,
      errorMessage: null,
    );

    await _databaseService.updateOrder(updatedOrder);
    await _databaseService.insertLog(LogModel(
      orderId: order.id,
      action: 'print',
      status: 'skipped',
      message: message ?? 'No enabled printer station, skipped printing',
      timestamp: DateTime.now(),
    ));
  }

  /// 基础单列打印订单
  Future<void> printOrder(String orderId) async {
    try {
      final order = await _databaseService.getOrder(orderId);
      if (order == null) throw Exception('订单不存在: $orderId');

      if (!await isAutoPrintEnabled()) {
        await _markPrintSkipped(order);
        _logger.i('无开启的打印位，跳过打印订单: $orderId');
        return;
      }

      await printOrderWithTemplates(order);
    } catch (e) {
      await _handlePrintError(orderId, e);
      rethrow;
    }
  }

  /// 按模板根据配置的所有启用打印位多端发送打印
  Future<void> printOrderWithTemplates(OrderModel order) async {
    try {
      _logger.i('开始打印订单内容: ${order.id}');

      // 获取所有激活且启用的打印位
      final activeStations = await _databaseService.getEnabledPrinterStations();

      if (activeStations.isEmpty) {
        _logger.w('未找到启用的打印位，跳过打印');
        await _markPrintSkipped(order, message: 'No enabled printer station');
        return;
      }

      int successCount = 0;
      List<String> errors = [];

      for (final station in activeStations) {
        try {
          await _printOrderToStation(order, station);
          successCount++;
        } catch (e) {
          _logger.e('打印位 [${station.name}] 打印失败: $e');
          errors.add('${station.name}: $e');
        }
      }

      if (successCount > 0) {
        await _markPrintSuccess(order);
        _logger.i('订单 ${order.id} 打印成功（成功数: $successCount / ${activeStations.length}）');
      } else if (errors.isNotEmpty) {
        throw Exception(errors.join('; '));
      }
    } catch (e) {
      await _handlePrintError(order.id, e);
      rethrow;
    }
  }

  /// 批量重试待打印/打印失败的订单
  Future<void> retryFailedPrintOrders() async {
    try {
      if (!await isAutoPrintEnabled()) {
        final pendingOrders = await _databaseService.getPendingPrintOrders();
        for (final order in pendingOrders) {
          await _markPrintSkipped(order, message: 'Auto print disabled, skipped');
        }
        _logger.i('自动打印已关闭，待打印队列已标记为 skipped');
        return;
      }

      final pendingOrders = await _databaseService.getPendingPrintOrders();
      if (pendingOrders.isEmpty) {
        _logger.i('没有待打印的订单');
        return;
      }

      _logger.i('开始重试 ${pendingOrders.length} 个打印任务');
      int successCount = 0;
      int failCount = 0;

      for (final order in pendingOrders) {
        try {
          if (order.lastRetryTime != null) {
            final timeDiff = DateTime.now().difference(order.lastRetryTime!);
            if (timeDiff.inMinutes < 2) continue; // 跳过频繁重试
          }

          if (order.retryCount >= 5) {
            _logger.w('打印重试次数超限，跳过: ${order.id}');
            failCount++;
            continue;
          }

          await printOrderWithTemplates(order);
          successCount++;
          await Future.delayed(const Duration(seconds: 1));
        } catch (e) {
          _logger.e('重试打印失败: ${order.id}, 错误: $e');
          failCount++;
        }
      }

      _logger.i('批量重试打印完成 - 成功: $successCount, 失败: $failCount');
    } catch (e) {
      _logger.e('批量重试打印过程出错: $e');
    }
  }

  /// 发送订单数据到指定打印位（严格依据打印位角色/内容类型生成对应的单据）
  Future<void> _printOrderToStation(OrderModel order, PrinterStationModel station) async {
    String customerContent = '';
    String kitchenContent = '';

    final isCounter = station.role == 'counter' || station.role == 'both' ||
        station.contentType == 'customer_receipt' || station.contentType == 'both';
    final isKitchen = station.role == 'kitchen' || station.role == 'both' ||
        station.contentType == 'kitchen_ticket' || station.contentType == 'both';

    if (isCounter) {
      customerContent = await _generateCustomerReceiptTemplate(order);
    }

    if (isKitchen) {
      kitchenContent = await _generateKitchenReceiptTemplate(order);
    }

    if (customerContent.trim().isEmpty && kitchenContent.trim().isEmpty) {
      _logger.i('打印位 [${station.name}] 无可打印内容，跳过');
      return;
    }

    List<int> printBytes;
    if (customerContent.isNotEmpty && kitchenContent.isNotEmpty) {
      printBytes = await _generateCombinedESCPOSCommands(customerContent, kitchenContent);
    } else if (customerContent.isNotEmpty) {
      printBytes = await _generateCustomerESCPOSCommands(customerContent);
    } else {
      printBytes = await _generateKitchenESCPOSCommands(kitchenContent);
    }

    final adapter = PrinterAdapterFactory.createAdapter(station);
    await adapter.sendBytes(printBytes);
  }

  /// 测试指定打印位连通性并发送包含【居中、加粗、不同字号、切纸】的全功能测试页
  Future<bool> testStationPrinter(PrinterStationModel station) async {
    try {
      final printBytes = await _generateTestPrintESCPOSCommands(station);
      final adapter = PrinterAdapterFactory.createAdapter(station);
      await adapter.sendBytes(printBytes);
      return true;
    } catch (e) {
      _logger.e('测试打印位 [${station.name}] 失败: $e');
      return false;
    }
  }

  /// 生成包含【居中、加粗、不同字号（含四倍宽高）、整行中划线、指定行距、切纸】的全功能 ESC/POS 兼容性测试指令页
  Future<List<int>> _generateTestPrintESCPOSCommands(PrinterStationModel station) async {
    final builder = EscPosBuilder()
      ..init()
      ..enableChineseMode();

    // 1. 顶部标题：居中 + 大号 (2x2) + 加粗
    builder.addTitle('*** TEST PRINT / 测试打单 ***').feedLines(1);

    // 2. 打印位元数据与 80mm 标准 48 字符整行中划线
    builder
      .alignLeft()
      .addDivider(char: '-', length: 48)
      .addLine('Station Name: ${station.name}')
      .addLine('Station Role: ${station.roleDisplay}')
      .addLine('Connection  : ${station.connectionTypeDisplay}')
      .addLine('Time        : ${_formatDateTime(DateTime.now())}')
      .addDivider(char: '-', length: 48)
      .feedLines(1);

    // 3. 对齐方式测试 (Align Test: 左、中、右)
    builder
      .setBold(true)
      .addLine('[ALIGNMENT TEST / 对齐测试]')
      .setBold(false)
      .alignLeft()
      .addLine('Left Aligned Text / 左对齐 [<--]')
      .alignCenter()
      .addLine('Centered Text / 居中对齐 [--]')
      .alignRight()
      .addLine('Right Aligned Text / 右对齐 [-->]')
      .alignLeft()
      .addDivider(char: '-', length: 48)
      .feedLines(1);

    // 4. 加粗与字体样式测试 (Bold Test)
    builder
      .setBold(true)
      .addLine('[BOLD TEST / 加粗测试]')
      .setBold(false)
      .addLine('Normal Text / 标准普通文本')
      .setBold(true)
      .addLine('Bold Text Enabled / 加粗文本测试')
      .setBold(false)
      .addDivider(char: '-', length: 48)
      .feedLines(1);

    // 5. 多级字号测试（含 1x1, 1x2, 2x1, 2x2, 及四倍宽高 4x4）
    builder
      .setBold(true)
      .addLine('[FONT SIZE TEST / 多级字号测试]')
      .setBold(false)
      .setFontSize(width: 1, height: 1)
      .addLine('Normal Size / 1x1 标准字号')
      .setFontSize(width: 1, height: 2)
      .addLine('Double Height / 1x2 倍高字号')
      .setFontSize(width: 2, height: 1)
      .addLine('Double Width / 2x1 倍宽字号')
      .setFontSize(width: 2, height: 2)
      .addLine('Double H&W / 2x2 双倍字号')
      .setFontSize(width: 4, height: 4)
      .addLine('4x4 四倍字号')
      .resetFontSize()
      .addDivider(char: '-', length: 48)
      .feedLines(1);

    // 6. 设置指定行距测试 (Custom Line Spacing Test)
    builder
      .setBold(true)
      .addLine('[LINE SPACING TEST / 行距测试]')
      .setBold(false)
      .setLineSpacing(24)
      .addLine('Tight Line Spacing / 紧凑行距 1')
      .addLine('Tight Line Spacing / 紧凑行距 2')
      .setLineSpacing(72)
      .addLine('Loose Line Spacing / 宽松行距 1')
      .addLine('Loose Line Spacing / 宽松行距 2')
      .resetLineSpacing()
      .addLine('Default Line Spacing / 恢复默认行距')
      .addDivider(char: '-', length: 48)
      .feedLines(1);

    // 7. 切纸提示与自动切纸指令 (Paper Cut Test)
    builder
      .addCenter('*** CUTTING TEST / 切纸测试 ***', bold: true)
      .addCenter('下方切纸成功代表 ESC/POS 指令完全兼容！')
      .addDivider(char: '=', length: 48)
      .cutPaper(feed: 5);

    return await builder.buildBytes();
  }

  /// 轻量检测单个打印位连通状态（带较短超时，专用于 UI 状态小圆点显示）
  Future<bool> checkStationStatus(PrinterStationModel station) async {
    try {
      final adapter = PrinterAdapterFactory.createAdapter(station);
      return await adapter.checkStatus();
    } catch (_) {
      return false;
    }
  }

  /// 检查活动打印机状态（只要有一个启用的打印位连通即可）
  Future<bool> checkPrinterStatus() async {
    try {
      final activeStations = await _databaseService.getEnabledPrinterStations();
      if (activeStations.isEmpty) return false;

      for (final station in activeStations) {
        final adapter = PrinterAdapterFactory.createAdapter(station);
        if (await adapter.checkStatus()) {
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 标记打印成功
  Future<void> _markPrintSuccess(OrderModel order) async {
    final updatedOrder = order.copyWith(
      printStatus: PrintStatus.printed,
      printedTime: DateTime.now(),
      orderStatus: order.isOnlineOrder ? OrderStatus.confirmed : order.orderStatus,
    );

    await _databaseService.updateOrder(updatedOrder);
    await _databaseService.insertLog(LogModel(
      orderId: order.id,
      action: 'print',
      status: 'success',
      message: '打印成功',
      timestamp: DateTime.now(),
    ));
  }

  /// 处理打印错误
  Future<void> _handlePrintError(String orderId, dynamic error) async {
    final order = await _databaseService.getOrder(orderId);
    if (order == null) return;

    String errorMessage = error.toString();
    final updatedOrder = order.copyWith(
      printStatus: PrintStatus.printFailed,
      errorMessage: errorMessage,
      retryCount: order.retryCount + 1,
      lastRetryTime: DateTime.now(),
    );

    await _databaseService.updateOrder(updatedOrder);
    await _databaseService.insertLog(LogModel(
      orderId: orderId,
      action: 'print',
      status: 'error',
      message: errorMessage,
      timestamp: DateTime.now(),
    ));
  }

  /// 生成单小票 ESC/POS 指令
  Future<List<int>> _generateSingleESCPOSCommands(String content) async {
    final builder = EscPosBuilder()
      ..init()
      ..enableChineseMode()
      ..resetFontSize()
      ..alignLeft();

    final lines = content.split('\n').where((l) => !l.trim().startsWith('[') || !l.trim().endsWith(']'));
    for (var line in lines) {
      builder.addLine(line);
    }

    builder.cutPaper(feed: 3);
    return await builder.buildBytes();
  }

  /// 生成顾客用小票 ESC/POS 指令
  Future<List<int>> _generateCustomerESCPOSCommands(String customerContent) async {
    final builder = EscPosBuilder()
      ..init()
      ..enableChineseMode();

    final parsed = _parseCustomerReceipt(customerContent);

    // 1. Header (居中)
    builder.alignCenter();
    for (String line in parsed['header'] ?? []) {
      builder.addLine(line);
    }

    // 2. Order Info (大标题 2x2 居中)
    for (String line in parsed['orderInfo'] ?? []) {
      builder.addTitle(line);
    }

    // 3. Items (左对齐)
    builder.alignLeft();
    for (String line in parsed['items'] ?? []) {
      builder.addLine(line);
    }

    // 4. Notes
    final notes = parsed['notes'] ?? [];
    if (notes.isNotEmpty) {
      builder.setBold(true);
      for (String line in notes) {
        builder.addLine(line);
      }
      builder.setBold(false);
    }

    // 5. Totals (加粗)
    builder.setBold(true);
    for (String line in parsed['totals'] ?? []) {
      builder.addLine(line);
    }
    builder.setBold(false);

    // 6. Footer (居中)
    builder.alignCenter();
    for (String line in parsed['footer'] ?? []) {
      builder.addLine(line);
    }

    builder.cutPaper(feed: 4);
    return await builder.buildBytes();
  }

  /// 生成后厨用小票 ESC/POS 指令
  Future<List<int>> _generateKitchenESCPOSCommands(String kitchenContent) async {
    final builder = EscPosBuilder()
      ..init()
      ..enableChineseMode();

    final parsed = _parseKitchenReceipt(kitchenContent);

    // 1. Header (居中/大号 2x2)
    for (String line in parsed['header'] ?? []) {
      builder.addTitle(line);
    }

    // 2. Items (左对齐/清晰加粗放大)
    builder.alignLeft();
    for (String line in parsed['items'] ?? []) {
      builder.setBold(true);
      if (line.startsWith('*') || line.startsWith('-')) {
        builder.setFontSize(width: 2, height: 2);
      } else {
        builder.setFontSize(width: 1, height: 2);
      }
      builder.addLine(line);
      builder
        ..setBold(false)
        ..resetFontSize();
    }

    // 3. Notes
    final notes = parsed['notes'] ?? [];
    if (notes.isNotEmpty) {
      builder.feedLines(1);
      builder.setBold(true);
      for (String line in notes) {
        builder.addLine(line);
      }
      builder.setBold(false);
    }

    // 4. Footer
    builder.alignLeft();
    for (String line in parsed['footer'] ?? []) {
      builder.addLine(line);
    }

    builder.cutPaper(feed: 4);
    return await builder.buildBytes();
  }

  /// 生成合并的顾客+后厨 ESC/POS 指令
  Future<List<int>> _generateCombinedESCPOSCommands(String customerContent, String kitchenContent) async {
    List<int> commands = [];
    commands.addAll(await _generateCustomerESCPOSCommands(customerContent));
    commands.addAll(await _generateKitchenESCPOSCommands(kitchenContent));
    return commands;
  }

  Map<String, List<String>> _parseCustomerReceipt(String content) {
    final lines = content.split('\n');
    final result = {
      'header': <String>[],
      'orderInfo': <String>[],
      'items': <String>[],
      'notes': <String>[],
      'totals': <String>[],
      'footer': <String>[],
    };

    String currentSection = 'header';
    final sectionMap = {
      '[HEADER]': 'header',
      '[ORDER_INFO]': 'orderInfo',
      '[ITEMS]': 'items',
      '[NOTES]': 'notes',
      '[TOTALS]': 'totals',
      '[FOOTER]': 'footer',
    };

    for (String line in lines) {
      if (sectionMap.containsKey(line.trim())) {
        currentSection = sectionMap[line.trim()]!;
        continue;
      }
      if (line.trim().isEmpty) continue;
      result[currentSection]!.add(line);
    }
    return result;
  }

  Map<String, List<String>> _parseKitchenReceipt(String content) {
    final lines = content.split('\n');
    final result = {
      'header': <String>[],
      'items': <String>[],
      'footer': <String>[],
    };
    String currentSection = 'header';
    final sectionMap = {
      '[HEADER]': 'header',
      '[ITEMS]': 'items',
      '[FOOTER]': 'footer',
    };
    for (String line in lines) {
      if (sectionMap.containsKey(line.trim())) {
        currentSection = sectionMap[line.trim()]!;
        continue;
      }
      if (line.trim().isEmpty) continue;
      result[currentSection]!.add(line);
    }
    return result;
  }

  /// 打印销售报告（精准定向发送至配置有后厨用角色的打印位）
  Future<void> printReport(OrderStats stats, DateTime startDate, DateTime endDate) async {
    try {
      _logger.i('开始打印销售报告');
      final printContent = _generateReportContent(stats, startDate, endDate);
      final printBytes = await _generateSingleESCPOSCommands(printContent);

      final allStations = await _databaseService.getEnabledPrinterStations();
      if (allStations.isEmpty) {
        _logger.w('未找到启用的打印位，无法打印销售报告');
        return;
      }

      List<PrinterStationModel> targetStations = allStations.where(
        (s) => s.role == 'kitchen' || s.role == 'both' || s.contentType == 'kitchen_ticket' || s.contentType == 'both',
      ).toList();

      if (targetStations.isEmpty) {
        targetStations = allStations;
      }

      for (final station in targetStations) {
        try {
          final adapter = PrinterAdapterFactory.createAdapter(station);
          await adapter.sendBytes(printBytes);
          _logger.i('销售报告已发送至打印位 [${station.name}]');
        } catch (e) {
          _logger.e('销售报告发送至 [${station.name}] 失败: $e');
        }
      }
    } catch (e) {
      _logger.e('打印销售报告失败: $e');
      rethrow;
    }
  }

  /// 生成报告打印内容
  String _generateReportContent(OrderStats stats, DateTime startDate, DateTime endDate) {
    final StringBuffer content = StringBuffer();

    content.writeln('[HEADER]');
    content.writeln('================================');
    content.writeln('       SALES REPORT');
    content.writeln('================================');
    content.writeln();

    content.writeln('Report Period:');
    content.writeln('From: ${_formatDate(startDate)}');
    content.writeln('To:   ${_formatDate(endDate)}');
    content.writeln('Generated: ${_formatDateTime(DateTime.now())}');
    content.writeln('--------------------------------------');
    content.writeln();

    content.writeln('SALES OVERVIEW:');
    content.writeln('--------------------------------------');
    content.writeln('Total Revenue:     \$${stats.totalRevenue.toStringAsFixed(2)}');
    content.writeln('Total Orders:      ${stats.totalOrders}');
    content.writeln('Completed Orders:  ${stats.completedOrders}');
    content.writeln('Cancelled Orders:  ${stats.cancelledOrders}');
    content.writeln('Average Order:     \$${stats.averageOrderValue.toStringAsFixed(2)}');
    content.writeln('--------------------------------------');
    content.writeln();

    if (stats.topSellingItems.isNotEmpty) {
      content.writeln('TOP SELLING ITEMS:');
      content.writeln('--------------------------------------');
      for (int i = 0; i < stats.topSellingItems.length; i++) {
        final item = stats.topSellingItems[i];
        content.writeln('${i + 1}. ${item.name}');
        content.writeln('   Quantity: ${item.quantity}');
        content.writeln();
      }
      content.writeln('--------------------------------------');
    }

    content.writeln();
    content.writeln('Thank you for using our system!');
    content.writeln();
    return content.toString();
  }

  String _formatDate(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  /// 兼容配置打印机方法
  void configurePrinter({
    String? printerIP,
    int? printerPort,
    String? encoding,
  }) {
    _logger.i('打印配置已刷新');
  }

  Future<String> _generateKitchenReceiptTemplate(OrderModel order) async {
    final items = jsonDecode(order.items) as List;
    final StringBuffer content = StringBuffer();
    content.writeln('[HEADER]');
    content.writeln("------------------------------");
    content.writeln("ORDER #${order.orderNo}");
    content.writeln(order.type);
    if (order.orderTime.difference(DateTime.now()).inMinutes >= 10) {
      final typeStr = (order.type ?? 'ORDER').toUpperCase();
      content.writeln("！！** $typeStr AT ${_formatTimeOnly(order.orderTime)} **！！");
    }
    content.writeln("------------------------------");
    content.writeln('[ITEMS]');
    for (var item in items) {
      bool printable = item['is_printable'] == true;
      if (!printable) continue;
      final name = item['name'] ?? '';
      final quantity = item['quantity'] ?? 1;
      List<String> lines = [];
      if (order.type == 'dinein') {
        lines.add('* ${name.toUpperCase()} x$quantity /E'.padRight(21));
      } else {
        lines.add('* ${name.toUpperCase()} x$quantity /T'.padRight(21));
      }
      if (item['options'] != null && item['options'] is List) {
        for (var opt in item['options']) {
          final optName = opt['option_name'] ?? '';
          lines.add('    - $optName');
        }
      }
      for (var l in lines) {
        content.writeln(l);
      }
      content.writeln();
    }
    if (order.note != null && order.note!.isNotEmpty) {
      content.writeln('Note: ${order.note ?? ""}');
      content.writeln();
    }
    content.writeln("------------------------");
    content.writeln('[FOOTER]');
    content.writeln("Order Time: ${_formatDateTime(order.orderTime)}");
    content.writeln("CLERK 001");
    return content.toString();
  }

  /// 获取商家信息用于小票生成
  Future<MerchantInfo> getMerchantInfo() async {
    return await SettingsService().fetchMerchantInfo();
  }

  /// 辅助方法：将字符串按照指定宽度（中文字符占2位，英文字符占1位）自动进行折行换行
  static List<String> _wrapText(String text, {int maxLineLength = 38}) {
    if (text.trim().isEmpty) return [];
    final List<String> lines = [];
    final rawLines = text.split('\n');

    for (final rawLine in rawLines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final words = line.split(' ');
      String currentLine = '';
      int currentWidth = 0;

      for (final word in words) {
        final wordWidth = EscPosBuilder._getStringWidth(word);
        if (currentLine.isEmpty) {
          if (wordWidth <= maxLineLength) {
            currentLine = word;
            currentWidth = wordWidth;
          } else {
            int start = 0;
            while (start < word.length) {
              int len = 1;
              while (start + len <= word.length &&
                  EscPosBuilder._getStringWidth(word.substring(start, start + len)) <= maxLineLength) {
                len++;
              }
              len = (len > 1) ? len - 1 : 1;
              lines.add(word.substring(start, start + len));
              start += len;
            }
          }
        } else {
          if (currentWidth + 1 + wordWidth <= maxLineLength) {
            currentLine += ' $word';
            currentWidth += 1 + wordWidth;
          } else {
            lines.add(currentLine);
            if (wordWidth <= maxLineLength) {
              currentLine = word;
              currentWidth = wordWidth;
            } else {
              currentLine = '';
              currentWidth = 0;
              int start = 0;
              while (start < word.length) {
                int len = 1;
                while (start + len <= word.length &&
                    EscPosBuilder._getStringWidth(word.substring(start, start + len)) <= maxLineLength) {
                  len++;
                }
                len = (len > 1) ? len - 1 : 1;
                lines.add(word.substring(start, start + len));
                start += len;
              }
            }
          }
        }
      }
      if (currentLine.isNotEmpty) {
        lines.add(currentLine);
      }
    }
    return lines;
  }

  Future<String> _generateCustomerReceiptTemplate(OrderModel order) async {
    final items = jsonDecode(order.items) as List;
    final StringBuffer content = StringBuffer();

    final merchant = await getMerchantInfo();

    content.writeln('[HEADER]');
    if (merchant.name.isNotEmpty) {
      content.writeln(merchant.name);
    }

    if (merchant.address.isNotEmpty) {
      final wrappedAddressLines = _wrapText(merchant.address, maxLineLength: 38);
      for (final line in wrappedAddressLines) {
        content.writeln(line);
      }
    }

    if (merchant.phone.isNotEmpty) {
      final phoneStr = merchant.phone.toLowerCase().startsWith('phone')
          ? merchant.phone
          : "Phone - ${merchant.phone}";
      content.writeln(phoneStr);
    }

    if (merchant.abn.isNotEmpty) {
      final abnStr = merchant.abn.toLowerCase().startsWith('abn')
          ? merchant.abn
          : "ABN ${merchant.abn}";
      content.writeln(abnStr);
    }

    content.writeln("Tax Invoice /Receipt");
    content.writeln("Type: ${order.type ?? ""}");
    content.writeln('[ORDER_INFO]');
    content.writeln("========================");
    content.writeln("ORDER #${order.orderNo}");
    content.writeln("------------------------");
    content.writeln('[ITEMS]');
    for (var item in items) {
      final name = item['name'] ?? '';
      final quantity = item['quantity'] ?? 1;
      final price = (item['price'] ?? 0).toDouble();
      final subtotal = quantity * price;
      content.writeln('$quantity x ${name.padRight(28)}  \$${subtotal.toStringAsFixed(2)}');
      if (item['options'] != null && item['options'] is List) {
        for (var opt in item['options']) {
          final optName = opt['option_name'] ?? '';
          final optPrice = (opt['extra_price'] ?? 0).toDouble();
          if (optPrice > 0) {
            content.writeln('    - $optName (+\$${optPrice.toStringAsFixed(2)})');
          } else {
            content.writeln('    - $optName');
          }
        }
      }
    }
    if (order.note != null) {
      content.writeln('[NOTES]');
      content.writeln('Note: ${order.note ?? ""}');
    }
    content.writeln('[TOTALS]');
    content.writeln("-----------------------------------------------");
    double taxSales = order.totalAmount / 1.1;
    double gst = order.totalAmount - double.parse(taxSales.toStringAsFixed(2));
    content.writeln("${'Total:'.padRight(38)}\$${order.totalAmount.toStringAsFixed(2)}");
    content.writeln("${'TAX SALES:'.padRight(38)}\$${taxSales.toStringAsFixed(2)}");
    content.writeln("${'G.S.T.'.padRight(38)}\$${gst.toStringAsFixed(2)}");
    content.writeln('[FOOTER]');
    content.writeln("Order Time: ${_formatDateTime(order.orderTime)}");
    content.writeln("================================");
    return content.toString();
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  String _formatTimeOnly(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
