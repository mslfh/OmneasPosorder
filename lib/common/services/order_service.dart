import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';
import '../models/order_model.dart';
import 'database_service.dart';
import 'sync_service.dart';
import 'print_service.dart';

class OrderService {
  static final Logger _logger = Logger();
  static final Uuid _uuid = Uuid();

  final DatabaseService _databaseService = DatabaseService();
  final SyncService _syncService = SyncService();
  final PrintService _printService = PrintService();

  // 单例模式
  static OrderService? _instance;
  OrderService._internal();

  factory OrderService() {
    _instance ??= OrderService._internal();
    return _instance!;
  }

  // 生成当天的订单编号
  Future<String> _generateOrderNo() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 获取今天的所有订单
    final todayOrders = await _databaseService.getOrdersByDate(today);

    // 计算今天的订单数量 + 1
    final orderCount = todayOrders.length + 1;

    // 格式化订单编号：B + 3位序号，例如：B001
    return 'B${orderCount.toString().padLeft(3, '0')}';
  }

  /// 下单核心流程：本地事务思维
  /// 1. 先本地落单（pending状态）
  /// 2. 异步打印（先打印小票）
  /// 3. 异步同步到后端（同步时传递print_status）
  Future<String> placeOrder({
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    double discountAmount = 0.0,
    double taxRate = 10.0,
    double serviceFee = 0.0,
    double cashAmount = 0.0,
    double posAmount = 0.0,
    String? note,
    String? type,
    double cashChange = 0.0, // 新增找零参数
    double voucherAmount = 0.0, // 新增券金额参数
  }) async {
    final String orderId = _uuid.v4();
    final DateTime orderTime = DateTime.now();
    final String orderNo = await _generateOrderNo();

    try {
      // 直接使用传入的 items，不再覆盖 extra_price 字段
      final List<Map<String, dynamic>> updatedItems = items;

      // 第一步：本地落单
      final order = OrderModel(
        id: orderId,
        orderNo: orderNo,
        orderTime: orderTime,
        items: jsonEncode(updatedItems),
        totalAmount: totalAmount,
        discountAmount: discountAmount,
        taxRate: taxRate,
        serviceFee: serviceFee,
        cashAmount: cashAmount,
        posAmount: posAmount,
        orderStatus: OrderStatus.pending,
        printStatus: PrintStatus.pending,
        note: note,
        type: type,
        cashChange: cashChange, // 传递找零
        voucherAmount: voucherAmount, // 传递券金额
      );

      // 保存到本地数据库（关键：先落单）
      await _databaseService.insertOrder(order);
      _logger.i('订单本地落单成功: $orderId, 订单编号: $orderNo');

      // 第二步：异步打印（先打印小票）
      await _addToPrintQueue(order);

      // 获取最新的订单（含最新printStatus）
      final printedOrder = await _databaseService.getOrder(orderId);

      // 第三步：异步同步到后端（同步时传递print_status）
      if (printedOrder != null) {
        _syncToBackendWithPrintStatus(printedOrder);
      } else {
        // fallback: 兼容老逻辑
        _syncToBackend(orderId);
      }

      return orderId;

    } catch (e) {
      _logger.e('下单失败: $orderId, 错误: $e');

      // 记录错误日志
      await _databaseService.insertLog(LogModel(
        orderId: orderId,
        action: 'order',
        status: 'error',
        message: '下单失败: $e',
        timestamp: DateTime.now(),
      ));

      rethrow;
    }
  }

  /// 异步同步到后端（带printStatus）
  Future<void> _syncToBackendWithPrintStatus(OrderModel order) async {
    try {
      // 更新状态为pending_sync
      await _databaseService.updateOrder(
        order.copyWith(orderStatus: OrderStatus.pendingSync)
      );

      // 调用同步服务，传递printStatus
      await _syncService.syncOrder(order.id, printStatus: order.printStatus);

    } catch (e) {
      _logger.e('同步到后端失败: ${order.id}, 错误: $e');

      // 更新错误信息和重试计数
      final latestOrder = await _databaseService.getOrder(order.id);
      if (latestOrder != null) {
        await _databaseService.updateOrder(
          latestOrder.copyWith(
            errorMessage: '同步失败: $e',
            retryCount: latestOrder.retryCount + 1,
            lastRetryTime: DateTime.now(),
          )
        );
      }

      // 记录日志
      await _databaseService.insertLog(LogModel(
        orderId: order.id,
        action: 'sync',
        status: 'error',
        message: '同步失败: $e',
        timestamp: DateTime.now(),
      ));
    }
  }

  /// 异步同步到后端
  Future<void> _syncToBackend(String orderId) async {
    try {
      // 更新状态为pending_sync
      final order = await _databaseService.getOrder(orderId);
      if (order == null) return;

      await _databaseService.updateOrder(
        order.copyWith(orderStatus: OrderStatus.pendingSync)
      );

      // 调用同步服务
      await _syncService.syncOrder(orderId);

    } catch (e) {
      _logger.e('同步到后端失败: $orderId, 错误: $e');

      // 更新错误信息和重试计数
      final order = await _databaseService.getOrder(orderId);
      if (order != null) {
        await _databaseService.updateOrder(
          order.copyWith(
            errorMessage: '同步失败: $e',
            retryCount: order.retryCount + 1,
            lastRetryTime: DateTime.now(),
          )
        );
      }

      // 记录日志
      await _databaseService.insertLog(LogModel(
        orderId: orderId,
        action: 'sync',
        status: 'error',
        message: '同步失败: $e',
        timestamp: DateTime.now(),
      ));
    }
  }

  /// 添加到打印队列
  Future<void> _addToPrintQueue(OrderModel order) async {
    try {
      // 调用打印服务
      await _printService.printOrderWithTemplates(order);

    } catch (e) {
      _logger.e('添加到打印队列失败: , 错误: $e');

      // 更新打印状态为失败
      final dbOrder = await _databaseService.getOrder(order.id);
      if (dbOrder != null) {
        await _databaseService.updateOrder(
          dbOrder.copyWith(
            printStatus: PrintStatus.printFailed,
            errorMessage: '打印失败: $e',
            retryCount: dbOrder.retryCount + 1,
            lastRetryTime: DateTime.now(),
          )
        );
      }

      // 记录日志
      await _databaseService.insertLog(LogModel(
        orderId: order.id,
        action: 'print',
        status: 'error',
        message: '打印失败: $e',
        timestamp: DateTime.now(),
      ));
    }
  }

  /// 手动重新同步订单
  Future<void> retrySyncOrder(String orderId) async {
    try {
      _logger.i('手动重试同步订单: $orderId');
      await _syncToBackend(orderId);
    } catch (e) {
      _logger.e('手动重试同步失败: $orderId, 错误: $e');
      rethrow;
    }
  }

  /// 手动重新打印订单
  Future<void> retryPrintOrder(String orderId) async {
    try {
      final order = await _databaseService.getOrder(orderId);
      _logger.i('手动重试打印订单: $orderId');
      await _addToPrintQueue(order!);
    } catch (e) {
      _logger.e('手动重试打印失败: $orderId, 错误: $e');
      rethrow;
    }
  }

  /// 批量重试待同步订单
  Future<void> retryAllPendingSyncOrders() async {
    try {
      final pendingOrders = await _databaseService.getPendingSyncOrders();
      _logger.i('开始批量重试 ${pendingOrders.length} 个待同步订单');

      for (final order in pendingOrders) {
        // 避免频繁重试，至少间隔5分钟
        if (order.lastRetryTime != null) {
          final timeDiff = DateTime.now().difference(order.lastRetryTime!);
          if (timeDiff.inMinutes < 5) {
            continue;
          }
        }

        // 最大重试次数限制
        if (order.retryCount >= 10) {
          _logger.w('订单重试次数超限，跳过: ${order.id}');
          continue;
        }

        await _syncToBackend(order.id);

        // 避免并发过多，延迟一下
        await Future.delayed(Duration(milliseconds: 500));
      }

      _logger.i('批量重试完成');
    } catch (e) {
      _logger.e('批量重试失败: $e');
    }
  }

  /// 批量重试待打印订单
  Future<void> retryAllPendingPrintOrders() async {
    try {
      final pendingOrders = await _databaseService.getPendingPrintOrders();
      _logger.i('开始批量重试 ${pendingOrders.length} 个待打印订单');

      for (final order in pendingOrders) {
        // 避免频繁重试
        if (order.lastRetryTime != null) {
          final timeDiff = DateTime.now().difference(order.lastRetryTime!);
          if (timeDiff.inMinutes < 2) {
            continue;
          }
        }

        // 最大重试次数限制
        if (order.retryCount >= 5) {
          _logger.w('打印重试次数超限，跳过: ${order.id}');
          continue;
        }

        await _addToPrintQueue(order);

        // 延迟避免打印机压力过大
        await Future.delayed(Duration(seconds: 1));
      }

      _logger.i('批量重试打印完成');
    } catch (e) {
      _logger.e('批量重试打印失败: $e');
    }
  }

  /// 获取订单列表
  Future<List<OrderModel>> getOrders({int limit = 50, int offset = 0}) async {
    return await _databaseService.getAllOrders(limit: limit, offset: offset);
  }

  /// 获取订单详情
  Future<OrderModel?> getOrderById(String orderId) async {
    return await _databaseService.getOrder(orderId);
  }

  /// 获取订单统计
  Future<Map<String, int>> getOrderStats() async {
    return await _databaseService.getOrderStats();
  }

  /// 获取订单日志
  Future<List<LogModel>> getOrderLogs(String orderId) async {
    return await _databaseService.getOrderLogs(orderId);
  }

  /// 标记订单同步成功
  Future<void> markOrderSynced(String orderId) async {
    final order = await _databaseService.getOrder(orderId);
    if (order != null) {
      await _databaseService.updateOrder(
        order.copyWith(
          orderStatus: OrderStatus.synced,
          syncedTime: DateTime.now(),
          errorMessage: null, // 清除错误信息
        )
      );

      // 记录成功日志
      await _databaseService.insertLog(LogModel(
        orderId: orderId,
        action: 'sync',
        status: 'success',
        message: '同步成功',
        timestamp: DateTime.now(),
      ));

      _logger.i('订单标记为已同步: $orderId');
    }
  }

  /// 标记订单打印成功
  Future<void> markOrderPrinted(String orderId) async {
    final order = await _databaseService.getOrder(orderId);
    if (order != null) {
      await _databaseService.updateOrder(
        order.copyWith(
          printStatus: PrintStatus.printed,
          printedTime: DateTime.now(),
        )
      );

      // 记录成功日志
      await _databaseService.insertLog(LogModel(
        orderId: orderId,
        action: 'print',
        status: 'success',
        message: '打印成功',
        timestamp: DateTime.now(),
      ));

      _logger.i('订单标记为已打印: $orderId');
    }
  }

  /// 定期维护任务
  Future<void> performMaintenance() async {
    try {
      _logger.i('开始执行订单维护任务');

      // 清理旧日志
      await _databaseService.cleanOldLogs();

      // 重试失败的订单（限制频率）
      await retryAllPendingSyncOrders();
      await retryAllPendingPrintOrders();

      _logger.i('订单维护任务完成');
    } catch (e) {
      _logger.e('订单维护任务失败: $e');
    }
  }
}
