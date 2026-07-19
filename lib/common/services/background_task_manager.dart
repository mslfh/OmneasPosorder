import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logger/logger.dart';
import 'order_service.dart';
import 'sync_service.dart';
import 'print_service.dart';
import 'settings_service.dart';

class ServiceStatusResult {
  final bool isPrinterConnected;
  final bool isServerConnected;

  const ServiceStatusResult({
    required this.isPrinterConnected,
    required this.isServerConnected,
  });
}

class BackgroundTaskManager {
  static final Logger _logger = Logger();
  static const String syncTaskName = 'order_sync_task';
  static const String printTaskName = 'print_retry_task';
  static const String maintenanceTaskName = 'maintenance_task';
  static const String fetchRemoteOrdersTaskName = 'fetch_remote_orders_task';
  static const String fetchRemoteOrdersChainTaskName = 'fetch_remote_orders_chain_task';
  static const String orderMatchTaskName = 'order_match_task';
  // 前台服务：保证熄屏/Doze模式下拉取远程订单任务仍能持续触发
  static const int _foregroundServiceId = 4001;
  static const String _foregroundNotificationChannelId = 'fetch_remote_orders_channel';
  static bool _isInitialized = false;

  // 任务执行状态锁，防止并发执行
  static bool _isSyncing = false;
  static bool _isPrinting = false;
  static bool _isMaintaining = false;
  static bool _isFetching = false;
  static bool _isMatching = false;

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
  static Timer? _fetchRemoteOrdersTimer;
  static Timer? _orderMatchTimer;

  /// 检查是否为移动平台
  bool get _isMobilePlatform => Platform.isAndroid || Platform.isIOS;

  /// 初始化后台任务管理器
  Future<void> initialize() async {
    try {
      if (_isInitialized) {
        _logger.i('后台任务管理器已初始化，跳过重复初始化');
        return;
      }

      if (_isMobilePlatform) {
        // 移动平台使用 workmanager 作为兜底（周期最小15分钟，受Doze限制）
        await Workmanager().initialize(
          callbackDispatcher,
          isInDebugMode: false,
        );
        await _registerPeriodicTasks();
        await _scheduleFetchRemoteOrdersChain(forceReplace: true);

        // 前台服务作为主力：不受熄屏/Doze省电限制，保证拉单任务持续触发
        await _startForegroundFetchService();
        _logger.i('移动平台后台任务管理器初始化成功');
      } else {
        // Windows/Web 平台使用定时器
        await _initializeDesktopTasks();
        _logger.i('桌面平台后台任务管理器初始化成功');
      }

      _isInitialized = true;

    } catch (e) {
      _logger.e('后台任务管理器初始化失败: $e');
    }
  }

  /// 按最新设置刷新后台任务
  Future<void> refreshScheduledTasks() async {
    try {
      if (!_isInitialized) {
        await initialize();
        return;
      }

      if (_isMobilePlatform) {
        await Workmanager().cancelAll();
        await _registerPeriodicTasks();
        await _scheduleFetchRemoteOrdersChain(forceReplace: true);
        await _startForegroundFetchService();
        _logger.i('移动平台后台任务已根据最新设置刷新');
      } else {
        await _cancelDesktopTimers();
        await _initializeDesktopTasks();
        _logger.i('桌面平台后台任务已根据最新设置刷新');
      }
    } catch (e) {
      _logger.e('刷新后台任务失败: $e');
    }
  }

  /// 初始化桌面平台任务
  Future<void> _initializeDesktopTasks() async {
    // 从settings获取间隔配置
    final settingsService = SettingsService();
    await settingsService.initialize();
    final settings = settingsService.getSettings();

    /* 暂时移除独立的同步和打印重试任务，由维护任务统一处理
    // 同步任务 - 使用配置的间隔
    _syncTimer = Timer.periodic(Duration(minutes: settings.syncTaskIntervalMinutes), (timer) async {
      try {
        await _executeSyncTask();
      } catch (e) {
        _logger.e('桌面平台同步任务失败: $e');
      }
    });
    */

    // 拉取服务器新订单任务 - 使用配置的间隔
    _fetchRemoteOrdersTimer = Timer.periodic(Duration(seconds: settings.fetchRemoteOrdersIntervalSeconds), (timer) async {
      try {
        await _executeFetchRemoteOrdersTask();
      } catch (e) {
        _logger.e('拉取服务器新订单任务失败: $e');
      }
    });

    /* 暂时移除独立的同步和打印重试任务，由维护任务统一处理
    // 打印重试任务 - 使用配置的间隔
    _printTimer = Timer.periodic(Duration(minutes: settings.printRetryTaskIntervalMinutes), (timer) async {
      try {
        await _executePrintRetryTask();
      } catch (e) {
        _logger.e('桌面平台打印重试任务失败: $e');
      }
    });
    */

    // 维护任务 - 每小时执行一次
    _maintenanceTimer = Timer.periodic(Duration(hours: 1), (timer) async {
      try {
        await _executeMaintenanceTask();
      } catch (e) {
        _logger.e('桌面平台维护任务失败: $e');
      }
    });

    // 订单对账任务 - 使用配置的间隔
    _orderMatchTimer = Timer.periodic(Duration(minutes: settings.orderMatchCheckIntervalMinutes), (timer) async {
      try {
        await _executeOrderMatchTask();
      } catch (e) {
        _logger.e('桌面平台订单对账任务失败: $e');
      }
    });

    _logger.i('桌面平台定期任务已启动');
  }

