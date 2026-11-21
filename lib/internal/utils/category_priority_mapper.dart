import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import '../../common/models/category.dart';
import '../../common/models/menu_item_adapter.dart';
import '../../common/services/database_service.dart';

class CategoryPriorityMapper {
  static final Logger _logger = Logger();
  static const String _settingKey = 'category_print_priorities';

  // 用户自定义分类打印优先级表 <categoryId, priority>
  static final Map<int, int> _categoryPriorities = {};
  static bool _isLoaded = false;

  /// 加载分类打印优先级配置
  static Future<void> loadPriorities() async {
    if (_isLoaded) return;
    try {
      final jsonStr = await DatabaseService().getSetting(_settingKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        _categoryPriorities.clear();
        decoded.forEach((key, value) {
          final id = int.tryParse(key);
          final priority = int.tryParse(value.toString());
          if (id != null && priority != null) {
            _categoryPriorities[id] = priority;
          }
        });
      }
    } catch (e) {
      _logger.e('加载分类打印优先级配置异常: $e');
    } finally {
      _isLoaded = true;
    }
  }

  /// 保存分类打印优先级到数据库
  static Future<void> _savePriorities() async {
    try {
      final mapToSave = _categoryPriorities.map((id, p) => MapEntry(id.toString(), p));
      final jsonStr = jsonEncode(mapToSave);
      await DatabaseService().saveSetting(_settingKey, jsonStr);
    } catch (e) {
      _logger.e('保存分类打印优先级配置异常: $e');
    }
  }

  /// 获取指定 categoryId 的打印优先级（数字越小优先级越高，默认 999）
  static int getPriorityForCategoryId(int categoryId) {
    return _categoryPriorities[categoryId] ?? 999;
  }

  /// 获取指定 Category 对象的打印优先级
  static int getPriorityForCategory(Category category) {
    return getPriorityForCategoryId(category.id);
  }

  /// 获取菜品的打印优先级（属于多个分类时取最小的优先级数值）
  static int getItemPriority(
    Map<String, dynamic> item, {
    Map<int, List<int>>? productCategoryMap,
  }) {
    final categoryIds = <int>[];

    if (item['category_ids'] is List) {
      categoryIds.addAll(
        (item['category_ids'] as List)
            .map((e) => int.tryParse(e.toString()) ?? 0)
            .where((e) => e != 0),
      );
    } else if (item['category_id'] != null) {
      final id = int.tryParse(item['category_id'].toString());
      if (id != null && id != 0) categoryIds.add(id);
    }

    if (categoryIds.isEmpty && productCategoryMap != null) {
      final productId = int.tryParse((item['id'] ?? item['product_id'])?.toString() ?? '');
      if (productId != null && productCategoryMap.containsKey(productId)) {
        categoryIds.addAll(productCategoryMap[productId]!);
      }
    }

    if (categoryIds.isEmpty) return 999;

    int minPriority = 999;
    for (int id in categoryIds) {
      final p = getPriorityForCategoryId(id);
      if (p < minPriority) {
        minPriority = p;
      }
    }
    return minPriority;
  }

  /// 设置分类打印优先级（传入 null 或 <= 0 则恢复默认）
  static Future<void> setCategoryPriority(int categoryId, int? priority) async {
    if (priority == null || priority <= 0) {
      _categoryPriorities.remove(categoryId);
    } else {
      _categoryPriorities[categoryId] = priority;
    }
    await _savePriorities();
  }

  /// 判断指定分类是否有设置打印优先级
  static bool hasCustomPriority(int categoryId) {
    return _categoryPriorities.containsKey(categoryId);
  }

  /// 依据分类打印优先级对后厨菜品列表进行排序（保持相同优先级的原始书写顺序）
  static Future<List<dynamic>> sortItemsByPriority(List<dynamic> items) async {
    if (items.isEmpty) return items;
    await loadPriorities();

    Map<int, List<int>> productCategoryMap = {};
    try {
      if (Hive.isBoxOpen('productsBox')) {
        final box = Hive.box<MenuItemAdapter>('productsBox');
        for (var adapter in box.values) {
          productCategoryMap[adapter.id] = adapter.categoryIds;
        }
      } else {
        final box = await Hive.openBox<MenuItemAdapter>('productsBox');
        for (var adapter in box.values) {
          productCategoryMap[adapter.id] = adapter.categoryIds;
        }
      }
    } catch (_) {}

    final indexedItems = items.asMap().entries.toList();

    indexedItems.sort((a, b) {
      final itemA = a.value is Map<String, dynamic>
          ? a.value as Map<String, dynamic>
          : Map<String, dynamic>.from(a.value as Map);
      final itemB = b.value is Map<String, dynamic>
          ? b.value as Map<String, dynamic>
          : Map<String, dynamic>.from(b.value as Map);

      final priorityA = getItemPriority(itemA, productCategoryMap: productCategoryMap);
      final priorityB = getItemPriority(itemB, productCategoryMap: productCategoryMap);

      final cmp = priorityA.compareTo(priorityB);
      if (cmp != 0) return cmp;
      return a.key.compareTo(b.key);
    });

    return indexedItems.map((e) => e.value).toList();
  }
}
