import 'dart:async';
import 'dart:io';
import 'package:logger/logger.dart';

class DiscoveredPrinterDevice {
  final String name;
  final String address; // IP, Bluetooth Name/MAC, or USB Printer Name
  final String type; // 'network', 'bluetooth', 'usb'

  DiscoveredPrinterDevice({
    required this.name,
    required this.address,
    required this.type,
  });
}

/// 真实打印机设备搜索与探查服务（局域网网段并发扫描、蓝牙 Android Pad / PC 真实搜寻、USB 打印机系统枚举）
class PrinterDiscoveryService {
  static final Logger _logger = Logger();

  /// 1. 真实高并发扫描局域网网段内的打印机 (TCP Port 9100)
  static Future<List<DiscoveredPrinterDevice>> discoverNetworkPrinters({
    int port = 9100,
    void Function(String message)? onProgress,
  }) async {
    final List<DiscoveredPrinterDevice> found = [];
    try {
      // 真实获取本机活动的局域网 IPv4 地址
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      String? activeSubnet;
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            final ip = addr.address;
            final lastDot = ip.lastIndexOf('.');
            if (lastDot != -1) {
              activeSubnet = ip.substring(0, lastDot);
              break;
            }
          }
        }
        if (activeSubnet != null) break;
      }

      activeSubnet ??= '192.168.1';
      onProgress?.call('正在扫描局域网网段 $activeSubnet.1 ~ $activeSubnet.254 ...');

      // 分批高并发探测 IP 1~254
      const int batchSize = 35;
      for (int start = 1; start <= 254; start += batchSize) {
        final batchEnd = (start + batchSize - 1) > 254 ? 254 : (start + batchSize - 1);
        onProgress?.call('扫网段 IP: $activeSubnet.$start ~ $activeSubnet.$batchEnd');

        final futures = <Future<void>>[];
        for (int i = start; i <= batchEnd; i++) {
          final targetIp = '$activeSubnet.$i';
          futures.add(_probePrinterAtIp(targetIp, port).then((device) {
            if (device != null) {
              found.add(device);
            }
          }));
        }
        await Future.wait(futures);
      }

      _logger.i('真实局域网打印机扫描完成，共找到 ${found.length} 台设备');
    } catch (e) {
      _logger.e('真实局域网打印机扫描异常: $e');
    }
    return found;
  }

  static Future<DiscoveredPrinterDevice?> _probePrinterAtIp(String ip, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 350));
      String displayName = '网络打印机 ($ip)';
      try {
        final hostInfo = await InternetAddress(ip).reverse().timeout(const Duration(milliseconds: 200));
        if (hostInfo.host.isNotEmpty && hostInfo.host != ip) {
          displayName = '${hostInfo.host} ($ip)';
        }
      } catch (_) {}

      await socket.close();
      return DiscoveredPrinterDevice(
        name: displayName,
        address: ip,
        type: 'network',
      );
    } catch (_) {
      try {
        await socket?.close();
      } catch (_) {}
      return null;
    }
  }

  /// 2. 真实搜寻系统蓝牙打印设备（支持 Windows PC 及 Android Pad / 移动端）
  static Future<List<DiscoveredPrinterDevice>> discoverBluetoothDevices({
    void Function(String message)? onProgress,
  }) async {
    final List<DiscoveredPrinterDevice> devices = [];
    onProgress?.call('正在搜寻系统配对及附近的真实蓝牙设备...');

    try {
      if (Platform.isAndroid) {
        onProgress?.call('正在探查 Android Pad 系统的蓝牙打印设备...');
        // 1. 尝试使用 cmd bluetooth_manager 查询已配对蓝牙设备
        try {
          final result = await Process.run('cmd', ['bluetooth_manager', 'get_bonded_devices']);
          if (result.exitCode == 0 && result.stdout.toString().isNotEmpty) {
            final lines = result.stdout.toString().split('\n');
            for (var line in lines) {
              final trimmed = line.trim();
              if (trimmed.isNotEmpty) {
                devices.add(DiscoveredPrinterDevice(
                  name: '蓝牙设备 ($trimmed)',
                  address: trimmed,
                  type: 'bluetooth',
                ));
              }
            }
          }
        } catch (_) {}

        // 2. 如果 cmd 命令不可用，解析 dumpsys bluetooth_manager 输出
        if (devices.isEmpty) {
          try {
            final result = await Process.run('dumpsys', ['bluetooth_manager']);
            if (result.exitCode == 0) {
              final output = result.stdout.toString();
              final reg = RegExp(r'([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})\s*\(?([^)\r\n]*)\)?');
              final matches = reg.allMatches(output);
              final Set<String> added = {};
              for (var m in matches) {
                final mac = m.group(0)?.split(' ').first.trim() ?? '';
                final name = m.group(3)?.trim();
                if (mac.isNotEmpty && !added.contains(mac)) {
                  added.add(mac);
                  final displayName = (name != null && name.isNotEmpty)
                      ? '$name ($mac)'
                      : '蓝牙打印机 ($mac)';
                  devices.add(DiscoveredPrinterDevice(
                    name: displayName,
                    address: mac,
                    type: 'bluetooth',
                  ));
                }
              }
            }
          } catch (_) {}
        }
      } else if (Platform.isWindows) {
        // Windows 平台使用 PowerShell 探查活动蓝牙 PnP 设备
        final result = await Process.run(
          'powershell',
          [
            '-Command',
            'Get-PnpDevice -Class Bluetooth | Where-Object { \$_.FriendlyName -ne \$null } | Select-Object -ExpandProperty FriendlyName'
          ],
          runInShell: true,
        );

        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          final Set<String> addedNames = {};
          for (var line in lines) {
            final name = line.trim();
            if (name.isNotEmpty && !addedNames.contains(name)) {
              addedNames.add(name);
              devices.add(DiscoveredPrinterDevice(
                name: name,
                address: name,
                type: 'bluetooth',
              ));
            }
          }
        }
      } else if (Platform.isLinux || Platform.isMacOS) {
        final result = await Process.run('bluetoothctl', ['devices']);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          for (var line in lines) {
            final parts = line.trim().split(' ');
            if (parts.length >= 3 && parts[0] == 'Device') {
              final mac = parts[1];
              final devName = parts.sublist(2).join(' ');
              devices.add(DiscoveredPrinterDevice(
                name: '$devName ($mac)',
                address: mac,
                type: 'bluetooth',
              ));
            }
          }
        }
      }
    } catch (e) {
      _logger.e('真实蓝牙设备搜寻失败: $e');
    }

    return devices;
  }

  /// 3. 真实枚举系统已连接/安装的 USB / 串口打印机 (Windows Get-Printer / System Enum)
  static Future<List<DiscoveredPrinterDevice>> discoverUsbPrinters({
    void Function(String message)? onProgress,
  }) async {
    final List<DiscoveredPrinterDevice> list = [];
    onProgress?.call('正在搜寻电脑系统连接的真实 USB 打印机...');

    try {
      if (Platform.isWindows) {
        // 使用 PowerShell 探查已安装的系统打印机及端口
        final result = await Process.run(
          'powershell',
          [
            '-Command',
            'Get-Printer | Select-Object Name, PortName | Format-Table -HideTableHeaders'
          ],
          runInShell: true,
        );

        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          for (var line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;

            // 过滤虚拟/软件打印机 (如 Microsoft Print to PDF, Fax, OneNote 等)
            if (trimmed.contains('Microsoft') ||
                trimmed.contains('PDF') ||
                trimmed.contains('XPS') ||
                trimmed.contains('OneNote') ||
                trimmed.contains('Fax')) {
              continue;
            }

            final parts = trimmed.split(RegExp(r'\s{2,}'));
            final printerName = parts[0].trim();
            final portName = parts.length > 1 ? parts[1].trim() : '';

            if (printerName.isNotEmpty) {
              final displayName = portName.isNotEmpty
                  ? '$printerName [$portName]'
                  : printerName;

              list.add(DiscoveredPrinterDevice(
                name: displayName,
                address: printerName,
                type: 'usb',
              ));
            }
          }
        }
      } else if (Platform.isMacOS || Platform.isLinux) {
        final result = await Process.run('lpstat', ['-p', '-d']);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          for (var line in lines) {
            if (line.startsWith('printer ')) {
              final parts = line.split(' ');
              if (parts.length >= 2) {
                final name = parts[1];
                list.add(DiscoveredPrinterDevice(
                  name: name,
                  address: name,
                  type: 'usb',
                ));
              }
            }
          }
        }
      }
    } catch (e) {
      _logger.e('真实 USB 打印机搜索失败: $e');
    }

    return list;
  }
}
