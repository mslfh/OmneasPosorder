import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:hive/hive.dart';
import 'dart:async';
import '../../common/models/app_settings.dart';
import '../../common/models/merchant_info.dart';
import '../../common/services/settings_service.dart';
import '../../common/services/background_task_manager.dart';
import '../../common/services/api_service.dart';
import '../../common/services/app_initialization_service.dart';
import '../../common/services/language_service.dart';
import '../../common/models/store_hours_config.dart';
import '../internal_app.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final Logger _logger = Logger();
  final SettingsService _settingsService = SettingsService();

  late AppSettings _settings;
  StoreHoursConfig? _storeHours;
  MerchantInfo? _merchantInfo;
  TaskStatusReport? _taskStatus;
  bool _isLoading = true;

  Timer? _statusRefreshTimer;

  String _tr(String key) => LanguageService().tr(key);

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
    _statusRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      await _settingsService.initialize();
      _settings = _settingsService.getSettings();
      _storeHours = await _settingsService.fetchStoreHours(forceRefresh: true);
      _merchantInfo = await _settingsService.fetchMerchantInfo(forceRefresh: true);

      setState(() => _isLoading = false);
    } catch (e) {
      _logger.e('Failed to load settings: $e');
      _showErrorSnackBar('Failed to load settings: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveStoreHoursToServer() async {
    if (_storeHours == null) return;
    try {
      await _settingsService.updateStoreHours(_storeHours!);
    } catch (e) {
      _logger.e('Failed to update store hours: $e');
      _showErrorSnackBar('Failed to update store hours: $e');
    }
  }

  Future<void> _resetSettings() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_tr('reset_confirm_title')),
        content: Text(_tr('reset_confirm_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: Text(_tr('reset')),
          ),
        ],
      ),
    );

    if (result == true) {
      await _settingsService.resetToDefaults();
      await _loadSettings();
      _showSuccessSnackBar(_tr('reset_settings'));
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_tr('logout_confirm_title')),
        content: Text(_tr('logout_confirm_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: Text(_tr('logout')),
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
      ApiService().setAuthToken('');
      await AppInitializationService.stopBackgroundTasksAndNetworkListener();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const InternalApp()),
        (route) => false,
      );
    }
  }

  void _showLanguageDialog() {
    final currentLang = LanguageService().currentLanguage;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(_tr('select_language'), style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLanguageOptionTile(
                title: '简体中文',
                subtitle: 'Simplified Chinese',
                code: 'zh',
                isSelected: currentLang == 'zh',
              ),
              const Divider(height: 1),
              _buildLanguageOptionTile(
                title: 'English',
                subtitle: 'English (US)',
                code: 'en',
                isSelected: currentLang == 'en',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLanguageOptionTile({
    required String title,
    required String subtitle,
    required String code,
    required bool isSelected,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      title: Text(title, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF2563EB)) : null,
      onTap: () async {
        Navigator.pop(context);
        if (!isSelected) {
          LanguageService().changeLanguage(code);
          setState(() {
            _settings = _settings.copyWith(language: code);
          });
          await _settingsService.saveSettings(_settings);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(_tr('settings_title'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          _tr('settings_title'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: const Icon(Icons.restore, color: Colors.grey),
            onPressed: _resetSettings,
            tooltip: _tr('reset_settings'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. General Settings Group (Language)
            _buildSectionGroup(
              title: _tr('section_general'),
              icon: Icons.tune_rounded,
              iconColor: const Color(0xFF2563EB),
              children: [
                _buildClickableTile(
                  icon: Icons.language_rounded,
                  iconBgColor: const Color(0xFFEFF6FF),
                  iconColor: const Color(0xFF2563EB),
                  title: _tr('language_setting'),
                  valueText: _tr('language_name'),
                  onTap: _showLanguageDialog,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 2. Merchant Profile Configuration
            if (_merchantInfo != null) _buildMerchantProfileDashboard(),

            const SizedBox(height: 16),

            // 3. Task Status Monitoring
            if (_taskStatus != null) _buildTaskStatusDashboard(),

            const SizedBox(height: 16),

            // 4. Store Hours Configuration
            if (_storeHours != null) _buildStoreHoursDashboard(),

            const SizedBox(height: 24),

            // 4. Logout Danger Zone
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded),
                label: Text(_tr('logout')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionGroup({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildClickableTile({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String valueText,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
            ),
            Text(
              valueText,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskStatusDashboard() {
    final status = _taskStatus!;
    final isRun = status.isInitialized;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isRun ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isRun ? Icons.check_circle_rounded : Icons.warning_rounded,
              color: isRun ? const Color(0xFF16A34A) : const Color(0xFFD97706),
              size: 20,
            ),
          ),
          title: Text(
            _tr('task_status_title'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          subtitle: Text(
            isRun ? _tr('status_running') : _tr('status_stopped'),
            style: TextStyle(fontSize: 12, color: isRun ? const Color(0xFF16A34A) : Colors.orange),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                children: [
                  const Divider(),
                  _buildStatusRow(
                    'Store Hours Status',
                    status.isWithinStoreHours ? _tr('within_hours') : _tr('outside_hours'),
                    status.isWithinStoreHours ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                  ),
                  _buildStatusRow(
                    _tr('foreground_service'),
                    status.isForegroundRunning ? _tr('status_active') : _tr('status_stopped'),
                    status.isForegroundRunning ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  ),
                  if (status.foregroundIntervalSeconds != null)
                    _buildStatusRow(
                      '  Interval',
                      '${status.foregroundIntervalSeconds} ${_tr('fetch_interval_unit')}',
                      Colors.grey.shade600,
                    ),
                  const Divider(),
                  ...status.activeTasks.entries.map((e) => _buildStatusRow(
                        e.key,
                        e.value ? _tr('status_active') : _tr('status_inactive'),
                        e.value ? const Color(0xFF0284C7) : Colors.grey,
                      )),
                  if (status.notificationPermission != null || status.batteryOptimizationExempt != null) ...[
                    const Divider(),
                    if (status.notificationPermission != null)
                      _buildStatusRow(
                        'Notification Permission',
                        status.notificationPermission == true ? 'Granted' : 'Denied',
                        status.notificationPermission == true ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                      ),
                    if (status.batteryOptimizationExempt != null)
                      _buildStatusRow(
                        'Battery Optimization',
                        status.batteryOptimizationExempt == true ? 'Exempted' : 'Optimizing',
                        status.batteryOptimizationExempt == true ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await BackgroundTaskManager().refreshScheduledTasks();
                          _showSuccessSnackBar(_tr('permission_triggered'));
                        },
                        icon: const Icon(Icons.security_rounded, size: 18),
                        label: Text(_tr('permission_request')),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.black87)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: valueColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
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

  Widget _buildStoreHoursDashboard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.access_time_filled_rounded, color: Color(0xFFD97706), size: 20),
          ),
          title: Text(
            _tr('section_store_hours'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                children: [
                  const Divider(),
                  _buildDayRow(_tr('monday'), _storeHours!.weeklySchedule.monday, (val) {
                    setState(() {
                      _storeHours = _storeHours!.copyWith(
                        weeklySchedule: _storeHours!.weeklySchedule.copyWith(monday: val),
                      );
                    });
                    _saveStoreHoursToServer();
                  }),
                  _buildDayRow(_tr('tuesday'), _storeHours!.weeklySchedule.tuesday, (val) {
                    setState(() {
                      _storeHours = _storeHours!.copyWith(
                        weeklySchedule: _storeHours!.weeklySchedule.copyWith(tuesday: val),
                      );
                    });
                    _saveStoreHoursToServer();
                  }),
                  _buildDayRow(_tr('wednesday'), _storeHours!.weeklySchedule.wednesday, (val) {
                    setState(() {
                      _storeHours = _storeHours!.copyWith(
                        weeklySchedule: _storeHours!.weeklySchedule.copyWith(wednesday: val),
                      );
                    });
                    _saveStoreHoursToServer();
                  }),
                  _buildDayRow(_tr('thursday'), _storeHours!.weeklySchedule.thursday, (val) {
                    setState(() {
                      _storeHours = _storeHours!.copyWith(
                        weeklySchedule: _storeHours!.weeklySchedule.copyWith(thursday: val),
                      );
                    });
                    _saveStoreHoursToServer();
                  }),
                  _buildDayRow(_tr('friday'), _storeHours!.weeklySchedule.friday, (val) {
                    setState(() {
                      _storeHours = _storeHours!.copyWith(
                        weeklySchedule: _storeHours!.weeklySchedule.copyWith(friday: val),
                      );
                    });
                    _saveStoreHoursToServer();
                  }),
                  _buildDayRow(_tr('saturday'), _storeHours!.weeklySchedule.saturday, (val) {
                    setState(() {
                      _storeHours = _storeHours!.copyWith(
                        weeklySchedule: _storeHours!.weeklySchedule.copyWith(saturday: val),
                      );
                    });
                    _saveStoreHoursToServer();
                  }),
                  _buildDayRow(_tr('sunday'), _storeHours!.weeklySchedule.sunday, (val) {
                    setState(() {
                      _storeHours = _storeHours!.copyWith(
                        weeklySchedule: _storeHours!.weeklySchedule.copyWith(sunday: val),
                      );
                    });
                    _saveStoreHoursToServer();
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayRow(String day, DaySchedule schedule, Function(DaySchedule) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(day, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          Switch.adaptive(
            value: schedule.enabled,
            onChanged: (val) {
              onChanged(schedule.copyWith(enabled: val));
            },
            activeColor: const Color(0xFF2563EB),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: InkWell(
              onTap: schedule.enabled ? () => _editDaySchedule(day, schedule, onChanged) : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: schedule.enabled ? const Color(0xFFEFF6FF) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  schedule.enabled
                      ? schedule.ranges.map((r) => '${r.start}-${r.end}').join(', ')
                      : _tr('closed'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: schedule.enabled ? const Color(0xFF2563EB) : Colors.grey,
                  ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('${_tr('edit_hours')} - $day'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...editingRanges.asMap().entries.map((entry) {
                    int index = entry.key;
                    TimeRange range = entry.value;
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
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
                                  Text('Start', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  Text(range.start, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
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
                                  Text('End', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  Text(range.end, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                            onPressed: () {
                              setDialogState(() {
                                editingRanges.removeAt(index);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                  if (editingRanges.length < 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: TextButton.icon(
                        onPressed: () {
                          setDialogState(() {
                            editingRanges.add(TimeRange(start: '11:00', end: '21:00'));
                          });
                        },
                        icon: const Icon(Icons.add_rounded),
                        label: Text(_tr('add_time_range')),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(_tr('cancel'))),
            ElevatedButton(
              onPressed: () {
                onChanged(schedule.copyWith(ranges: editingRanges));
                Navigator.pop(context);
              },
              child: Text(_tr('confirm')),
            ),
          ],
        ),
      ),
    );
  }

  TimeOfDay _parseTime(String time) {
    try {
      final parts = time.split(':');
      if (parts.length != 2) return const TimeOfDay(hour: 11, minute: 0);
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (e) {
      return const TimeOfDay(hour: 11, minute: 0);
    }
  }

  Widget _buildMerchantProfileDashboard() {
    final merchant = _merchantInfo!;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.storefront_rounded, color: Color(0xFF0284C7), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _tr('section_merchant'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_rounded, color: Color(0xFF2563EB), size: 20),
                  onPressed: _editMerchantProfile,
                  tooltip: _tr('edit_merchant'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildMerchantDetailRow(Icons.business_rounded, _tr('merchant_name'), merchant.name),
                const SizedBox(height: 8),
                _buildMerchantDetailRow(Icons.location_on_rounded, _tr('merchant_address'), merchant.address),
                const SizedBox(height: 8),
                _buildMerchantDetailRow(Icons.phone_rounded, _tr('merchant_phone'), merchant.phone),
                const SizedBox(height: 8),
                _buildMerchantDetailRow(Icons.receipt_long_rounded, _tr('merchant_abn'), merchant.abn),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMerchantDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(
            value.isNotEmpty ? value : '-',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
        ),
      ],
    );
  }

  void _editMerchantProfile() {
    if (_merchantInfo == null) return;
    final nameController = TextEditingController(text: _merchantInfo!.name);
    final addressController = TextEditingController(text: _merchantInfo!.address);
    final phoneController = TextEditingController(text: _merchantInfo!.phone);
    final abnController = TextEditingController(text: _merchantInfo!.abn);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(_tr('edit_merchant'), style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: _tr('merchant_name'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.storefront_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: _tr('merchant_address'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.location_on_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: InputDecoration(
                    labelText: _tr('merchant_phone'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.phone_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: abnController,
                  decoration: InputDecoration(
                    labelText: _tr('merchant_abn'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.receipt_long_rounded),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_tr('cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final newInfo = MerchantInfo(
                  name: nameController.text.trim(),
                  address: addressController.text.trim(),
                  phone: phoneController.text.trim(),
                  abn: abnController.text.trim(),
                );
                Navigator.pop(context);
                await _saveMerchantInfoToServer(newInfo);
              },
              child: Text(_tr('confirm')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveMerchantInfoToServer(MerchantInfo newMerchantInfo) async {
    try {
      await _settingsService.updateMerchantInfo(newMerchantInfo);
      setState(() {
        _merchantInfo = newMerchantInfo;
      });
      _showSuccessSnackBar(_tr('merchant_save_success'));
    } catch (e) {
      _logger.e('Failed to update merchant info: $e');
      _showErrorSnackBar('Failed to update merchant info: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
