import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'app.dart';
import 'common/models/menu_item_adapter.dart';
import 'common/models/category_adapter.dart';
import 'common/models/menu_option.dart';
import 'common/models/option_groups_adapter.dart';
import 'common/services/app_initialization_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化前台服务通信端口（须在 runApp 之前调用）
  FlutterForegroundTask.initCommunicationPort();
  await Hive.initFlutter();
  Hive.registerAdapter(MenuItemAdapterAdapter());
  Hive.registerAdapter(CategoryAdapterAdapter());
  Hive.registerAdapter(MenuOptionAdapter());
  Hive.registerAdapter(OptionGroupsAdapterAdapter());

  // 直接清理旧的 Hive 缓存，避免旧数据在启动时触发解析崩溃
  await Hive.deleteBoxFromDisk('productsBox');
  await Hive.deleteBoxFromDisk('categoriesBox');
  await Hive.deleteBoxFromDisk('optionGroupsBox');

  // 预先打开所有需要的 Hive 盒子
  await Hive.openBox<MenuItemAdapter>('productsBox');
  await Hive.openBox<CategoryAdapter>('categoriesBox');
  await Hive.openBox<OptionGroupsAdapter>('optionGroupsBox');

  // 使用应用初始化包装器启动应用（数据库、设置、Token恢复、初始数据拉取及后台任务均在包装器内部有序初始化）
  runApp(const AppInitializationPage(
    child: OmneasApp(),
  ));
}
