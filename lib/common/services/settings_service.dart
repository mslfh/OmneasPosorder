import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import '../models/app_settings.dart';
import '../models/store_hours_config.dart';
import 'api_service.dart';

class SettingsService {
  static final Logger _logger = Logger();
  static const String _boxName = 'settings';
  static const String _settingsKey = 'app_settings';

  final ApiService _apiService = ApiService();

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

      // 打开已有设置盒子；如果不存在则创建
      _settingsBox = Hive.isBoxOpen(_boxName)
          ? Hive.box<AppSettings>(_boxName)
          : await Hive.openBox<AppSettings>(_boxName);

      // 确保设置存在，并补齐缺失字段
      final currentSettings = _settingsBox?.get(_settingsKey);
      final effectiveSettings = (currentSettings ?? AppSettings()).migrateIfNeeded();
      await _settingsBox?.put(_settingsKey, effectiveSettings);

      _logger.i('Settings service initialized successfully');
    } catch (e) {
      _logger.e('Failed to initialize settings service: $e');
      rethrow;
    }
  }

  /// 获取当前设置
  AppSettings getSettings() {
    try {
      final settings = _settingsBox?.get(_settingsKey);
      if (settings == null) {
        _logger.i('No settings found, returning default');
        return AppSettings();
      }
      return settings;
    } catch (e) {
      _logger.e('Error getting settings: $e');
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

  /// 更新API服务器地址（去除末尾的 /）
  Future<void> updateApiServerUrl(String url) async {
    final currentSettings = getSettings();
    final cleanUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final updatedSettings = currentSettings.copyWith(apiServerUrl: cleanUrl);
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

  /// 更新后台任务间隔配置
  Future<void> updateTaskIntervals({
    int? syncTaskIntervalMinutes,
    int? fetchRemoteOrdersIntervalSeconds,
    int? printRetryTaskIntervalMinutes,
    int? orderMatchCheckIntervalMinutes,
  }) async {
    final currentSettings = getSettings();
    final updatedSettings = currentSettings.copyWith(
      syncTaskIntervalMinutes: syncTaskIntervalMinutes,
      fetchRemoteOrdersIntervalSeconds: fetchRemoteOrdersIntervalSeconds,
      printRetryTaskIntervalMinutes: printRetryTaskIntervalMinutes,
      orderMatchCheckIntervalMinutes: orderMatchCheckIntervalMinutes,
    );
    await saveSettings(updatedSettings);
  }

  /// 获取营业时间配置
  Future<StoreHoursConfig> fetchStoreHours() async {
    final Box<String> cacheBox = await Hive.openBox<String>('store_hours_cache');
    
    // 1. 优先读取本地缓存并准备返回
    StoreHoursConfig? cachedConfig;
    final cachedData = cacheBox.get('config');
    if (cachedData != null) {
      try {
        cachedConfig = StoreHoursConfig.fromJson(jsonDecode(cachedData));
      } catch (e) {
        _logger.e('Error decoding cached store hours: $e');
      }
    }

    // 2. 异步触发网络更新（不阻塞本次读取）
    _refreshStoreHoursInBackground(cacheBox);

    // 3. 返回缓存，若无缓存则返回默认值（直到后台更新完成）
    if (cachedConfig != null) {
      _logger.d('Returning cached store hours');
      return cachedConfig;
    }

    _logger.w('No cache found, using defaults until background refresh completes');
    return StoreHoursConfig.defaults();
  }

  /// 后台刷新营业时间并更新缓存
  Future<void> _refreshStoreHoursInBackground(Box<String> cacheBox) async {
    try {
      final response = await _apiService.get('system-setting/store-hours');
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final valueStr = data['value'];
        if (valueStr != null) {
          final dynamic valueJson = valueStr is String ? jsonDecode(valueStr) : valueStr;
          await cacheBox.put('config', jsonEncode(valueJson));
          _logger.i('Store hours cache updated from server');
        }
      }
    } catch (e) {
      _logger.w('Background store hours refresh failed: $e');
    }
  }

  /// 更新营业时间配置
  Future<void> updateStoreHours(StoreHoursConfig config) async {
    try {
      final configJson = config.toJson();
      final data = {
        'value': jsonEncode(configJson),
        'description': 'Store hours configuration',
        'type': 'json',
      };
      
      // 更新本地缓存
      final Box<String> cacheBox = await Hive.openBox<String>('store_hours_cache');
      await cacheBox.put('config', jsonEncode(configJson));

      final response = await _apiService.put('system-setting/store-hours', data: data);
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to update store hours: ${response.statusCode}');
      }
      _logger.i('Store hours updated successfully');
    } catch (e) {
      _logger.e('Error updating store hours: $e');
      rethrow;
    }
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
