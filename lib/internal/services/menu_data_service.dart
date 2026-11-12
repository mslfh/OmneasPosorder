import 'package:flutter/foundation.dart' hide Category;
import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import '../../common/models/menu_item.dart';
import '../../common/models/category.dart';
import '../../common/models/menu_option.dart';
import '../../common/models/menu_item_adapter.dart';
import '../../common/models/category_adapter.dart';
import '../../common/models/option_groups_adapter.dart';
import '../../common/services/api_service.dart';
import '../../common/services/cache_service.dart';
import '../../common/services/kitchen_split_service.dart';

/// 菜品数据加载服务
class MenuDataService {
  static final Logger _logger = Logger();
  final ApiService _apiService = ApiService();

  /// 初始网络数据同步与缓存写入（供应用启动或强制全量同步时调用）
  Future<void> fetchAndCacheInitialData() async {
    try {
      final results = await Future.wait([
        _apiService.get('products/active'),
        _apiService.get('categories/active'),
        _apiService.get('options/group'),
      ]);

      final prodRes = results[0];
      final catRes = results[1];
      final optRes = results[2];

      final prodDataRaw = prodRes.data['data'];
      final catDataRaw = catRes.data['data'];
      final optDataRaw = optRes.data['data'];

      if (prodDataRaw is List && catDataRaw is List) {
        final products = prodDataRaw
            .whereType<Map<String, dynamic>>()
            .map((e) => MenuItem.fromJson(e))
            .toList();
        final categories = catDataRaw
            .whereType<Map<String, dynamic>>()
            .map((e) => Category.fromJson(e))
            .toList();

        final sortedProducts = _sortProducts(products);
        await _saveToCacheBoxes(sortedProducts, categories);
      }

      if (optDataRaw is Map<String, dynamic>) {
        final optionGroups = optDataRaw.map((type, list) => MapEntry(
          type,
          (list as List).map((e) => MenuOption.fromJson(e)).toList(),
        ));

        Box<OptionGroupsAdapter> optionGroupsBox;
        if (Hive.isBoxOpen('optionGroupsBox')) {
          optionGroupsBox = Hive.box<OptionGroupsAdapter>('optionGroupsBox');
        } else {
          optionGroupsBox = await Hive.openBox<OptionGroupsAdapter>('optionGroupsBox');
        }
        await optionGroupsBox.put('groups', OptionGroupsAdapter(groups: optionGroups));
      }
    } catch (e) {
      _logger.e('初始数据同步失败: $e');
      rethrow;
    }
  }

  /// 加载菜品和分类数据（优先使用本地缓存）
  Future<Map<String, dynamic>> loadMenuData() async {
    try {
      final productsBox = await Hive.openBox<MenuItemAdapter>('productsBox');
      final categoriesBox = await Hive.openBox<CategoryAdapter>('categoriesBox');
      final splitMap = await KitchenSplitService().getProductSplitMap();

      if (productsBox.isEmpty || categoriesBox.isEmpty) {
        _logger.d('缓存为空，从API获取数据');
        return await _fetchMenuDataFromApi();
      } else {
        final allProducts = productsBox.values.map((e) {
          final item = e.toMenuItem();
          final splitId = splitMap[item.id] ?? item.splitGroupId;
          return item.copyWith(splitGroupId: splitId);
        }).toList();
        final products = _sortProducts(List<MenuItem>.from(allProducts));
        final categories = categoriesBox.values.map((e) => e.toCategory()).toList();
        _logger.d('使用本地缓存数据，菜品数量: ${products.length}，分类数量: ${categories.length}');
        return {
          'allProducts': allProducts,
          'products': products,
          'categories': categories,
          'error': null,
        };
      }
    } catch (e) {
      _logger.e('加载菜品数据失败: $e');
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
      final splitMap = await KitchenSplitService().getProductSplitMap();

      final prodDataRaw = prodRes.data['data'];
      List prodData;
      if (prodDataRaw is List) {
        prodData = prodDataRaw;
      } else {
        _logger.w('products/active 返回的 data 不是 List');
        prodData = [];
      }

      final catData = catRes.data['data'] as List;
      final allProducts = prodData
          .whereType<Map<String, dynamic>>()
          .map((e) {
            final item = MenuItem.fromJson(e);
            final splitId = splitMap[item.id] ?? item.splitGroupId;
            return item.copyWith(splitGroupId: splitId);
          })
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
      _logger.e('API获取菜品数据失败: $e');
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
        _logger.d('使用本地缓存的 optionGroups，组数: ${adapter.groups.length}');
        return adapter.groups;
      }
      _logger.d('选项配置缓存为空，从API获取数据');
      return await _fetchOptionsFromApi();
    } catch (e) {
      _logger.w('loadOptions 出错: $e');
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
      _logger.e('获取选项失败: $e');
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
      _logger.e('保存缓存失败: $e');
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

  /// 售罄状态推送/更新事件监听器 (通知所有订阅页面实时刷新 UI)
  static final ValueNotifier<Map<String, dynamic>?> soldOutEventNotifier =
      ValueNotifier<Map<String, dynamic>?>(null);

  /// 动态更新单个商品的售罄状态 (更新 Hive 本地缓存并返回最新 MenuItem)
  Future<MenuItem?> updateProductSoldOutStatus({
    required int productId,
    required bool isSoldOut,
    String? soldOutLabel,
  }) async {
    try {
      final productsBox = await Hive.openBox<MenuItemAdapter>('productsBox');

      for (final key in productsBox.keys) {
        final adapter = productsBox.get(key);
        if (adapter != null && adapter.id == productId) {
          adapter.isSoldOut = isSoldOut;
          if (soldOutLabel != null) {
            adapter.soldOutLabel = soldOutLabel;
          }
          await adapter.save();
          _logger.d('已成功更新商品 #$productId 售罄状态: isSoldOut=$isSoldOut, label=$soldOutLabel');
          return adapter.toMenuItem();
        }
      }
      return null;
    } catch (e) {
      _logger.e('更新商品售罄状态失败: $e');
      rethrow;
    }
  }

  /// 当收到后端推送 (WebSocket/SSE/轮询) 改变商品售罄状态时调用的预留方法
  Future<void> onProductSoldOutPushed({
    required int productId,
    required bool isSoldOut,
    String? soldOutLabel,
  }) async {
    final updatedItem = await updateProductSoldOutStatus(
      productId: productId,
      isSoldOut: isSoldOut,
      soldOutLabel: soldOutLabel,
    );

    // 触发全局 ValueNotifier 事件，通知正在显示的 UI 页面实时更新
    soldOutEventNotifier.value = {
      'productId': productId,
      'isSoldOut': isSoldOut,
      'soldOutLabel': soldOutLabel,
      'updatedItem': updatedItem,
      'timestamp': DateTime.now(),
    };
  }
}

