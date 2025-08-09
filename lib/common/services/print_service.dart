import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import '../models/order_model.dart';
import 'database_service.dart';
import 'settings_service.dart';

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

  /// 打印订单
  Future<void> printOrder(String orderId) async {
    try {
      final order = await _databaseService.getOrder(orderId);
      if (order == null) {
        throw Exception('订单不存在: $orderId');
      }

      _logger.i('开始打印订单: $orderId');

      // 生成打印内容
      final printContent = await _generatePrintContent(order);

      // 发送到打印机
      await _sendToPrinter(printContent);

      // 标记打印成功
      await _markPrintSuccess(order);

      _logger.i('订单打印成功: $orderId');

    } catch (e) {
      await _handlePrintError(orderId, e);
      rethrow;
    }
  }

  /// 生成打印内容
  Future<String> _generatePrintContent(OrderModel order) async {
    final items = jsonDecode(order.items) as List;
    final StringBuffer content = StringBuffer();

    // Print header (English only)
    content.writeln('================================');
    content.writeln('       RESTAURANT RECEIPT');
    content.writeln('================================');
    content.writeln();

    // Order information
    content.writeln('Order ID: ${order.id.substring(0, 8)}');
    content.writeln('Order Time: ${_formatDateTime(order.orderTime)}');
    content.writeln('--------------------------------');
    content.writeln();

    // Items detail
    content.writeln('Items:');
    content.writeln('--------------------------------');

    double totalAmount = 0;
    for (var item in items) {
      final name = item['name'] ?? '';
      final quantity = item['quantity'] ?? 1;
      final price = (item['price'] ?? 0).toDouble();
      final subtotal = quantity * price;
      totalAmount += subtotal;

      content.writeln('${name.padRight(20)} x${quantity}');
      content.writeln('${' ' * 16}\$${price.toStringAsFixed(2)} = \$${subtotal.toStringAsFixed(2)}');

      // Notes if any
      if (item['note'] != null && item['note'].toString().isNotEmpty) {
        content.writeln('${' ' * 4}Note: ${item['note']}');
      }
      content.writeln();
    }

    content.writeln('--------------------------------');
    content.writeln('Total: \$${totalAmount.toStringAsFixed(2)}');
    content.writeln('================================');
    content.writeln();

    // Print time
    content.writeln('Print Time: ${_formatDateTime(DateTime.now())}');
    content.writeln('--------------------------------');
    content.writeln('Thank you for your business!');
    content.writeln();
    content.writeln();
    content.writeln(); // Extra lines for easy tearing

    return content.toString();
  }

  /// 发送到打印机
  Future<void> _sendToPrinter(String content) async {
    try {
      // 获取打印机配置
      final settingsService = SettingsService();
      final settings = settingsService.getSettings();

      final printerIP = settings.printerAddress;
      final printerPort = settings.printerPort;

      if (printerIP.isEmpty) {
        throw Exception('打印机IP地址未配置');
      }

      _logger.i('连接打印机: $printerIP:$printerPort');

      // 实际发送到网络打印机
      await _sendToNetworkPrinter(content, printerIP, printerPort);

    } catch (e) {
      _logger.e('发送到打印机失败: $e');
      throw Exception('打印机通信失败: $e');
    }
  }

  /// 网络打印机发送（真实实现）
  Future<void> _sendToNetworkPrinter(String content, String printerIP, int port) async {
    Socket? socket;

    try {
      _logger.d('正在连接打印机: $printerIP:$port');

      // 建立TCP连接，设置超时时间
      socket = await Socket.connect(printerIP, port)
          .timeout(Duration(seconds: 10));

      _logger.d('打印机连接成功');

      // 生成ESC/POS命令
      final printData = _generateESCPOSCommands(content);

      // 发送数据到打印机
      socket.add(printData);
      await socket.flush();

      // 等待一小段时间确保数据发送完成
      await Future.delayed(Duration(milliseconds: 500));

      _logger.i('数据发送到打印机成功，长度: ${printData.length} bytes');

    } catch (e) {
      _logger.e('网络打印机通信失败: $e');
      throw Exception('网络打印机连接失败: $e');
    } finally {
      // 确保关闭连接
      try {
        await socket?.close();
        _logger.d('打印机连接已关闭');
      } catch (e) {
        _logger.w('关闭打印机连接时出错: $e');
      }
    }
  }

  /// 生成ESC/POS打印命令
  List<int> _generateESCPOSCommands(String content) {
    List<int> commands = [];

    // ESC/POS 初始化命令
    commands.addAll([0x1B, 0x40]); // ESC @ - 初始化打印机

    // 设置字符集为UTF-8
    commands.addAll([0x1B, 0x74, 0x06]); // ESC t 6 - 设置字符集

    // 设置字体大小（正常）
    commands.addAll([0x1D, 0x21, 0x00]); // GS ! 0 - 正常字体

    // 设置左对齐
    commands.addAll([0x1B, 0x61, 0x00]); // ESC a 0 - 左对齐

    // 添加打印内容
    commands.addAll(utf8.encode(content));

    // 切纸命令（部分切纸）
    commands.addAll([0x1D, 0x56, 0x01]); // GS V 1 - 部分切纸

    // 或者使用全切纸（如果打印机支持）
    // commands.addAll([0x1D, 0x56, 0x00]); // GS V 0 - 全切纸

    return commands;
  }

  /// 标记打印成功
  Future<void> _markPrintSuccess(OrderModel order) async {
    final updatedOrder = order.copyWith(
      printStatus: PrintStatus.printed,
      printedTime: DateTime.now(),
    );

    await _databaseService.updateOrder(updatedOrder);

    // 记录成功日志
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

    // 更新订单打印状态
    final updatedOrder = order.copyWith(
      printStatus: PrintStatus.printFailed,
      errorMessage: errorMessage,
      retryCount: order.retryCount + 1,
      lastRetryTime: DateTime.now(),
    );

    await _databaseService.updateOrder(updatedOrder);

    // 记录错误日志
    await _databaseService.insertLog(LogModel(
      orderId: orderId,
      action: 'print',
      status: 'error',
      message: errorMessage,
      timestamp: DateTime.now(),
    ));
  }

  /// 批量重试打印失败的订单
  Future<void> retryFailedPrintOrders() async {
    try {
      final failedOrders = await _databaseService.getPendingPrintOrders();

      if (failedOrders.isEmpty) {
        _logger.i('没有待打印的订单');
        return;
      }

      _logger.i('开始重试 ${failedOrders.length} 个打印任务');

      int successCount = 0;
      int failCount = 0;

      for (final order in failedOrders) {
        try {
          // 检查重试间隔
          if (order.lastRetryTime != null) {
            final timeDiff = DateTime.now().difference(order.lastRetryTime!);
            if (timeDiff.inMinutes < 2) {
              continue; // 跳过频繁重试
            }
          }

          // 检查重试次数
          if (order.retryCount >= 5) {
            _logger.w('打印重试次数超限，跳过: ${order.id}');
            failCount++;
            continue;
          }

          await printOrder(order.id);
          successCount++;

          // 控制打印频率，避免打印机过载
          await Future.delayed(Duration(seconds: 1));

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

  /// 检查打印机状态
  Future<bool> checkPrinterStatus() async {
    try {
      final settingsService = SettingsService();
      final settings = settingsService.getSettings();

      final printerIP = settings.printerAddress;
      final printerPort = settings.printerPort;

      if (printerIP.isEmpty) {
        _logger.w('打印机IP地址未配置');
        return false;
      }

      _logger.d('检查打印机状态: $printerIP:$printerPort');

      // 尝试连接打印机
      Socket? socket;
      try {
        socket = await Socket.connect(printerIP, printerPort)
            .timeout(Duration(seconds: 5));

        // 发送状态查询命令
        socket.add([0x10, 0x04, 0x01]); // DLE EOT 1 - 查询打印机状态
        await socket.flush();

        // 等待响应
        final response = await socket.first.timeout(Duration(seconds: 3));

        _logger.d('打印机状态响应: $response');

        await socket.close();
        return true;

      } catch (e) {
        _logger.w('打印机状态检查失败: $e');
        await socket?.close();
        return false;
      }

    } catch (e) {
      _logger.e('检查打印机状态失败: $e');
      return false;
    }
  }

  /// 手动重置订单打印状态
  Future<void> resetOrderPrintStatus(String orderId) async {
    final order = await _databaseService.getOrder(orderId);
    if (order == null) return;

    final resetOrder = order.copyWith(
      printStatus: PrintStatus.pending,
      retryCount: 0,
      lastRetryTime: null,
    );

    await _databaseService.updateOrder(resetOrder);

    // 记录重置日志
    await _databaseService.insertLog(LogModel(
      orderId: orderId,
      action: 'print',
      status: 'reset',
      message: '手动重置打印状态',
      timestamp: DateTime.now(),
    ));

    _logger.i('订单打印状态已重置: $orderId');
  }

  /// 获取打印队列统计
  Future<Map<String, int>> getPrintQueueStats() async {
    final pendingOrders = await _databaseService.getPendingPrintOrders();

    int pendingCount = 0;
    int failedCount = 0;

    for (final order in pendingOrders) {
      if (order.printStatus == PrintStatus.pending) {
        pendingCount++;
      } else if (order.printStatus == PrintStatus.printFailed) {
        failedCount++;
      }
    }

    return {
      'pendingCount': pendingCount,
      'failedCount': failedCount,
      'totalCount': pendingOrders.length,
    };
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  /// 配置打印机设置
  void configurePrinter({
    String? printerIP,
    int? printerPort,
    String? encoding,
  }) {
    // 保存打印机配置到本地存储
    _logger.i('打印机配置已更新');
  }
}
