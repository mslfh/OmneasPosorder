import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:hive/hive.dart';
import 'dart:async';
import '../../common/models/app_settings.dart';
import '../../common/services/settings_service.dart';
import '../../common/services/sync_service.dart';
import '../../common/services/print_service.dart';
import '../../common/services/background_task_manager.dart';
import '../../common/services/api_service.dart';
import '../../common/services/app_initialization_service.dart';
import '../../common/models/store_hours_config.dart';
import '../internal_app.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final Logger _logger = Logger();
  final SettingsService _settingsService = SettingsService();
  final SyncService _syncService = SyncService();
  final PrintService _printService = PrintService();

  late AppSettings _settings;
  StoreHoursConfig? _storeHours;
  TaskStatusReport? _taskStatus;
  bool _isLoading = true;
  // 新增测试状态变量
  bool _isTestingConnection = false;
  bool _isTestingPrinter = false;

  Timer? _debounceTimer;
  Timer? _statusRefreshTimer;

  // Controllers
  final _apiUrlController = TextEditingController();
  final _printerAddressController = TextEditingController();
  final _printerPortController = TextEditingController();
  final _fetchRemoteOrdersIntervalController = TextEditingController();
  final _orderMatchCheckIntervalController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _startStatusPolling();
  }

  void _startStatusPolling() {
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (mounted) {
        final report = await BackgroundTaskManager().getTaskStatusReport();
        setState(() {
          _taskStatus = report;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _statusRefreshTimer?.cancel();
    _apiUrlController.dispose();
    _printerAddressController.dispose();
    _printerPortController.dispose();
    _fetchRemoteOrdersIntervalController.dispose();
    _orderMatchCheckIntervalController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      await _settingsService.initialize();
      _settings = _settingsService.getSettings();
      _storeHours = await _settingsService.fetchStoreHours();

      // Update controllers
      _apiUrlController.text = _settings.apiServerUrl;
      _printerAddressController.text = _settings.printerAddress;
      _printerPortController.text = _settings.printerPort.toString();
      _fetchRemoteOrdersIntervalController.text = _settings.fetchRemoteOrdersIntervalSeconds.toString();
      _orderMatchCheckIntervalController.text = _settings.orderMatchCheckIntervalMinutes.toString();

      setState(() => _isLoading = false);
    } catch (e) {
      _logger.e('Failed to load settings: $e');
      _showErrorSnackBar('Failed to load settings: $e');
      setState(() => _isLoading = false);
    }
  }

  String _cleanUrlFormat(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  void _onSettingsChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1000), _applySettings);
  }

  Future<void> _applySettings() async {
    try {
      // Validate input
      final apiUrl = _cleanUrlFormat(_apiUrlController.text.trim());
      final printerAddress = _printerAddressController.text.trim();
      final printerPortStr = _printerPortController.text.trim();
      final fetchIntervalStr = _fetchRemoteOrdersIntervalController.text.trim();
      final matchIntervalStr = _orderMatchCheckIntervalController.text.trim();

      if (apiUrl.isEmpty || printerAddress.isEmpty) return;

      final printerPort = int.tryParse(printerPortStr);
      final fetchRemoteOrdersInterval = int.tryParse(fetchIntervalStr);
      final orderMatchCheckInterval = int.tryParse(matchIntervalStr);

      if (printerPort == null || printerPort <= 0 || printerPort > 65535) return;
      if (fetchRemoteOrdersInterval == null || fetchRemoteOrdersInterval <= 0) return;
      if (orderMatchCheckInterval == null || orderMatchCheckInterval <= 0) return;

      // Update settings
      final updatedSettings = _settings.copyWith(
        apiServerUrl: apiUrl,
        printerAddress: printerAddress,
        printerPort: printerPort,
        fetchRemoteOrdersIntervalSeconds: fetchRemoteOrdersInterval,
        orderMatchCheckIntervalMinutes: orderMatchCheckInterval,
      );

      // Check if anything actually changed
      if (updatedSettings == _settings) return;

      // 保存设置到本地存储
      await _settingsService.saveSettings(updatedSettings);
      ApiService().updateBaseUrl(apiUrl); 

      // 立即应用设置到服务
      _syncService.configureBaseUrl(apiUrl);
      _printService.configurePrinter(
        printerIP: printerAddress,
        printerPort: printerPort,
      );

      // 立即按最新设置刷新后台任务间隔
      await BackgroundTaskManager().refreshScheduledTasks();

      if (mounted) {
        setState(() {
          _settings = updatedSettings;
        });
      }
      _logger.i('Settings auto-applied');
    } catch (e) {
      _logger.e('Failed to auto-apply settings: $e');
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isTestingConnection = true);
    try {
      final isConnected = await _syncService.checkNetworkConnectivity();
      if (isConnected) {
        _showSuccessSnackBar('API connection successful');
      } else {
        _showErrorSnackBar('API connection failed');
      }
    } catch (e) {
      _showErrorSnackBar('Connection test failed: $e');
    } finally {
      setState(() => _isTestingConnection = false);
    }
  }

  Future<void> _testPrinter() async {
    setState(() => _isTestingPrinter = true);
    try {
      final isReady = await _printService.checkPrinterStatus();
      if (isReady) {
        _showSuccessSnackBar('Printer connection successful');
      } else {
        _showErrorSnackBar('Printer connection failed');
      }
    } catch (e) {
      _showErrorSnackBar('Printer test failed: $e');
    } finally {
      setState(() => _isTestingPrinter = false);
    }
  }

  Future<void> _saveStoreHoursToServer() async {
    if (_storeHours == null) return;
    try {
      await _settingsService.updateStoreHours(_storeHours!);
      // _showSuccessSnackBar('Store hours updated successfully');
    } catch (e) {
      _logger.e('Failed to update store hours: $e');
      _showErrorSnackBar('Failed to update store hours: $e');
    }
  }

  Future<void> _resetSettings() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Settings'),
        content: const Text('Are you sure you want to reset all settings to defaults?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _settingsService.resetToDefaults();
      await _loadSettings();
      _showSuccessSnackBar('Settings reset to defaults');
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('退出登录'),
        content: Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('退出'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final box = await Hive.openBox('authBox');
      await box.delete('authToken');
      await box.delete('savedUsername');
      await box.delete('savedPassword');
      await box.delete('rememberMe');
      ApiService().setAuthToken(''); // 清除ApiService的token
      await AppInitializationService.stopBackgroundTasksAndNetworkListener();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => InternalApp()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: _resetSettings,
            tooltip: 'Reset to defaults',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // API Server Section
            _buildSectionCard(
              title: 'API Server Configuration',
              icon: Icons.cloud,
              children: [
                TextFormField(
                  controller: _apiUrlController,
                  decoration: const InputDecoration(
                    labelText: 'API Server URL',
                    hintText: 'http://127.0.0.1:8000/api/',
                    prefixIcon: Icon(Icons.language),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  onChanged: (val) => _onSettingsChanged(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isTestingConnection ? null : _testConnection,
                        icon: _isTestingConnection
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.wifi_find),
                        label: Text(_isTestingConnection ? 'Testing...' : 'Test Connection'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Enable Auto Sync'),
                  subtitle: const Text('Automatically sync orders to server'),
                  value: _settings.enableAutoSync,
                  onChanged: (value) async {
                    setState(() {
                      _settings = _settings.copyWith(enableAutoSync: value);
                    });
                    await _settingsService.updateAutoFeatures(enableAutoSync: value);
                    await BackgroundTaskManager().refreshScheduledTasks();
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Background Tasks Configuration Section
            _buildSectionCard(
              title: 'Background Tasks Configuration',
              icon: Icons.schedule,
              children: [
                const Text(
                  'Configure the intervals for background tasks',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _fetchRemoteOrdersIntervalController,
                  decoration: const InputDecoration(
                    labelText: 'Fetch Remote Orders Interval (seconds)',
                    hintText: '5',
                    prefixIcon: Icon(Icons.cloud_download),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (val) => _onSettingsChanged(),
                ),
                const SizedBox(height: 12),
                 TextFormField(
                    controller: _orderMatchCheckIntervalController,
                    decoration: const InputDecoration(
                      labelText: 'Order Match Check Interval (minutes)',
                      hintText: '5',
                      prefixIcon: Icon(Icons.update),
                      border: OutlineInputBorder(),
                      helperText: 'Interval to verify local orders match server data',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (val) => _onSettingsChanged(),
                  ),
               ],
             ),

             const SizedBox(height: 24),

             _buildTaskStatusSection(),

             const SizedBox(height: 24),

             _buildStoreHoursSection(),

             const SizedBox(height: 24),
             _buildSectionCard(
               title: 'Printer Configuration',
               icon: Icons.print,
               children: [
                DropdownButtonFormField<String>(
                  value: _settings.printerType,
                  decoration: const InputDecoration(
                    labelText: 'Printer Type',
                    prefixIcon: Icon(Icons.print),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'network', child: Text('Network Printer')),
                    // DropdownMenuItem(value: 'usb', child: Text('USB Printer')),
                    // DropdownMenuItem(value: 'bluetooth', child: Text('Bluetooth Printer')),
                  ],
                  onChanged: (value) async {
                    if (value != null) {
                      setState(() {
                        _settings = _settings.copyWith(printerType: value);
                      });
                      await _applySettings();
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _printerAddressController,
                  decoration: InputDecoration(
                    labelText: _settings.printerType == 'network' ? 'IP Address' : 'Address',
                    hintText: _settings.printerType == 'network' ? '192.168.1.100' : 'Printer address',
                    prefixIcon: const Icon(Icons.location_on),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (val) => _onSettingsChanged(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _printerPortController,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '9100',
                    prefixIcon: Icon(Icons.settings_ethernet),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  enabled: _settings.printerType == 'network',
                  onChanged: (val) => _onSettingsChanged(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isTestingPrinter ? null : _testPrinter,
                        icon: _isTestingPrinter
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.print_outlined),
                        label: Text(_isTestingPrinter ? 'Testing...' : 'Test Printer'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Enable Auto Print'),
                  subtitle: const Text('Automatically print orders after placing'),
                  value: _settings.enableAutoPrint,
                  onChanged: (value) async {
                    final updatedSettings = _settings.copyWith(enableAutoPrint: value);
                    setState(() {
                      _settings = updatedSettings;
                    });
                    await _settingsService.updateAutoFeatures(enableAutoPrint: value);
                    await BackgroundTaskManager().refreshScheduledTasks();
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),
            // 退出登录按钮
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text('LOG OUT'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskStatusSection() {
    if (_taskStatus == null) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      child: ExpansionTile(
        leading: Icon(
          _taskStatus!.isInitialized ? Icons.check_circle : Icons.warning,
          color: _taskStatus!.isInitialized ? Colors.green : Colors.orange,
        ),
        title: const Text(
          'Task Manager Status',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          _taskStatus!.isInitialized ? 'Running' : 'Not Initialized',
          style: TextStyle(fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.all(16),
        children: [
          _buildStatusRow(
            'Store Hours Status',
            _taskStatus!.isWithinStoreHours ? 'Within Hours' : 'Outside Hours (Paused)',
            _taskStatus!.isWithinStoreHours ? Colors.green : Colors.orange,
          ),
          _buildStatusRow(
            'Foreground Fetch Service',
            _taskStatus!.isForegroundRunning ? 'Active' : 'Stopped',
            _taskStatus!.isForegroundRunning ? Colors.green : Colors.red,
          ),
          if (_taskStatus!.foregroundIntervalSeconds != null)
            _buildStatusRow(
              '  - Interval',
              '${_taskStatus!.foregroundIntervalSeconds} seconds',
              Colors.grey,
            ),
          const Divider(),
          ..._taskStatus!.activeTasks.entries.map((e) => _buildStatusRow(
                e.key,
                e.value ? 'Active' : 'Inactive',
                e.value ? Colors.blue : Colors.grey,
              )),
          if (_taskStatus!.notificationPermission != null ||
              _taskStatus!.batteryOptimizationExempt != null) ...[
            const Divider(),
            const Text('Permissions (Android)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            _buildStatusRow(
              'Notification Permission',
              _taskStatus!.notificationPermission == true ? 'Granted' : 'Denied',
              _taskStatus!.notificationPermission == true ? Colors.green : Colors.red,
            ),
            if (_taskStatus!.batteryOptimizationExempt != null)
              _buildStatusRow(
                'Battery Optimization',
                _taskStatus!.batteryOptimizationExempt == true ? 'Exempted' : 'Optimizing',
                _taskStatus!.batteryOptimizationExempt == true ? Colors.green : Colors.orange,
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await BackgroundTaskManager().refreshScheduledTasks();
                _showSuccessSnackBar('Permission request triggered');
              },
              icon: const Icon(Icons.security),
              label: const Text('Request/Refresh Permissions'),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Last updated: ${DateTime.now().toString().split('.')[0]}',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14)),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: valueColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: valueColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildStoreHoursSection() {
    if (_storeHours == null) return const SizedBox.shrink();
    return Card(
      elevation: 2,
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.access_time, color: Colors.blue),
        title: const Text(
          'Store Hours Configuration',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildDayRow('Monday', _storeHours!.weeklySchedule.monday, (val) {
            setState(() {
              _storeHours = _storeHours!.copyWith(
                weeklySchedule: _storeHours!.weeklySchedule.copyWith(monday: val),
              );
            });
            _saveStoreHoursToServer();
          }),
          _buildDayRow('Tuesday', _storeHours!.weeklySchedule.tuesday, (val) {
            setState(() {
              _storeHours = _storeHours!.copyWith(
                weeklySchedule: _storeHours!.weeklySchedule.copyWith(tuesday: val),
              );
            });
            _saveStoreHoursToServer();
          }),
          _buildDayRow('Wednesday', _storeHours!.weeklySchedule.wednesday, (val) {
            setState(() {
              _storeHours = _storeHours!.copyWith(
                weeklySchedule: _storeHours!.weeklySchedule.copyWith(wednesday: val),
              );
            });
            _saveStoreHoursToServer();
          }),
          _buildDayRow('Thursday', _storeHours!.weeklySchedule.thursday, (val) {
            setState(() {
              _storeHours = _storeHours!.copyWith(
                weeklySchedule: _storeHours!.weeklySchedule.copyWith(thursday: val),
              );
            });
            _saveStoreHoursToServer();
          }),
          _buildDayRow('Friday', _storeHours!.weeklySchedule.friday, (val) {
            setState(() {
              _storeHours = _storeHours!.copyWith(
                weeklySchedule: _storeHours!.weeklySchedule.copyWith(friday: val),
              );
            });
            _saveStoreHoursToServer();
          }),
          _buildDayRow('Saturday', _storeHours!.weeklySchedule.saturday, (val) {
            setState(() {
              _storeHours = _storeHours!.copyWith(
                weeklySchedule: _storeHours!.weeklySchedule.copyWith(saturday: val),
              );
            });
            _saveStoreHoursToServer();
          }),
          _buildDayRow('Sunday', _storeHours!.weeklySchedule.sunday, (val) {
            setState(() {
              _storeHours = _storeHours!.copyWith(
                weeklySchedule: _storeHours!.weeklySchedule.copyWith(sunday: val),
              );
            });
            _saveStoreHoursToServer();
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildDayRow(String day, DaySchedule schedule, Function(DaySchedule) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(day, style: const TextStyle(fontWeight: FontWeight.w500))),
          Switch(
            value: schedule.enabled,
            onChanged: (val) {
              onChanged(schedule.copyWith(enabled: val));
            },
          ),
          Expanded(
            flex: 4,
            child: InkWell(
              onTap: schedule.enabled ? () => _editDaySchedule(day, schedule, onChanged) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  schedule.enabled
                      ? schedule.ranges.map((r) => '${r.start}-${r.end}').join(', ')
                      : 'Closed',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: schedule.enabled ? Colors.black87 : Colors.grey),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _editDaySchedule(String day, DaySchedule schedule, Function(DaySchedule) onChanged) async {
    List<TimeRange> editingRanges = List.from(schedule.ranges);
    if (editingRanges.isEmpty) {
      editingRanges.add(TimeRange(start: '11:00', end: '21:00'));
    }
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit $day Hours'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...editingRanges.asMap().entries.map((entry) {
                    int index = entry.key;
                    TimeRange range = entry.value;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: _parseTime(range.start),
                                    initialEntryMode: TimePickerEntryMode.input,
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      editingRanges[index] = TimeRange(
                                        start: '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
                                        end: range.end,
                                      );
                                    });
                                  }
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Start', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                    Text(range.start, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: _parseTime(range.end),
                                    initialEntryMode: TimePickerEntryMode.input,
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      editingRanges[index] = TimeRange(
                                        start: range.start,
                                        end: '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
                                      );
                                    });
                                  }
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const Text('End', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                    Text(range.end, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () {
                                setDialogState(() {
                                  editingRanges.removeAt(index);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  if (editingRanges.length < 5) // Limit to 5 ranges per day
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: TextButton.icon(
                        onPressed: () {
                          setDialogState(() {
                            editingRanges.add(TimeRange(start: '11:00', end: '21:00'));
                          });
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add Time Range'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                onChanged(schedule.copyWith(ranges: editingRanges));
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  TimeOfDay _parseTime(String time) {
    try {
      final parts = time.split(':');
      if (parts.length != 2) return TimeOfDay(hour: 11, minute: 0);
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (e) {
      return TimeOfDay(hour: 11, minute: 0);
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
