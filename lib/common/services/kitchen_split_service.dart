import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import '../models/kitchen_split_group.dart';
import '../models/menu_item_adapter.dart';
import 'database_service.dart';

class KitchenSplitService {
  static final Logger _logger = Logger();
  final DatabaseService _databaseService = DatabaseService();

  static KitchenSplitService? _instance;
  KitchenSplitService._internal();

  factory KitchenSplitService() {
    _instance ??= KitchenSplitService._internal();
    return _instance!;
  }

  static const String _settingKey = 'kitchen_split_groups';

  /// 获取所有后厨分单打印项
  Future<List<KitchenSplitGroup>> getSplitGroups() async {
    try {
      final jsonStr = await _databaseService.getSetting(_settingKey);
      if (jsonStr == null || jsonStr.trim().isEmpty) {
        return [];
      }
      final List rawList = jsonDecode(jsonStr);
      return rawList.map((e) => KitchenSplitGroup.fromJson(e)).toList();
    } catch (e) {
      _logger.e('读取分单配置失败: $e');
      return [];
    }
  }

  /// 保存后厨分单打印项，并同步更新本地 Hive 商品的分单 ID 缓存
  Future<void> saveSplitGroups(List<KitchenSplitGroup> groups) async {
    try {
      final jsonStr = jsonEncode(groups.map((g) => g.toJson()).toList());
      await _databaseService.saveSetting(_settingKey, jsonStr);

      // 构建 productId -> splitGroupId 的映射
      final Map<int, int> productSplitMap = {};
      for (final group in groups) {
        for (final pId in group.productIds) {
          productSplitMap[pId] = group.id;
        }
      }

      // 同步更新 Hive 缓存 Box
      if (Hive.isBoxOpen('productsBox')) {
        final box = Hive.box<MenuItemAdapter>('productsBox');
        for (final adapter in box.values) {
          final newSplitId = productSplitMap[adapter.id] ?? 0;
          if (adapter.splitGroupId != newSplitId) {
            adapter.splitGroupId = newSplitId;
            await adapter.save();
          }
        }
      }

      _logger.i('分单配置保存成功，分单组数: ${groups.length}');
    } catch (e) {
      _logger.e('保存分单配置失败: $e');
      rethrow;
    }
  }

  /// 获取所有商品的 productId -> splitGroupId 字典映射
  Future<Map<int, int>> getProductSplitMap() async {
    final groups = await getSplitGroups();
    final Map<int, int> resultMap = {};
    for (final group in groups) {
      for (final pId in group.productIds) {
        resultMap[pId] = group.id;
      }
    }
    return resultMap;
  }
}
