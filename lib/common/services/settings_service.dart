import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import '../models/app_settings.dart';

class SettingsService {
  static final Logger _logger = Logger();
  static const String _boxName = 'settings';
  static const String _settingsKey = 'app_settings';

  // 单例模式
  static SettingsService? _instance;
  SettingsService._internal();

  factory SettingsService() {
    _instance ??= SettingsService._internal();
    return _instance!;
  }

  Box<AppSettings>? _settingsBox;

  /// 初始化设置服务
  Future<void> initialize() async {
    try {
      // 注册Hive适配器
      if (!Hive.isAdapterRegistered(10)) {
        Hive.registerAdapter(AppSettingsAdapter());
      }

      // 打开设置盒子
      _settingsBox = await Hive.openBox<AppSettings>(_boxName);
      _logger.i('Settings service initialized');
    } catch (e) {
      _logger.e('Failed to initialize settings service: $e');
      rethrow;
    }
  }

  /// 获取当前设置
  AppSettings getSettings() {
    try {
      final settings = _settingsBox?.get(_settingsKey);
      return settings ?? AppSettings();
    } catch (e) {
      _logger.e('Failed to get settings: $e');
      return AppSettings();
    }
  }

  /// 保存设置
  Future<void> saveSettings(AppSettings settings) async {
    try {
      await _settingsBox?.put(_settingsKey, settings);
      _logger.i('Settings saved successfully');
    } catch (e) {
      _logger.e('Failed to save settings: $e');
      rethrow;
    }
  }

  /// 更新API服务器地址
  Future<void> updateApiServerUrl(String url) async {
    final currentSettings = getSettings();
    final updatedSettings = currentSettings.copyWith(apiServerUrl: url);
    await saveSettings(updatedSettings);
  }

  /// 更新打印机配置
  Future<void> updatePrinterConfig({
    String? address,
    int? port,
    String? type,
  }) async {
    final currentSettings = getSettings();
    final updatedSettings = currentSettings.copyWith(
      printerAddress: address,
      printerPort: port,
      printerType: type,
    );
    await saveSettings(updatedSettings);
  }

  /// 更新自动功能开关
  Future<void> updateAutoFeatures({
    bool? enableAutoSync,
    bool? enableAutoPrint,
  }) async {
    final currentSettings = getSettings();
    final updatedSettings = currentSettings.copyWith(
      enableAutoSync: enableAutoSync,
      enableAutoPrint: enableAutoPrint,
    );
    await saveSettings(updatedSettings);
  }

  /// 重置为默认设置
  Future<void> resetToDefaults() async {
    await saveSettings(AppSettings());
    _logger.i('Settings reset to defaults');
  }

  /// 关闭服务
  Future<void> close() async {
    await _settingsBox?.close();
    _logger.i('Settings service closed');
  }
}
