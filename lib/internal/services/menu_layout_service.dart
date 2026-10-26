import 'dart:convert';
import 'package:logger/logger.dart';
import '../../common/models/menu_item_layout_config.dart';
import '../../common/services/database_service.dart';

/// 菜品网格布局持久化与数据服务
class MenuLayoutService {
  static final Logger _logger = Logger();
  static const String _layoutSettingKey = 'menu_grid_layout_configs';
  static Map<int, MenuItemLayoutConfig>? _cachedConfigs;

  /// 加载所有保存的菜品网格布局配置
  static Future<Map<int, MenuItemLayoutConfig>> loadLayoutConfigs() async {
    if (_cachedConfigs != null) {
      return Map.from(_cachedConfigs!);
    }

    try {
      final jsonString = await DatabaseService().getSetting(_layoutSettingKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonString);
        final map = <int, MenuItemLayoutConfig>{};
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final config = MenuItemLayoutConfig.fromJson(item);
            map[config.menuItemId] = config;
          }
        }
        _cachedConfigs = map;
        return Map.from(map);
      }
    } catch (e) {
      _logger.e('加载网格布局配置异常: $e');
    }

    _cachedConfigs = {};
    return {};
  }

  /// 保存所有菜品网格布局配置
  static Future<void> saveLayoutConfigs(Map<int, MenuItemLayoutConfig> configs) async {
    _cachedConfigs = Map.from(configs);
    try {
      final jsonList = configs.values.map((c) => c.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      await DatabaseService().saveSetting(_layoutSettingKey, jsonString);
    } catch (e) {
      _logger.e('保存网格布局配置异常: $e');
    }
  }

  /// 保存/更新单个菜品网格布局配置
  static Future<void> saveSingleConfig(MenuItemLayoutConfig config) async {
    final current = await loadLayoutConfigs();
    current[config.menuItemId] = config;
    await saveLayoutConfigs(current);
  }

  /// 清空并重置所有网格布局配置（恢复默认布局）
  static Future<void> clearLayoutConfigs() async {
    _cachedConfigs = {};
    try {
      await DatabaseService().saveSetting(_layoutSettingKey, '[]');
    } catch (e) {
      _logger.e('清空网格布局配置异常: $e');
    }
  }
}
