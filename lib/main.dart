import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';
import 'common/models/menu_item_adapter.dart';
import 'common/models/category_adapter.dart';
import 'common/models/menu_option.dart';
import 'common/models/option_groups_adapter.dart';
import 'common/services/api_service.dart';
import 'common/models/menu_item.dart';
import 'common/models/category.dart';
import 'common/services/app_initialization_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(MenuItemAdapterAdapter());
  Hive.registerAdapter(CategoryAdapterAdapter());
  Hive.registerAdapter(MenuOptionAdapter());
  Hive.registerAdapter(OptionGroupsAdapterAdapter());

  // 预先打开所有需要的 Hive 盒子
  await Hive.openBox<MenuItemAdapter>('productsBox');
  await Hive.openBox<CategoryAdapter>('categoriesBox');
  await Hive.openBox<OptionGroupsAdapter>('optionGroupsBox');

  // 应用启动时获取最新数据
  await _fetchInitialData();

  // 使用应用初始化包装器启动应用
  runApp(const AppInitializationPage(
    child: OmneasApp(),
  ));
}

/// 应用启动时获取所有数据
Future<void> _fetchInitialData() async {
  try {
    print('[DEBUG] 🚀 应用启动，开始获取最新数据...');

    final api = ApiService();

    // 并行获取所有数据
    final results = await Future.wait([
      api.get('products/active'),
      api.get('categories/active'),
      api.get('attributes/group'),
    ]);

    final prodRes = results[0];
    final catRes = results[1];
    final optRes = results[2];

    // 处理产品和分类数据
    final prodData = prodRes.data['data'] as List;
    final catData = catRes.data['data'] as List;
    final products = prodData.map((e) => MenuItem.fromJson(e)).toList();
    products.sort((a, b) => a.sort.compareTo(b.sort));
    final categories = catData.map((e) => Category.fromJson(e)).toList();

    // 处理选项数据
    final optData = optRes.data['data'] as Map<String, dynamic>;
    final optionGroups = optData.map((type, list) => MapEntry(
      type,
      (list as List).map((e) => MenuOption.fromJson(e)).toList(),
    ));

    // 保存产品和分类到本地
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

    // 保存选项到本地
    final optionGroupsBox = Hive.box<OptionGroupsAdapter>('optionGroupsBox');
    await optionGroupsBox.put('groups', OptionGroupsAdapter(groups: optionGroups));

    print('[DEBUG] ✅ 应用启动数据获取完成');
    print('[DEBUG] - 产品数量: ${products.length}');
    print('[DEBUG] - 分类数量: ${categories.length}');
    print('[DEBUG] - 选项组数量: ${optionGroups.length}');

  } catch (e) {
    print('[DEBUG] ❌ 应用启动数据获取失败: $e');
    print('[DEBUG] 将使用本地缓存数据（如果有的话）');
  }
}
