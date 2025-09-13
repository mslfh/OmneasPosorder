import 'dart:async';
import 'dart:io';
import 'package:workmanager/workmanager.dart';
import 'package:logger/logger.dart';
import 'order_service.dart';
import 'sync_service.dart';
import 'print_service.dart';

class BackgroundTaskManager {
  static final Logger _logger = Logger();
  static const String syncTaskName = 'order_sync_task';
  static const String printTaskName = 'print_retry_task';
  static const String maintenanceTaskName = 'maintenance_task';
  static const String fetchRemoteOrdersTaskName = 'fetch_remote_orders_task'; // 新增任务名

  // 单例模式
  static BackgroundTaskManager? _instance;
  BackgroundTaskManager._internal();

  factory BackgroundTaskManager() {
    _instance ??= BackgroundTaskManager._internal();
    return _instance!;
  }

  // Windows 平台的定时器
  static Timer? _syncTimer;
  static Timer? _printTimer;
  static Timer? _maintenanceTimer;
  static Timer? _fetchRemoteOrdersTimer; // 新增定时器

  /// 检查是否为移动平台
  bool get _isMobilePlatform => Platform.isAndroid || Platform.isIOS;

  /// 初始化后台任务管理器
  Future<void> initialize() async {
    try {
      if (_isMobilePlatform) {
        // 移动平台使用 workmanager
        await Workmanager().initialize(
          callbackDispatcher,
          isInDebugMode: false,
        );
        await _registerPeriodicTasks();
        _logger.i('移动平台后台任务管理器初始化成功');
      } else {
        // Windows/Web 平台使用定时器
        await _initializeDesktopTasks();
        _logger.i('桌面平台后台任务管理器初始化成功');
      }

    } catch (e) {
      _logger.e('后台任务管理器初始化失败: $e');
    }
  }

  /// 初始化桌面平台任务
  Future<void> _initializeDesktopTasks() async {
    // 同步任务 - 每5分钟执行一次
    _syncTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
      try {
        await _executeSyncTask();
      } catch (e) {
        _logger.e('桌面平台同步任务失败: $e');
      }
    });

    // 拉取服务器新订单任务 - 每5秒执行一次
    _fetchRemoteOrdersTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      try {
        print('拉取服务器新订单任务');
        final syncService = SyncService();
        await syncService.fetchAndSyncRemoteOrders();
      } catch (e) {
        _logger.e('拉取服务器新订单任务失败: $e');
      }
    });

    // 打印重试任务 - 每2分钟执行一次
    _printTimer = Timer.periodic(Duration(minutes: 2), (timer) async {
      try {
        await _executePrintRetryTask();
      } catch (e) {
        _logger.e('桌面平台打印重试任务失败: $e');
      }
    });

    // 维护任务 - 每小时执行一次
    _maintenanceTimer = Timer.periodic(Duration(hours: 1), (timer) async {
      try {
        await _executeMaintenanceTask();
      } catch (e) {
        _logger.e('桌面平台维护任务失败: $e');
      }
    });

    _logger.i('桌面平台定期任务已启动');
  }

  /// 注册定期任务
  Future<void> _registerPeriodicTasks() async {
    try {
      // 同步任务 - 每5分钟检查一次
      await Workmanager().registerPeriodicTask(
        syncTaskName,
        syncTaskName,
        frequency: Duration(minutes: 5),
        constraints: Constraints(
          networkType: NetworkType.connected, // 需要网络连接
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );

      // 打印重试任务 - 每2分钟检查一次
      await Workmanager().registerPeriodicTask(
        printTaskName,
        printTaskName,
        frequency: Duration(minutes: 2),
        constraints: Constraints(
          networkType: NetworkType.not_required, // 打印不需要网络
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );

      // 维护任务 - 每小时执行一次
      await Workmanager().registerPeriodicTask(
        maintenanceTaskName,
        maintenanceTaskName,
        frequency: Duration(hours: 1),
        constraints: Constraints(
          networkType: NetworkType.not_required,
          requiresBatteryNotLow: true, // 电量充足时执行
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: true, // 存储空间充足
        ),
      );

      // 拉取服务器新订单任务 - 每5秒执行一次
      await Workmanager().registerPeriodicTask(
        fetchRemoteOrdersTaskName,
        fetchRemoteOrdersTaskName,
        frequency: Duration(seconds: 5),
        constraints: Constraints(
          networkType: NetworkType.connected, // 需要网络连接
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );

      _logger.i('定期任务注册成功');

    } catch (e) {
      _logger.e('定期任务注册失败: $e');
    }
  }

  /// 立即执行同步任务
  Future<void> triggerSyncTask() async {
    try {
      if (_isMobilePlatform) {
        await Workmanager().registerOneOffTask(
          'immediate_sync_${DateTime.now().millisecondsSinceEpoch}',
          syncTaskName,
          constraints: Constraints(
            networkType: NetworkType.connected,
          ),
        );
        _logger.i('立即同步任务已触发（移动平台）');
      } else {
        // Windows 平台直接执行
        await _executeSyncTask();
        _logger.i('立即同步任务已执行（桌面平台）');
      }
    } catch (e) {
      _logger.e('触发立即同步失败: $e');
    }
  }

  /// 立即执行打印重试任务
  Future<void> triggerPrintRetryTask() async {
    try {
      if (_isMobilePlatform) {
        await Workmanager().registerOneOffTask(
          'immediate_print_${DateTime.now().millisecondsSinceEpoch}',
          printTaskName,
        );
        _logger.i('立即打印重试任务已触发（移动平台）');
      } else {
        // Windows 平台直接执行
        await _executePrintRetryTask();
        _logger.i('立即打印重试任务已执行（桌面平台）');
      }
    } catch (e) {
      _logger.e('触发立即打印重试失败: $e');
    }
  }

  /// 网络恢复时触发同步
  Future<void> onNetworkRestored() async {
    _logger.i('检测到网络恢复，触发同步任务');
    await triggerSyncTask();
  }

  /// 取消所有任务
  Future<void> cancelAllTasks() async {
    try {
      if (_isMobilePlatform) {
        await Workmanager().cancelAll();
        _logger.i('所有后台任务已取消（移动平台）');
      } else {
        // Windows 平台取消定时器
        _syncTimer?.cancel();
        _printTimer?.cancel();
        _maintenanceTimer?.cancel();
        _fetchRemoteOrdersTimer?.cancel(); // 新增取消逻辑
        _syncTimer = null;
        _printTimer = null;
        _maintenanceTimer = null;
        _fetchRemoteOrdersTimer = null;
        _logger.i('所有后台任务已取消（桌面平台）');
      }
    } catch (e) {
      _logger.e('取消后台任务失败: $e');
    }
  }

  /// 取消特定任务
  Future<void> cancelTask(String taskName) async {
    try {
      if (_isMobilePlatform) {
        await Workmanager().cancelByUniqueName(taskName);
        _logger.i('任务已取消: $taskName（移动平台）');
      } else {
        // Windows 平台根据任务名称取消对应定时器
        switch (taskName) {
          case syncTaskName:
            _syncTimer?.cancel();
            _syncTimer = null;
            break;
          case printTaskName:
            _printTimer?.cancel();
            _printTimer = null;
            break;
          case maintenanceTaskName:
            _maintenanceTimer?.cancel();
            _maintenanceTimer = null;
            break;
          case fetchRemoteOrdersTaskName:
            _fetchRemoteOrdersTimer?.cancel();
            _fetchRemoteOrdersTimer = null;
            break;
        }
        _logger.i('任务已取消: $taskName（桌面平台）');
      }
    } catch (e) {
      _logger.e('取消任务失败: $taskName, 错误: $e');
    }
  }
}

/// 后台任务调度器
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final Logger logger = Logger();

    try {
      logger.i('执行后台任务: $task');

      switch (task) {
        case BackgroundTaskManager.syncTaskName:
          await _executeSyncTask();
          break;

        case BackgroundTaskManager.printTaskName:
          await _executePrintRetryTask();
          break;

        case BackgroundTaskManager.maintenanceTaskName:
          await _executeMaintenanceTask();
          break;

        case BackgroundTaskManager.fetchRemoteOrdersTaskName: // 新增任务处理
          final syncService = SyncService();
          await syncService.fetchAndSyncRemoteOrders();
          break;

        default:
          logger.w('未知的后台任务: $task');
          return false;
      }

      logger.i('后台任务执行成功: $task');
      return true;

    } catch (e) {
      logger.e('后台任务执行失败: $task, 错误: $e');
      return false;
    }
  });
}

