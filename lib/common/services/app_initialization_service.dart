import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:hive/hive.dart';
import 'database_service.dart';
import 'background_task_manager.dart';
import 'settings_service.dart';
import 'sync_service.dart';
import 'print_service.dart';
import '../models/menu_item_adapter.dart';
import '../models/category_adapter.dart';
import '../models/option_groups_adapter.dart';
import 'dart:io';

class AppInitializationService {
  static final Logger _logger = Logger();
  static bool _isInitialized = false;

  /// 初始化应用
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _logger.i('开始初始化应用...');

      // 1. 清空Hive缓存 - 确保每次重启都重新获取数据
      await _clearHiveCache();

      // 2. 初始化数据库
      await _initializeDatabase();

      // 3. 初始化后台任务管理器
      await _initializeBackgroundTasks();

      // 4. 启动网络监听
      _startNetworkListener();

      _isInitialized = true;
      _logger.i('应用初始化完成');

    } catch (e) {
      _logger.e('应用初始化失败: $e');
      rethrow;
    }
  }

  /// 清空Hive缓存
  static Future<void> _clearHiveCache() async {
    try {
      _logger.i('清空Hive缓存...');

      // 清空菜品缓存
      if (Hive.isBoxOpen('productsBox')) {
        final productsBox = Hive.box<MenuItemAdapter>('productsBox');
        await productsBox.clear();
        _logger.i('已清空菜品缓存');
      } else {
        try {
          final productsBox = await Hive.openBox<MenuItemAdapter>('productsBox');
          await productsBox.clear();
          _logger.i('已清空菜品缓存');
        } catch (e) {
          _logger.w('无法打开菜品缓存box: $e');
        }
      }

      // 清空分类缓存
      if (Hive.isBoxOpen('categoriesBox')) {
        final categoriesBox = Hive.box<CategoryAdapter>('categoriesBox');
        await categoriesBox.clear();
        _logger.i('已清空分类缓存');
      } else {
        try {
          final categoriesBox = await Hive.openBox<CategoryAdapter>('categoriesBox');
          await categoriesBox.clear();
          _logger.i('已清空分类缓存');
        } catch (e) {
          _logger.w('无法打开分类缓存box: $e');
        }
      }

      // 清空选项配置缓存
      if (Hive.isBoxOpen('optionGroupsBox')) {
        final optionGroupsBox = Hive.box<OptionGroupsAdapter>('optionGroupsBox');
        await optionGroupsBox.clear();
        _logger.i('已清空选项配置缓存');
      } else {
        try {
          final optionGroupsBox = await Hive.openBox<OptionGroupsAdapter>('optionGroupsBox');
          await optionGroupsBox.clear();
          _logger.i('已清空选项配置缓存');
        } catch (e) {
          _logger.w('无法打开选项配置缓存box: $e');
        }
      }

      _logger.i('Hive缓存清空完成');
    } catch (e) {
      _logger.e('清空Hive缓存失败: $e');
      // 清空缓存失败不应该阻止应用启动
      _logger.w('继续启动应用，但缓存可能包含旧数据');
    }
  }

  /// 初始化数据库
  static Future<void> _initializeDatabase() async {
    try {
      _logger.i('初始化数据库...');
      final databaseService = DatabaseService();

      // 确保数据库正确创建
      await databaseService.database;

      // 执行数据库维护任务
      await databaseService.cleanOldLogs();

      // 初始化设置服务
      final settingsService = SettingsService();
      await settingsService.initialize();

      // 加载设置并应用到服务
      final settings = settingsService.getSettings();
      final syncService = SyncService();
      final printService = PrintService();

      // 应用API服务器设置
      syncService.configureBaseUrl(settings.apiServerUrl);
      _logger.i('Applied API server URL: ${settings.apiServerUrl}');

      // 应用打印机设置
      printService.configurePrinter(
        printerIP: settings.printerAddress,
        printerPort: settings.printerPort,
      );
      _logger.i('Applied printer config: ${settings.printerAddress}:${settings.printerPort}');

      _logger.i('数据库初始化完成');
    } catch (e) {
      _logger.e('数据库初始化失败: $e');
      rethrow;
    }
  }

  /// 初始化后台任务
  static Future<void> _initializeBackgroundTasks() async {
    try {
      _logger.i('初始化后台任务管理器...');

      // 检查是否是移动平台（workmanager只在移动平台支持）
      if (Platform.isAndroid || Platform.isIOS) {
        final taskManager = BackgroundTaskManager();
        await taskManager.initialize();
        _logger.i('后台任务管理器初始化完成');
      } else {
        _logger.i('桌面平台跳过后台任务管理器初始化');
      }

    } catch (e) {
      _logger.e('后台任务管理器初始化失败: $e');
      // 后台任务失败不应该阻止应用启动
      _logger.w('继续启动应用，但后台任务可能不可用');
    }
  }

  /// 启动网络监听
  static void _startNetworkListener() {
    try {
      _logger.i('启动网络状态监听...');
      NetworkStatusListener.startListening();
    } catch (e) {
      _logger.e('网络监听启动失败: $e');
    }
  }

  /// 应用关闭时的清理工作
  static Future<void> dispose() async {
    try {
      _logger.i('开始应用清理...');

      // 停止网络监听
      NetworkStatusListener.stopListening();

      // 关闭数据库连接
      final databaseService = DatabaseService();
      await databaseService.close();

      _logger.i('应用清理完成');
    } catch (e) {
      _logger.e('应用清理失败: $e');
    }
  }
}

/// 应用启动页面，负责初始化和启动画面
class AppInitializationPage extends StatefulWidget {
  final Widget child;

  const AppInitializationPage({Key? key, required this.child}) : super(key: key);

  @override
  _AppInitializationPageState createState() => _AppInitializationPageState();
}

class _AppInitializationPageState extends State<AppInitializationPage> {
  bool _isInitializing = true;
  String _initializationStatus = '正在初始化...';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _initializationStatus = '正在初始化数据库...';
      });

      await Future.delayed(Duration(milliseconds: 500)); // 让用户看到状态

      setState(() {
        _initializationStatus = '正在设置后台任务...';
      });

      await AppInitializationService.initialize();

      setState(() {
        _initializationStatus = '初始化完成';
        _isInitializing = false;
      });

    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isInitializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
                SizedBox(height: 24),
                Text(
                  _initializationStatus,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  SizedBox(height: 24),
                  Text(
                    '初始化失败',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isInitializing = true;
                        _errorMessage = null;
                        _initializationStatus = '正在重新初始化...';
                      });
                      _initializeApp();
                    },
                    child: Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}