  /// 检查打印机和服务器连接状态
  Future<ServiceStatusResult> checkServiceStatus() async {
    try {
      final settingsService = SettingsService();
      await settingsService.initialize();
      final settings = settingsService.getSettings();

      final syncService = SyncService();
      final printService = PrintService();

      syncService.configureBaseUrl(settings.apiServerUrl);
      printService.configurePrinter(
        printerIP: settings.printerAddress,
        printerPort: settings.printerPort,
      );

      final results = await Future.wait<bool>([
        printService.checkPrinterStatus(),
        syncService.checkNetworkConnectivity(),
      ]);

      return ServiceStatusResult(
        isPrinterConnected: results[0],
        isServerConnected: results[1],
      );
    } catch (e) {
      _logger.e('检查打印机和服务器状态失败: $e');
      return const ServiceStatusResult(
        isPrinterConnected: false,
        isServerConnected: false,
      );
    }
  }

  /// 取消桌面平台定时器
  Future<void> _cancelDesktopTimers() async {
    _syncTimer?.cancel();
    _printTimer?.cancel();
    _maintenanceTimer?.cancel();
    _fetchRemoteOrdersTimer?.cancel();
    _orderMatchTimer?.cancel();
    _syncTimer = null;
    _printTimer = null;
    _maintenanceTimer = null;
    _fetchRemoteOrdersTimer = null;
    _orderMatchTimer = null;
  }

  /// 注册定期任务
  Future<void> _registerPeriodicTasks() async {
    try {
      // 从settings获取间隔配置
      final settingsService = SettingsService();
      await settingsService.initialize();
      final settings = settingsService.getSettings();

      /* 暂时移除独立的同步和打印重试任务，由维护任务统一处理
      // 同步任务 - 使用配置的间隔
      await Workmanager().registerPeriodicTask(
        syncTaskName,
        syncTaskName,
        frequency: Duration(minutes: settings.syncTaskIntervalMinutes),
        constraints: Constraints(
          networkType: NetworkType.connected, // 需要网络连接
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );

      // 打印重试任务 - 使用配置的间隔
      await Workmanager().registerPeriodicTask(
        printTaskName,
        printTaskName,
        frequency: Duration(minutes: settings.printRetryTaskIntervalMinutes),
        constraints: Constraints(
          networkType: NetworkType.not_required, // 打印不需要网络
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );
      */

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

      // 拉取服务器新订单任务 - 使用配置的间隔
      // 注意：Workmanager 在 Android 上的最小周期为 15 分钟
      final fetchInterval = settings.fetchRemoteOrdersIntervalSeconds > 900 
          ? Duration(seconds: settings.fetchRemoteOrdersIntervalSeconds)
          : Duration(minutes: 15);

      await Workmanager().registerPeriodicTask(
        fetchRemoteOrdersTaskName,
        fetchRemoteOrdersTaskName,
        frequency: fetchInterval,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );

      // 订单对账任务
      await Workmanager().registerPeriodicTask(
        orderMatchTaskName,
        orderMatchTaskName,
        frequency: Duration(minutes: settings.orderMatchCheckIntervalMinutes > 15 
            ? settings.orderMatchCheckIntervalMinutes 
            : 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );

      _logger.i('定期任务注册成功');

    } catch (e) {
      _logger.e('定期任务注册失败: $e');
    }
  }

  /// 在移动端维持一个单次任务链，提升熄屏/休眠期间拉单任务的触发机会
  Future<void> _scheduleFetchRemoteOrdersChain({bool forceReplace = false}) async {
    if (!_isMobilePlatform) return;

    try {
      final settingsService = SettingsService();
      await settingsService.initialize();
      final settings = settingsService.getSettings();

      final intervalSeconds = settings.fetchRemoteOrdersIntervalSeconds > 0
          ? settings.fetchRemoteOrdersIntervalSeconds
          : 60;

      await Workmanager().registerOneOffTask(
        fetchRemoteOrdersChainTaskName,
        fetchRemoteOrdersTaskName,
        initialDelay: Duration(seconds: intervalSeconds),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        existingWorkPolicy:
            forceReplace ? ExistingWorkPolicy.replace : ExistingWorkPolicy.keep,
      );
    } catch (e) {
      _logger.e('调度拉单链式任务失败: $e');
    }
  }

  /// 申请前台服务所需的通知/电池优化豁免权限（尽力而为，不阻塞流程）
  Future<void> _requestForegroundServicePermissions() async {
    try {
      final notificationPermission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notificationPermission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      if (Platform.isAndroid) {
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
      }
    } catch (e) {
      _logger.e('申请前台服务权限失败: $e');
    }
  }

  /// 启动（或按最新间隔重启）前台拉单服务，确保熄屏时也能持续拉取远程订单
  Future<void> _startForegroundFetchService() async {
    if (!_isMobilePlatform) return;

    try {
      await _requestForegroundServicePermissions();

      final settingsService = SettingsService();
      await settingsService.initialize();
      final settings = settingsService.getSettings();
      final intervalSeconds = settings.fetchRemoteOrdersIntervalSeconds > 0
          ? settings.fetchRemoteOrdersIntervalSeconds
          : 5;

      final taskOptions = ForegroundTaskOptions(
        eventAction:
            ForegroundTaskEventAction.repeat(intervalSeconds * 1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      );

      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          foregroundTaskOptions: taskOptions,
          notificationTitle: '远程订单拉取服务运行中',
          notificationText: '每 $intervalSeconds 秒拉取一次远程订单',
        );
      } else {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: _foregroundNotificationChannelId,
            channelName: '远程订单拉取服务',
            channelDescription: '保持后台运行以持续拉取远程订单，即使设备熄屏也不中断',
            onlyAlertOnce: true,
          ),
          iosNotificationOptions: const IOSNotificationOptions(
            showNotification: false,
            playSound: false,
          ),
          foregroundTaskOptions: taskOptions,
        );

        await FlutterForegroundTask.startService(
          serviceId: _foregroundServiceId,
          notificationTitle: '远程订单拉取服务运行中',
          notificationText: '每 $intervalSeconds 秒拉取一次远程订单',
          callback: startFetchRemoteOrdersForegroundTask,
        );
      }