/// 执行同步任务
Future<void> _executeSyncTask() async {
  final Logger logger = Logger();

  try {
    final syncService = SyncService();

    // 检查网络连接
    final isConnected = await syncService.checkNetworkConnectivity();
    if (!isConnected) {
      logger.w('网络不可用，跳过同步任务');
      return;
    }

    // 执行批量同步
    await syncService.syncPendingOrders();
    logger.i('后台同步任务完成');

  } catch (e) {
    logger.e('后台同步任务失败: $e');
    rethrow;
  }
}

/// 执行打印重试任务
Future<void> _executePrintRetryTask() async {
  final Logger logger = Logger();

  try {
    final printService = PrintService();

    // 检查打印机状态
    final isReady = await printService.checkPrinterStatus();
    if (!isReady) {
      logger.w('打印机不可用，跳过打印重试任务');
      return;
    }

    // 重试失败的打印任务
    await printService.retryFailedPrintOrders();
    logger.i('后台打印重试任务完成');

  } catch (e) {
    logger.e('后台打印重试任务失败: $e');
    rethrow;
  }
}

/// 执行维护任务
Future<void> _executeMaintenanceTask() async {
  final Logger logger = Logger();

  try {
    final orderService = OrderService();

    // 执行订单维护
    await orderService.performMaintenance();
    logger.i('后台维护任务完成');

  } catch (e) {
    logger.e('后台维护任务失败: $e');
    rethrow;
  }
}

/// 网络状态监听器
class NetworkStatusListener {
  static final Logger _logger = Logger();
  static StreamSubscription? _subscription;

  /// 开始监听网络状态
  static void startListening() {
    // 这里应该使用connectivity_plus包来监听网络状态
    // 暂时使用定时器模拟
    Timer.periodic(Duration(seconds: 30), (timer) async {
      try {
        final syncService = SyncService();
        final isConnected = await syncService.checkNetworkConnectivity();

        if (isConnected) {
          // 网络可用时触发同步
          final taskManager = BackgroundTaskManager();
          await taskManager.onNetworkRestored();
        }
      } catch (e) {
        _logger.e('网络状态检查失败: $e');
      }
    });
  }

  /// 停止监听网络状态
  static void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }
}
