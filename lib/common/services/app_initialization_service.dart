import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:hive/hive.dart';
import 'database_service.dart';
import 'background_task_manager.dart';
import 'settings_service.dart';
import 'api_service.dart';
import '../../internal/services/menu_data_service.dart';

class AppInitializationService {
  static final Logger _logger = Logger();
  static bool _isInitialized = false;

  /// 初始化应用（包含数据库、设置服务、Auth Token恢复、初始数据同步及后台任务）
  static Future<void> initialize({void Function(String status)? onStatusUpdate}) async {
    if (_isInitialized) return;
    try {
      _logger.i('开始初始化应用...');

      // 1. 初始化数据库及设置服务
      onStatusUpdate?.call('正在初始化数据库及设置...');
      await _initializeDatabase();

      // 2. 恢复 Auth Token 到 ApiService
      try {
        final box = await Hive.openBox('authBox');
        final token = box.get('authToken');
        if (token != null && token is String && token.isNotEmpty) {
          ApiService().setAuthToken(token);
        }
      } catch (e) {
        _logger.w('恢复 Auth Token 失败: $e');
      }

      // 3. 应用启动时同步获取最新菜单数据
      onStatusUpdate?.call('正在获取最新数据...');
      await _fetchInitialData();

      // 4. 初始化后台任务管理器
      onStatusUpdate?.call('正在初始化后台服务...');
      await _initializeBackgroundTasks();

      _isInitialized = true;
      _logger.i('应用初始化完成');
    } catch (e) {
      _logger.e('应用初始化失败: $e');
      rethrow;
    }
  }

  /// 启动网络拉取等初始数据
  static Future<void> _fetchInitialData() async {
    try {
      _logger.i('🚀 应用启动，开始获取最新数据...');
      await MenuDataService().fetchAndCacheInitialData();
      _logger.i('✅ 应用启动数据获取完成');
    } catch (e) {
      _logger.w('❌ 应用启动数据获取失败: $e');
      _logger.i('将使用本地缓存数据（如果有的话）');
    }
  }

  /// 登录后启动后台任务和网络监听
  static Future<void> startBackgroundTasksAndNetworkListener() async {
    await _initializeBackgroundTasks();
    _startNetworkListener();
    _logger.i('后台任务和网络监听已启动');
  }

  /// 退出登录时停止后台任务和网络监听
  static Future<void> stopBackgroundTasksAndNetworkListener() async {
    try {
      await BackgroundTaskManager().cancelAllTasks();
      NetworkStatusListener.stopListening();
      _logger.i('后台任务和网络监听已停止');
    } catch (e) {
      _logger.e('停止后台任务和网络监听失败: $e');
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

      // 初始化设置服务（内部会自动将配置应用到 SyncService, PrintService, ApiService）
      final settingsService = SettingsService();
      await settingsService.initialize();

      _logger.i('数据库及设置初始化完成');
    } catch (e) {
      _logger.e('数据库初始化失败: $e');
      rethrow;
    }
  }

  /// 初始化后台任务
  static Future<void> _initializeBackgroundTasks() async {
    try {
      _logger.i('初始化后台任务管理器...');

      final taskManager = BackgroundTaskManager();
      await taskManager.initialize();
      _logger.i('后台任务管理器初始化完成');
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

  const AppInitializationPage({super.key, required this.child});

  @override
  State<AppInitializationPage> createState() => _AppInitializationPageState();
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
        _initializationStatus = '正在初始化系统设置...';
      });

      await AppInitializationService.initialize(
        onStatusUpdate: (status) {
          if (mounted) {
            setState(() {
              _initializationStatus = status;
            });
          }
        },
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw Exception('应用初始化超时（> 25 秒）。请检查设备网络、存储权限或日志'),
      );

      if (mounted) {
        setState(() {
          _initializationStatus = '初始化完成';
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isInitializing = false;
        });
      }
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
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
                const SizedBox(height: 24),
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
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '初始化失败',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isInitializing = true;
                        _errorMessage = null;
                        _initializationStatus = '正在重新初始化...';
                      });
                      _initializeApp();
                    },
                    child: const Text('重试'),
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