      _logger.i('前台拉单服务已启动/更新，间隔 $intervalSeconds 秒');
    } catch (e) {
      _logger.e('启动前台拉单服务失败: $e');
    }
  }

  /// 停止前台拉单服务
  Future<void> _stopForegroundFetchService() async {
    if (!_isMobilePlatform) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      _logger.e('停止前台拉单服务失败: $e');
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
        await Workmanager().cancelByUniqueName(fetchRemoteOrdersChainTaskName);
        await _stopForegroundFetchService();
        _logger.i('所有后台任务已取消（移动平台）');
      } else {
        // Windows 平台取消定时器
        await _cancelDesktopTimers();
        _logger.i('所有后台任务已取消（桌面平台）');
      }
      _isInitialized = false;
    } catch (e) {
      _logger.e('取消后台任务失败: $e');
    }
  }

  /// 取消特定任务
  Future<void> cancelTask(String taskName) async {
    try {
      if (_isMobilePlatform) {
        await Workmanager().cancelByUniqueName(taskName);
        if (taskName == fetchRemoteOrdersTaskName) {
          await Workmanager().cancelByUniqueName(fetchRemoteOrdersChainTaskName);
          await _stopForegroundFetchService();
        }
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
          case orderMatchTaskName:
            _orderMatchTimer?.cancel();
            _orderMatchTimer = null;
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
      await _ensureBackgroundHiveInitialized();
      await _configureServicesFromSettings();
      logger.i('执行后台任务: $task');

      switch (task) {
        /* 暂时移除独立的同步和打印重试任务
        case BackgroundTaskManager.syncTaskName:
          await _executeSyncTask();
          break;

        case BackgroundTaskManager.printTaskName:
          await _executePrintRetryTask();
          break;
        */

        case BackgroundTaskManager.maintenanceTaskName:
          await _executeMaintenanceTask();
          break;

        case BackgroundTaskManager.fetchRemoteOrdersTaskName:
          await _executeFetchRemoteOrdersTask();
          await _scheduleNextFetchRemoteOrdersChainTask();
          break;

        case BackgroundTaskManager.orderMatchTaskName:
          await _executeOrderMatchTask();
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

/// 前台服务专用任务回调，在独立的后台隔离区(isolate)中运行，
/// 不受Doze/App Standby省电策略限制，保证熄屏时也能持续拉单。
@pragma('vm:entry-point')
void startFetchRemoteOrdersForegroundTask() {
  FlutterForegroundTask.setTaskHandler(_FetchRemoteOrdersTaskHandler());
}

class _FetchRemoteOrdersTaskHandler extends TaskHandler {
  final Logger _logger = Logger();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      await _ensureBackgroundHiveInitialized();
      await _configureServicesFromSettings();
      _logger.i('前台拉单服务已启动 (starter: ${starter.name})');
      // 启动时立即执行一次，避免等待首个周期
      await _executeFetchRemoteOrdersTask();
    } catch (e) {
      _logger.e('前台拉单服务启动失败: $e');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _executeFetchRemoteOrdersTask();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _logger.i('前台拉单服务已停止');
  }

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}

Future<void> _scheduleNextFetchRemoteOrdersChainTask() async {
  if (!(Platform.isAndroid || Platform.isIOS)) return;

  final logger = Logger();
  try {
    final settingsService = SettingsService();
    await settingsService.initialize();
    final settings = settingsService.getSettings();

    final intervalSeconds = settings.fetchRemoteOrdersIntervalSeconds > 0
        ? settings.fetchRemoteOrdersIntervalSeconds
        : 60;

    await Workmanager().registerOneOffTask(
      BackgroundTaskManager.fetchRemoteOrdersChainTaskName,
      BackgroundTaskManager.fetchRemoteOrdersTaskName,
      initialDelay: Duration(seconds: intervalSeconds),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  } catch (e) {
    logger.e('续期拉单链式任务失败: $e');
  }
}

/// 执行同步任务
Future<void> _executeSyncTask() async {
  if (BackgroundTaskManager._isSyncing) return;
  BackgroundTaskManager._isSyncing = true;
  
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
  } catch (e) {
    logger.e('后台同步任务失败: $e');
  } finally {
    BackgroundTaskManager._isSyncing = false;
  }
}

/// 执行打印重试任务
Future<void> _executePrintRetryTask() async {
  if (BackgroundTaskManager._isPrinting) return;
  BackgroundTaskManager._isPrinting = true;

  final Logger logger = Logger();

  try {
    final printService = PrintService();
    // 先处理自动打印开关
    final autoPrintEnabled = await printService.isAutoPrintEnabled();
    if (!autoPrintEnabled) {
      await printService.retryFailedPrintOrders();
      return;
    }
    // 检查打印机状态
    final isReady = await printService.checkPrinterStatus();
    if (!isReady) {
      logger.w('打印机不可用，跳过打印重试任务');
      return;
    }
    // 重试失败的打印任务
    await printService.retryFailedPrintOrders();
  } catch (e) {
    logger.e('后台打印重试任务失败: $e');
  } finally {
    BackgroundTaskManager._isPrinting = false;
  }
}

/// 执行维护任务
Future<void> _executeMaintenanceTask() async {
  if (BackgroundTaskManager._isMaintaining) return;
  BackgroundTaskManager._isMaintaining = true;

  final Logger logger = Logger();

  try {
    final orderService = OrderService();
    // 执行订单维护
    await orderService.performMaintenance();
    logger.i('后台维护任务完成');
  } catch (e) {
    logger.e('后台维护任务失败: $e');
  } finally {
    BackgroundTaskManager._isMaintaining = false;
  }
}

/// 执行远程订单拉取任务
Future<void> _executeFetchRemoteOrdersTask() async {
  if (BackgroundTaskManager._isFetching) return;
  BackgroundTaskManager._isFetching = true;

  final Logger logger = Logger();
  try {
    final syncService = SyncService();
    await syncService.fetchAndSyncRemoteOrders();
  } catch (e) {
    logger.e('拉取服务器新订单任务失败: $e');
  } finally {
    BackgroundTaskManager._isFetching = false;
  }
}

/// 执行订单对账任务
Future<void> _executeOrderMatchTask() async {
  if (BackgroundTaskManager._isMatching) return;
  BackgroundTaskManager._isMatching = true;

  final Logger logger = Logger();
  try {
    final syncService = SyncService();
    // 对账前先尝试同步待处理订单
    await syncService.syncPendingOrders();
    
    // 执行对账逻辑
    // final matchService = OrderMatchService();
    // await matchService.verifyOrdersMatch();
    // logger.i('后台对账任务完成');
  } catch (e) {
    logger.e('后台对账任务失败: $e');
  } finally {
    BackgroundTaskManager._isMatching = false;
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

bool _isBackgroundHiveInitialized = false;

Future<void> _ensureBackgroundHiveInitialized() async {
  if (_isBackgroundHiveInitialized) return;

  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  _isBackgroundHiveInitialized = true;
}

Future<void> _configureServicesFromSettings() async {
  final settingsService = SettingsService();
  await settingsService.initialize();
  final settings = settingsService.getSettings();

  SyncService().configureBaseUrl(settings.apiServerUrl);
  PrintService().configurePrinter(
    printerIP: settings.printerAddress,
    printerPort: settings.printerPort,
  );
}

