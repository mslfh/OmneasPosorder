import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import '../models/app_settings.dart';
import '../models/store_hours_config.dart';
import '../models/merchant_info.dart';
import 'api_service.dart';
import 'database_service.dart';
import 'sync_service.dart';
import 'print_service.dart';
import 'language_service.dart';
import 'package:dio/dio.dart';

class SettingsService {
  static final Logger _logger = Logger();
  static const String _boxName = 'settings';
  static const String _settingsKey = 'app_settings';

  final DatabaseService _databaseService = DatabaseService();

  // 单例模式
  static SettingsService? _instance;
  SettingsService._internal();

  factory SettingsService() {
    _instance ??= SettingsService._internal();
    return _instance!;
  }

  AppSettings _cachedSettings = AppSettings();
  bool _isInitialized = false;

  StoreHoursConfig? _cachedStoreHours;
  DateTime? _lastStoreHoursFetchTime;
  bool _isRefreshingStoreHours = false;
  static const Duration _storeHoursCacheTtl = Duration(minutes: 30);

  MerchantInfo? _cachedMerchantInfo;
  bool _isRefreshingMerchantInfo = false;

  /// 统一处理 URL 规范化格式（去除尾部斜杠，补全 http:// 前缀）
  static String cleanUrlFormat(String url) {
    var trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
    }
    return trimmed;
  }

  /// 初始化设置服务（从数据库读取设置，若数据库为空则从 Hive 迁移）
  Future<void> initialize({bool forceReload = false}) async {
    if (_isInitialized && !forceReload) return;
    try {
      final dbSettings = await _databaseService.getAllSettings();
      AppSettings effectiveSettings;

      if (dbSettings.isEmpty) {
        // 首次从数据库读取为空，尝试从 Hive 或旧配置中迁移
        AppSettings? hiveSettings;
        try {
          if (!Hive.isAdapterRegistered(10)) {
            Hive.registerAdapter(AppSettingsAdapter());
          }
          final box = Hive.isBoxOpen(_boxName)
              ? Hive.box<AppSettings>(_boxName)
              : await Hive.openBox<AppSettings>(_boxName);
          hiveSettings = box.get(_settingsKey);
        } catch (e) {
          _logger.w('Read legacy Hive settings error: $e');
        }

        String? legacyAuthUrl;
        try {
          final authBox = await Hive.openBox('authBox');
          legacyAuthUrl = authBox.get('apiServerUrl') as String?;
        } catch (_) {}

        effectiveSettings = (hiveSettings ?? AppSettings()).migrateIfNeeded();

        final rawUrl = (effectiveSettings.apiServerUrl.isNotEmpty)
            ? effectiveSettings.apiServerUrl
            : (legacyAuthUrl ?? '');

        if (rawUrl.isNotEmpty) {
          effectiveSettings = effectiveSettings.copyWith(
            apiServerUrl: cleanUrlFormat(rawUrl),
          );
        }

        // 将迁移后的设置直接保存到 SQLite 数据库
        await _databaseService.saveSettingsMap(_settingsToMap(effectiveSettings));
        _logger.i('Migrated legacy settings to database successfully');
      } else {
        effectiveSettings = _settingsFromMap(dbSettings).migrateIfNeeded();
      }

      _cachedSettings = effectiveSettings;
      _isInitialized = true;

      // 尝试加载本地存储的商家配置
      final merchantStr = await _databaseService.getSetting('merchant_info');
      if (merchantStr != null && merchantStr.isNotEmpty) {
        try {
          _cachedMerchantInfo = MerchantInfo.fromJson(jsonDecode(merchantStr));
        } catch (e) {
          _logger.w('Parse local merchant info failed: $e');
        }
      }

      // 初始化语言服务
      LanguageService().initialize(effectiveSettings.language);

      // 自动配置各个依赖服务
      _syncServices();

      _logger.i('Settings service initialized successfully from database');
    } catch (e) {
      _logger.e('Failed to initialize settings service: $e');
      rethrow;
    }
  }

  /// 同步基础配置到 ApiService, SyncService, PrintService
  void _syncServices() {
    final apiUrl = _cachedSettings.apiServerUrl;
    ApiService().updateBaseUrlInternal(apiUrl);
    if (apiUrl.isNotEmpty) {
      SyncService().configureBaseUrl(apiUrl);
    }
    PrintService().configurePrinter(
      printerIP: _cachedSettings.printerAddress,
      printerPort: _cachedSettings.printerPort,
    );
  }

  /// 获取当前设置
  AppSettings getSettings() {
    if (!_isInitialized) {
      _logger.w('SettingsService requested before initialize(), returning cached/default');
    }
    return _cachedSettings;
  }

  /// 保存设置到 SQLite 数据库
  Future<void> saveSettings(AppSettings settings) async {
    try {
      final normalizedUrl = cleanUrlFormat(settings.apiServerUrl);
      final normalizedSettings = settings.copyWith(apiServerUrl: normalizedUrl).migrateIfNeeded();

      _cachedSettings = normalizedSettings;
      await _databaseService.saveSettingsMap(_settingsToMap(normalizedSettings));

      _syncServices();
      _logger.i('Settings saved successfully to database');
    } catch (e) {
      _logger.e('Failed to save settings: $e');
      rethrow;
    }
  }

  /// 更新 API 服务器地址（写入数据库）
  Future<void> updateApiServerUrl(String url) async {
    final currentSettings = getSettings();
    final cleanUrl = cleanUrlFormat(url);
    final updatedSettings = currentSettings.copyWith(apiServerUrl: cleanUrl);
    await saveSettings(updatedSettings);
  }

  /// 更新打印机配置（写入数据库）
  Future<void> updatePrinterConfig({
    String? address,
    int? port,
    String? type,
  }) async {
    final currentSettings = getSettings();
    final updatedSettings = currentSettings.copyWith(
      printerAddress: address?.trim(),
      printerPort: port,
      printerType: type,
    );
    await saveSettings(updatedSettings);
  }

  /// 更新自动功能开关（写入数据库）
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

  /// 更新后台任务间隔配置（写入数据库）
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

  /// 获取营业时间配置（含内存缓存与 30 分钟 TTL 过期策略）
  Future<StoreHoursConfig> fetchStoreHours({bool forceRefresh = false}) async {
    final now = DateTime.now();

    // 1. 若已有有效的内存缓存且未过期，且无需强制刷新，直接返回（0 毫秒，无网络/磁盘开销）
    if (!forceRefresh &&
        _cachedStoreHours != null &&
        _lastStoreHoursFetchTime != null &&
        now.difference(_lastStoreHoursFetchTime!) < _storeHoursCacheTtl) {
      return _cachedStoreHours!;
    }

    final Box<String> cacheBox = await Hive.openBox<String>('store_hours_cache');

    // 2. 若内存缓存为空，先尝试读取磁盘缓存
    if (_cachedStoreHours == null) {
      final cachedData = cacheBox.get('config');
      if (cachedData != null) {
        try {
          _cachedStoreHours = StoreHoursConfig.fromJson(jsonDecode(cachedData));
        } catch (e) {
          _logger.e('Error decoding cached store hours: $e');
        }
      }
    }

    // 3. 异步触发网络更新（仅在无缓存、缓存已过期或指定 forceRefresh 时）
    final shouldRefreshNetwork = forceRefresh ||
        _cachedStoreHours == null ||
        _lastStoreHoursFetchTime == null ||
        now.difference(_lastStoreHoursFetchTime!) >= _storeHoursCacheTtl;

    if (shouldRefreshNetwork && !_isRefreshingStoreHours) {
      _refreshStoreHoursInBackground(cacheBox);
    }

    // 4. 返回缓存，若无缓存则返回默认值
    return _cachedStoreHours ?? StoreHoursConfig.defaults();
  }

  /// 后台刷新营业时间并更新缓存
  Future<void> _refreshStoreHoursInBackground(Box<String> cacheBox) async {
    _isRefreshingStoreHours = true;
    try {
      final response = await ApiService().get('system-setting/store-hours');
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final valueStr = data['value'];
        if (valueStr != null) {
          final dynamic valueJson = valueStr is String ? jsonDecode(valueStr) : valueStr;
          final updatedConfig = StoreHoursConfig.fromJson(
              valueJson is Map<String, dynamic> ? valueJson : jsonDecode(valueJson));

          _cachedStoreHours = updatedConfig;
          _lastStoreHoursFetchTime = DateTime.now();

          await cacheBox.put('config', jsonEncode(valueJson));
          _logger.i('Store hours cache updated from server');
        }
      }
    } catch (e) {
      _logger.w('Background store hours refresh failed: $e');
    } finally {
      _isRefreshingStoreHours = false;
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

      // 立即更新内存缓存与时间戳
      _cachedStoreHours = config;
      _lastStoreHoursFetchTime = DateTime.now();

      // 更新本地磁盘缓存
      final Box<String> cacheBox = await Hive.openBox<String>('store_hours_cache');
      await cacheBox.put('config', jsonEncode(configJson));

      final response = await ApiService().put('system-setting/store-hours', data: data);
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to update store hours: ${response.statusCode}');
      }
      _logger.i('Store hours updated successfully');
    } catch (e) {
      _logger.e('Error updating store hours: $e');
      rethrow;
    }
  }

  /// 获取当前内存或缓存中的商家配置
  MerchantInfo getMerchantInfo() {
    return _cachedMerchantInfo ?? MerchantInfo.defaultProfile();
  }

  /// 异步获取/刷新商家信息配置（同步到内存与数据库）
  Future<MerchantInfo> fetchMerchantInfo({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedMerchantInfo != null && !_cachedMerchantInfo!.isEmpty) {
      return _cachedMerchantInfo!;
    }

    final dbValue = await _databaseService.getSetting('merchant_info');
    if (dbValue != null && dbValue.isNotEmpty) {
      try {
        _cachedMerchantInfo = MerchantInfo.fromJson(jsonDecode(dbValue));
      } catch (e) {
        _logger.e('Error decoding local merchant info: $e');
      }
    }

    if (_cachedMerchantInfo == null || _cachedMerchantInfo!.isEmpty) {
      _cachedMerchantInfo = MerchantInfo.defaultProfile();
    }

    if (forceRefresh || !_isRefreshingMerchantInfo) {
      _refreshMerchantInfoInBackground();
    }

    return _cachedMerchantInfo!;
  }

  /// 后台自动同步服务器商家信息
  Future<void> _refreshMerchantInfoInBackground() async {
    _isRefreshingMerchantInfo = true;
    try {
      Response? response;
      try {
        response = await ApiService().get('merchant-info');
      } catch (_) {
        try {
          response = await ApiService().get('get-merchant-info');
        } catch (_) {}
      }

      if (response != null && (response.statusCode == 200 || response.statusCode == 201) && response.data != null) {
        final dynamic rawData = response.data;
        final map = rawData is Map<String, dynamic> ? rawData : jsonDecode(rawData.toString());
        final updatedInfo = MerchantInfo.fromJson(map);

        if (!updatedInfo.isEmpty) {
          _cachedMerchantInfo = updatedInfo;
          await _databaseService.saveSetting('merchant_info', jsonEncode(updatedInfo.toJson()));
          _logger.i('Merchant info updated from server');
        }
      }
    } catch (e) {
      _logger.w('Background merchant info refresh failed: $e');
    } finally {
      _isRefreshingMerchantInfo = false;
    }
  }

  /// 更新商家配置并实时同步保存至本地与服务器
  Future<void> updateMerchantInfo(MerchantInfo info) async {
    try {
      _cachedMerchantInfo = info;
      final jsonMap = info.toJson();

      await _databaseService.saveSetting('merchant_info', jsonEncode(jsonMap));

      final response = await ApiService().put('system-setting/merchant', data: jsonMap);
      if (response.statusCode != 200 && response.statusCode != 201) {
        _logger.w('Server update merchant info returned status: ${response.statusCode}');
      }
      _logger.i('Merchant info saved and synced successfully');
    } catch (e) {
      _logger.e('Error updating merchant info: $e');
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
    _logger.i('Settings service closed');
  }

  // ========== Map 转换辅助函数 ==========

  AppSettings _settingsFromMap(Map<String, String> map) {
    return AppSettings(
      apiServerUrl: map['api_server_url'] ?? '',
      printerAddress: map['printer_address'] ?? '',
      printerPort: int.tryParse(map['printer_port'] ?? '') ?? 9100,
      printerType: map['printer_type'] ?? 'network',
      enableAutoSync: map['enable_auto_sync'] != 'false',
      enableAutoPrint: map['enable_auto_print'] != 'false',
      syncTaskIntervalMinutes: int.tryParse(map['sync_task_interval_minutes'] ?? '') ?? 60,
      fetchRemoteOrdersIntervalSeconds: int.tryParse(map['fetch_remote_orders_interval_seconds'] ?? '') ?? 5,
      printRetryTaskIntervalMinutes: int.tryParse(map['print_retry_task_interval_minutes'] ?? '') ?? 2,
      orderMatchCheckIntervalMinutes: int.tryParse(map['order_match_check_interval_minutes'] ?? '') ?? 5,
      language: map['language'] ?? 'en',
    );
  }

  Map<String, String> _settingsToMap(AppSettings settings) {
    return {
      'api_server_url': settings.apiServerUrl,
      'printer_address': settings.printerAddress,
      'printer_port': settings.printerPort.toString(),
      'printer_type': settings.printerType,
      'enable_auto_sync': settings.enableAutoSync.toString(),
      'enable_auto_print': settings.enableAutoPrint.toString(),
      'sync_task_interval_minutes': settings.syncTaskIntervalMinutes.toString(),
      'fetch_remote_orders_interval_seconds': settings.fetchRemoteOrdersIntervalSeconds.toString(),
      'print_retry_task_interval_minutes': settings.printRetryTaskIntervalMinutes.toString(),
      'order_match_check_interval_minutes': settings.orderMatchCheckIntervalMinutes.toString(),
      'language': settings.language,
    };
  }
}
