import 'package:flutter/material.dart';

import '../../common/models/printer_station_model.dart';
import '../../common/services/database_service.dart';
import '../../common/services/print_service.dart';
import '../../common/services/printer_discovery_service.dart';
import '../../common/services/settings_service.dart';
import '../../common/services/language_service.dart';

Future<bool?> showPrinterConfigDialog({
  required BuildContext context,
  required SettingsService settingsService,
  required PrintService printService,
}) async {
  final dbService = DatabaseService();
  await settingsService.initialize();
  if (!context.mounted) return false;

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return _PrinterStationsDialog(
        dbService: dbService,
        printService: printService,
      );
    },
  );

  return result;
}

class _PrinterStationsDialog extends StatefulWidget {
  final DatabaseService dbService;
  final PrintService printService;

  const _PrinterStationsDialog({
    Key? key,
    required this.dbService,
    required this.printService,
  }) : super(key: key);

  @override
  State<_PrinterStationsDialog> createState() => _PrinterStationsDialogState();
}

class _PrinterStationsDialogState extends State<_PrinterStationsDialog> {
  List<PrinterStationModel> _stations = [];
  final Map<String, bool?> _stationStatusMap = {};
  bool _isLoading = true;
  String? _testingStationId;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    setState(() => _isLoading = true);
    final list = await widget.dbService.getPrinterStations();
    if (mounted) {
      setState(() {
        _stations = list;
        _isLoading = false;
      });
      _checkAllStationsStatus(list);
    }
  }

  Future<void> _checkAllStationsStatus(List<PrinterStationModel> list) async {
    for (final st in list) {
      if (!st.isEnabled) continue;
      widget.printService.checkStationStatus(st).then((isOk) {
        if (mounted) {
          setState(() {
            _stationStatusMap[st.id] = isOk;
          });
        }
      });
    }
  }

  Future<void> _testStation(PrinterStationModel station) async {
    setState(() => _testingStationId = station.id);
    final success = await widget.printService.testStationPrinter(station);
    if (!mounted) return;
    setState(() => _testingStationId = null);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? '打印位 [${station.name}] 测试打单成功' : '打印位 [${station.name}] 测试通信失败'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _deleteStation(PrinterStationModel station) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除打印位'),
        content: Text('确认要删除打印位 "${station.name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: Text('delete'.tr),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.dbService.deletePrinterStation(station.id);
      await _loadStations();
    }
  }

  Future<void> _openEditDialog([PrinterStationModel? existing]) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => _EditStationDialog(
        station: existing,
        existingStations: _stations,
        dbService: widget.dbService,
      ),
    );

    if (updated == true) {
      await _loadStations();
    }
  }

  Widget _buildStatusBadge(PrinterStationModel station) {
    if (!station.isEnabled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.grey)),
            const SizedBox(width: 4),
            Text('已禁用', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          ],
        ),
      );
    }

    final isAvailable = _stationStatusMap[station.id];

    if (isAvailable == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.amber),
            ),
            const SizedBox(width: 4),
            Text('检测中...', style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
          ],
        ),
      );
    }

    final color = isAvailable ? Colors.green : Colors.red;
    final text = isAvailable ? '可用' : '不可用';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.print_rounded, color: Color(0xFF9333EA)),
              const SizedBox(width: 8),
              Text('printer_config'.tr),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () => _openEditDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加打印位'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9333EA),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        height: 440,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _stations.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        '暂无配置的打印位，请点击右上角【+ 添加打印位】按钮进行设置',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _stations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final station = _stations[index];
                      final isTestingThis = _testingStationId == station.id;

                      String connDetail = '';
                      if (station.connectionType == 'network') {
                        connDetail = '${station.ip ?? "未配置"}:${station.port}';
                      } else {
                        connDetail = station.deviceAddress ?? '未配置设备';
                      }

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: station.isEnabled ? Colors.white : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: station.isEnabled ? const Color(0xFFE9D5FF) : Colors.grey.shade300,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.print_rounded,
                                  color: station.isEnabled ? const Color(0xFF9333EA) : Colors.grey,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  station.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(width: 8),
                                _buildStatusBadge(station),
                                const SizedBox(width: 8),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3E8FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    station.roleDisplay,
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF9333EA), fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const Spacer(),
                                Switch.adaptive(
                                  value: station.isEnabled,
                                  activeColor: const Color(0xFF9333EA),
                                  onChanged: (val) async {
                                    final updated = station.copyWith(isEnabled: val);
                                    await widget.dbService.updatePrinterStation(updated);
                                    if (val && updated.enableAutoPrint) {
                                      final settingsService = SettingsService();
                                      await settingsService.initialize();
                                      await settingsService.updateAutoFeatures(enableAutoPrint: true);
                                    }
                                    await _loadStations();
                                  },
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            Row(
                              children: [
                                Text(
                                  '连接: [${station.connectionTypeDisplay}] $connDetail',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                ),
                                const Spacer(),
                                OutlinedButton.icon(
                                  onPressed: isTestingThis ? null : () => _testStation(station),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    side: const BorderSide(color: Color(0xFF9333EA)),
                                  ),
                                  icon: isTestingThis
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9333EA)),
                                        )
                                      : const Icon(Icons.print_outlined, size: 16, color: Color(0xFF9333EA)),
                                  label: Text(
                                    isTestingThis ? '测试中...' : '测试打单',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF9333EA)),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blue),
                                  onPressed: () => _openEditDialog(station),
                                  tooltip: '编辑',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                  onPressed: () => _deleteStation(station),
                                  tooltip: '删除',
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('confirm'.tr),
        ),
      ],
    );
  }
}

