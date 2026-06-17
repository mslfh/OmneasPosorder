import 'package:hive/hive.dart';
import '../../common/models/menu_item.dart';
import '../../common/models/category.dart';
import '../../common/models/menu_option.dart';
import '../../common/models/menu_item_adapter.dart';
import '../../common/models/category_adapter.dart';
import '../../common/models/option_groups_adapter.dart';
import '../../common/services/api_service.dart';
import '../../common/services/cache_service.dart';

/// 菜品数据加载服务
class MenuDataService {
  final ApiService _apiService = ApiService();

  /// 加载菜品和分类数据（优先使用本地缓存）
  Future<Map<String, dynamic>> loadMenuData() async {
    try {
      final productsBox = await Hive.openBox<MenuItemAdapter>('productsBox');
      final categoriesBox = await Hive.openBox<CategoryAdapter>('categoriesBox');

      if (productsBox.isEmpty || categoriesBox.isEmpty) {
        print('[DEBUG] 缓存为空，从API获取数据');
        return await _fetchMenuDataFromApi();
      } else {
        final allProducts = productsBox.values.map((e) => e.toMenuItem()).toList();
        final products = _sortProducts(List<MenuItem>.from(allProducts));
        final categories = categoriesBox.values.map((e) => e.toCategory()).toList();
        print('[DEBUG] 使用本地缓存数据，菜品数量: ${products.length}，分类数量: ${categories.length}');
        return {
          'allProducts': allProducts,
          'products': products,
          'categories': categories,
          'error': null,
        };
      }
    } catch (e) {
      print('[ERROR] 加载菜品数据失败: $e');
      return {
        'allProducts': [],
        'products': [],
        'categories': [],
        'error': e.toString(),
      };
    }
  }

  /// 从API获取菜品数据
  Future<Map<String, dynamic>> _fetchMenuDataFromApi() async {
    try {
      final prodRes = await _apiService.get('products/active');
      final catRes = await _apiService.get('categories/active');

      final prodDataRaw = prodRes.data['data'];
      List prodData;
      if (prodDataRaw is List) {
        prodData = prodDataRaw;
      } else {
        print('[ERROR] products/active 返回的 data 不是 List');
        prodData = [];
      }

      final catData = catRes.data['data'] as List;
      final allProducts = prodData
          .where((e) => e is Map<String, dynamic>)
          .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
          .toList();
      final products = _sortProducts(List<MenuItem>.from(allProducts));
      final categories = catData.map((e) => Category.fromJson(e)).toList();

      // 保存到本地缓存
      await _saveToCacheBoxes(products, categories);

      return {
        'allProducts': allProducts,
        'products': products,
        'categories': categories,
        'error': null,
      };
    } catch (e) {
      print('[ERROR] API获取菜品数据失败: $e');
      return {
        'allProducts': [],
        'products': [],
        'categories': [],
        'error': e.toString(),
      };
    }
  }

  /// 加载菜品选项
  Future<Map<String, List<MenuOption>>> loadOptions() async {
    try {
      Box<OptionGroupsAdapter> optionGroupsBox;
      if (Hive.isBoxOpen('optionGroupsBox')) {
        optionGroupsBox = Hive.box<OptionGroupsAdapter>('optionGroupsBox');
      } else {
        optionGroupsBox = await Hive.openBox<OptionGroupsAdapter>('optionGroupsBox');
      }

      final adapter = optionGroupsBox.get('groups');
      if (adapter != null && adapter.groups.isNotEmpty) {
        print('[DEBUG] ✅ 使用本地缓存的 optionGroups，组数: ${adapter.groups.length}');
        return adapter.groups;
      }
      print('[DEBUG] 选项配置缓存为空，从API获取数据');
      return await _fetchOptionsFromApi();
    } catch (e) {
      print('[DEBUG] ❌ loadOptions 出错: $e');
      return await _fetchOptionsFromApi();
    }
  }

  /// 从API获取选项
  Future<Map<String, List<MenuOption>>> _fetchOptionsFromApi() async {
    try {
      final api = ApiService();
      final response = await api.get('options/group');
      final data = response.data['data'] as Map<String, dynamic>;
      final groups = data.map((type, list) => MapEntry(
        type,
        (list as List).map((e) => MenuOption.fromJson(e)).toList(),
      ));

      final optionGroupsBox = Hive.box<OptionGroupsAdapter>('optionGroupsBox');
      await optionGroupsBox.put('groups', OptionGroupsAdapter(groups: groups));

      return groups;
    } catch (e) {
      print('[ERROR] 获取选项失败: $e');
      return {};
    }
  }

  /// 保存菜品和分类到本地缓存
  Future<void> _saveToCacheBoxes(List<MenuItem> products, List<Category> categories) async {
    try {
      final productsBox = Hive.box<MenuItemAdapter>('productsBox');
      final categoriesBox = Hive.box<CategoryAdapter>('categoriesBox');
      await productsBox.clear();
      await categoriesBox.clear();
      for (var item in products) {
        await productsBox.add(MenuItemAdapter.fromMenuItem(item));
      }
      for (var cat in categories) {
        await categoriesBox.add(CategoryAdapter.fromCategory(cat));
      }
    } catch (e) {
      print('[ERROR] 保存缓存失败: $e');
    }
  }

  /// 菜品排序
  List<MenuItem> _sortProducts(List<MenuItem> products) {
    products.sort((a, b) {
      int cmp = a.sort.compareTo(b.sort);
      if (cmp != 0) return cmp;
      return a.code.compareTo(b.code);
    });
    return products;
  }

  /// 获取分类下的菜品
  List<MenuItem> getProductsByCategory(List<MenuItem> allProducts, int categoryId) {
    final filtered =
        allProducts.where((item) => item.categoryIds.contains(categoryId)).toList();
    return _sortProducts(filtered);
  }

  /// 清除所有缓存
  Future<void> clearAllCaches() async {
    await CacheService.clearMenuCaches();
    await CacheService.clearOptionsCache();
  }
}

