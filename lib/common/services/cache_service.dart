import 'package:hive/hive.dart';
import '../models/menu_item_adapter.dart';
import '../models/category_adapter.dart';
import '../models/option_groups_adapter.dart';

/// 缓存服务类，用于管理和刷新本地Hive缓存
class CacheService {
  static const String _productsBoxName = 'productsBox';
  static const String _categoriesBoxName = 'categoriesBox';
  static const String _optionGroupsBoxName = 'optionGroupsBox';

  /// 清空菜品缓存
  static Future<void> clearProductsCache() async {
    try {
      if (Hive.isBoxOpen(_productsBoxName)) {
        final box = Hive.box<MenuItemAdapter>(_productsBoxName);
        await box.clear();
      }
    } catch (e) {
      print('[DEBUG] 清空菜品缓存失败: $e');
    }
  }

  /// 清空分类缓存
  static Future<void> clearCategoriesCache() async {
    try {
      if (Hive.isBoxOpen(_categoriesBoxName)) {
        final box = Hive.box<CategoryAdapter>(_categoriesBoxName);
        await box.clear();
      }
    } catch (e) {
      print('[DEBUG] 清空分类缓存失败: $e');
    }
  }

  /// 清空选项缓存
  static Future<void> clearOptionsCache() async {
    try {
      if (Hive.isBoxOpen(_optionGroupsBoxName)) {
        final box = Hive.box<OptionGroupsAdapter>(_optionGroupsBoxName);
        await box.clear();
      }
    } catch (e) {
      print('[DEBUG] 清空选项缓存失败: $e');
    }
  }

  /// 清空所有缓存（菜品、分类、选项）
  static Future<void> clearAllCaches() async {
    await clearProductsCache();
    await clearCategoriesCache();
    await clearOptionsCache();
  }

  /// 清空菜品和分类缓存（用于菜品编辑后）
  static Future<void> clearMenuCaches() async {
    await clearProductsCache();
    await clearCategoriesCache();
  }
}