class _EditStationDialog extends StatefulWidget {
  final PrinterStationModel? station;
  final List<PrinterStationModel> existingStations;
  final DatabaseService dbService;

  const _EditStationDialog({
    Key? key,
    this.station,
    required this.existingStations,
    required this.dbService,
  }) : super(key: key);

  @override
  State<_EditStationDialog> createState() => _EditStationDialogState();
}

class _EditStationDialogState extends State<_EditStationDialog> {
  late TextEditingController _nameController;
  late TextEditingController _ipController;
  late TextEditingController _portController;
  late TextEditingController _deviceAddressController;

  late String _role;
  late String _connectionType;
  late bool _enableAutoPrint;
  bool _isSearching = false;
  String _searchProgress = '';

  @override
  void initState() {
    super.initState();
    final st = widget.station;
    _role = st?.role ?? 'counter';
    _connectionType = st?.connectionType ?? 'network';
    _enableAutoPrint = st?.enableAutoPrint ?? true;

    final defaultName = st?.name ?? _generateDefaultName(_role);
    _nameController = TextEditingController(text: defaultName);
    _ipController = TextEditingController(text: st?.ip ?? '192.168.1.100');
    _portController = TextEditingController(text: st?.port.toString() ?? '9100');
    _deviceAddressController = TextEditingController(text: st?.deviceAddress ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _deviceAddressController.dispose();
    super.dispose();
  }

  /// 自动生成打印位默认名称：打印位区域 + 自动序号
  String _generateDefaultName(String role) {
    String prefix = '前台';
    if (role == 'kitchen') prefix = '后厨';
    if (role == 'both') prefix = '前台+后厨';

    final sameRoleStations = widget.existingStations
        .where((s) => s.id != widget.station?.id && s.role == role)
        .toList();

    return '$prefix${sameRoleStations.length + 1}';
  }

  /// 更改区域时，自动同步名字与打印内容映射
  void _onRoleChanged(String newRole) {
    setState(() {
      _role = newRole;
      _nameController.text = _generateDefaultName(newRole);
    });
  }

  /// 真实扫描局域网打印机
  Future<void> _searchNetworkPrinters() async {
    setState(() {
      _isSearching = true;
      _searchProgress = '准备扫描...';
    });

    final port = int.tryParse(_portController.text.trim()) ?? 9100;
    final found = await PrinterDiscoveryService.discoverNetworkPrinters(
      port: port,
      onProgress: (msg) {
        if (mounted) setState(() => _searchProgress = msg);
      },
    );

    if (!mounted) return;
    setState(() => _isSearching = false);

    _showDiscoveryPicker(
      title: '扫描到的局域网打印机 (TCP 9100)',
      devices: found,
      onSelected: (device) {
        setState(() {
          _ipController.text = device.address;
        });
      },
    );
  }

  /// 真实搜索蓝牙设备
  Future<void> _searchBluetoothDevices() async {
    setState(() {
      _isSearching = true;
      _searchProgress = '正在搜索蓝牙...';
    });

    final found = await PrinterDiscoveryService.discoverBluetoothDevices(
      onProgress: (msg) {
        if (mounted) setState(() => _searchProgress = msg);
      },
    );

    if (!mounted) return;
    setState(() => _isSearching = false);

    _showDiscoveryPicker(
      title: '真实的蓝牙打印设备',
      devices: found,
      onSelected: (device) {
        setState(() {
          _deviceAddressController.text = device.address;
        });
      },
    );
  }

  /// 真实搜索 USB 打印机
  Future<void> _searchUsbPrinters() async {
    setState(() {
      _isSearching = true;
      _searchProgress = '正在枚举系统 USB 打印机...';
    });

    final found = await PrinterDiscoveryService.discoverUsbPrinters(
      onProgress: (msg) {
        if (mounted) setState(() => _searchProgress = msg);
      },
    );

    if (!mounted) return;
    setState(() => _isSearching = false);

    _showDiscoveryPicker(
      title: '系统连接的真实 USB / 串口打印机',
      devices: found,
      onSelected: (device) {
        setState(() {
          _deviceAddressController.text = device.address;
        });
      },
    );
  }

  void _showDiscoveryPicker({
    required String title,
    required List<DiscoveredPrinterDevice> devices,
    required void Function(DiscoveredPrinterDevice) onSelected,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 400,
          child: devices.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                    child: Text('未扫描到连通设备，请确认打印机已开机并处于活动状态。'),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, index) {
                    final dev = devices[index];
                    return ListTile(
                      leading: Icon(
                        dev.type == 'network'
                            ? Icons.wifi_rounded
                            : dev.type == 'bluetooth'
                                ? Icons.bluetooth_rounded
                                : Icons.usb_rounded,
                        color: const Color(0xFF9333EA),
                      ),
                      title: Text(dev.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(dev.address, style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF9333EA)),
                      onTap: () {
                        onSelected(dev);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel'.tr),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.station != null;

    return AlertDialog(
      title: Text(isEdit ? '编辑打印位' : '添加打印位'),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('1. 打印位区域 (决定打印小票内容):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'counter', label: Text('前台 (顾客小票)')),
                  ButtonSegment(value: 'kitchen', label: Text('后厨 (后厨小票)')),
                  ButtonSegment(value: 'both', label: Text('前台+后厨')),
                ],
                selected: {_role},
                onSelectionChanged: (set) {
                  _onRoleChanged(set.first);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '打印位名称 (自动默认: 区域+序号)',
                  hintText: '如: 前台1 / 后厨1',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              const Text('2. 打印机连接方式:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'network', label: Text('局域网')),
                  ButtonSegment(value: 'bluetooth', label: Text('蓝牙')),
                  ButtonSegment(value: 'usb', label: Text('USB (仅电脑)')),
                ],
                selected: {_connectionType},
                onSelectionChanged: (set) {
                  setState(() => _connectionType = set.first);
                },
              ),
              const SizedBox(height: 12),

              // 局域网连接
              if (_connectionType == 'network') ...[
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _ipController,
                        decoration: const InputDecoration(
                          labelText: 'IP 地址 (可手动输入或自动搜索)',
                          hintText: '192.168.1.100',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '端口',
                          hintText: '9100',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isSearching ? null : _searchNetworkPrinters,
                    icon: _isSearching
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_find_rounded, size: 18),
                    label: Text(_isSearching ? _searchProgress : '真实并发扫描局域网打印机'),
                  ),
                ),
              ]
              // 蓝牙连接
              else if (_connectionType == 'bluetooth') ...[
                TextField(
                  controller: _deviceAddressController,
                  decoration: const InputDecoration(
                    labelText: '蓝牙设备 MAC 地址 / 名称',
                    hintText: '如 00:11:22:33:44:55 或 BT-Printer',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isSearching ? null : _searchBluetoothDevices,
                    icon: _isSearching
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.bluetooth_searching_rounded, size: 18),
                    label: Text(_isSearching ? _searchProgress : '自动搜索真实蓝牙打印设备'),
                  ),
                ),
              ]
              // USB 连接
              else ...[
                TextField(
                  controller: _deviceAddressController,
                  decoration: const InputDecoration(
                    labelText: 'USB 打印机名称',
                    hintText: '如: POS-80 或 LPT1 / COM3',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isSearching ? null : _searchUsbPrinters,
                    icon: _isSearching
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.usb_rounded, size: 18),
                    label: Text(_isSearching ? _searchProgress : '真实搜寻系统 USB 打印机 (PC端)'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('cancel'.tr),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;

            final ip = _ipController.text.trim();
            final port = int.tryParse(_portController.text.trim()) ?? 9100;
            final address = _deviceAddressController.text.trim();

            final id = widget.station?.id ?? 'station_${DateTime.now().millisecondsSinceEpoch}';

            final newStation = PrinterStationModel(
              id: id,
              name: name,
              role: _role,
              contentType: PrinterStationModel.mapRoleToContentType(_role),
              connectionType: _connectionType,
              ip: ip.isNotEmpty ? ip : '192.168.1.100',
              port: port,
              deviceAddress: address,
              enableAutoPrint: _enableAutoPrint,
              isEnabled: widget.station?.isEnabled ?? true,
            );

            if (isEdit) {
              await widget.dbService.updatePrinterStation(newStation);
            } else {
              await widget.dbService.insertPrinterStation(newStation);
            }

            if (newStation.isEnabled && newStation.enableAutoPrint) {
              final settingsService = SettingsService();
              await settingsService.initialize();
              await settingsService.updateAutoFeatures(enableAutoPrint: true);
            }

            if (!mounted) return;
            Navigator.pop(context, true);
          },
          child: Text('save'.tr),
        ),
      ],
    );
  }
}
