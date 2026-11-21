import 'dart:convert';
import 'package:logger/logger.dart';
import '../../common/models/category.dart';
import '../../common/services/database_service.dart';

class CategoryDisplaySortMapper {
  static final Logger _logger = Logger();
  static const String _settingKey = 'category_display_sort_orders';

  // 用户自定义分类界面显示排序表 <categoryId, sortOrder>
  static final Map<int, int> _categoryDisplaySortOrders = {};
  static bool _isLoaded = false;

  /// 加载分类显示排序配置
  static Future<void> loadDisplaySortOrders() async {
    if (_isLoaded) return;
    try {
      final jsonStr = await DatabaseService().getSetting(_settingKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        _categoryDisplaySortOrders.clear();
        decoded.forEach((key, value) {
          final id = int.tryParse(key);
          final sortOrder = int.tryParse(value.toString());
          if (id != null && sortOrder != null) {
            _categoryDisplaySortOrders[id] = sortOrder;
          }
        });
      }
    } catch (e) {
      _logger.e('加载分类显示排序配置异常: $e');
    } finally {
      _isLoaded = true;
    }
  }

  /// 保存分类显示排序到数据库
  static Future<void> _saveDisplaySortOrders() async {
    try {
      final mapToSave = _categoryDisplaySortOrders.map((id, s) => MapEntry(id.toString(), s));
      final jsonStr = jsonEncode(mapToSave);
      await DatabaseService().saveSetting(_settingKey, jsonStr);
    } catch (e) {
      _logger.e('保存分类显示排序配置异常: $e');
    }
  }

  /// 获取指定 categoryId 的界面显示排序（数字越小越靠前，默认 999）
  static int getDisplaySortForCategoryId(int categoryId) {
    return _categoryDisplaySortOrders[categoryId] ?? 999;
  }

  /// 获取指定 Category 对象的界面显示排序
  static int getDisplaySortForCategory(Category category) {
    return getDisplaySortForCategoryId(category.id);
  }

  /// 设置分类界面显示排序（传入 null 或 <= 0 则恢复默认）
  static Future<void> setCategoryDisplaySort(int categoryId, int? sortOrder) async {
    if (sortOrder == null || sortOrder <= 0) {
      _categoryDisplaySortOrders.remove(categoryId);
    } else {
      _categoryDisplaySortOrders[categoryId] = sortOrder;
    }
    await _saveDisplaySortOrders();
  }

  /// 判断指定分类是否有设置自定义界面显示排序
  static bool hasCustomDisplaySort(int categoryId) {
    return _categoryDisplaySortOrders.containsKey(categoryId);
  }
}
