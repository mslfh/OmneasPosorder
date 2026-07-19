import 'dart:convert';
import 'package:logger/logger.dart';
import '../models/order_model.dart';
import '../models/server_order_model.dart';
import 'database_service.dart';
import 'sync_service.dart';
import 'print_service.dart';
import 'settings_service.dart';
import 'api_service.dart';

class OrderService {
  static final Logger _logger = Logger();
  final DatabaseService _databaseService = DatabaseService();
  final SyncService _syncService = SyncService();
  final PrintService _printService = PrintService();
  final ApiService _apiService = ApiService();

  // 单例模式
  static OrderService? _instance;
  OrderService._internal();

  factory OrderService() {
    _instance ??= OrderService._internal();
    return _instance!;
  }

  // 生成当天的订单编号（仅计算本地生成的订单）
  Future<String> _generateOrderNo() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 获取今天的所有订单
    final todayOrders = await _databaseService.getOrdersByDate(today);

    // 计算今天的本地订单数量 + 1
    final orderCount = todayOrders.length + 1;

    // 格式化订单编号：B + 3位序号，例如：B001
    return 'B${orderCount.toString().padLeft(3, '0')}';
  }

  /// 下单核心流程：本地事务思维
  /// 1. 先本地落单（pending状态）
  /// 2. 异步打印（先打印小票）
  /// 3. 异步同步到后端
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
    final DateTime orderTime = DateTime.now();
    final String orderNo = await _generateOrderNo();
    final String orderId =
        '$orderNo-${(orderTime.month).toString().padLeft(2, '0')}${orderTime.day.toString()}${orderTime.hour.toString()}${orderTime.minute.toString()}${orderTime.second.toString()}';

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
        orderStatus: OrderStatus.completed,
        syncStatus: SyncStatus.pending,
        printStatus: PrintStatus.pending,
        note: note,
        type: type,
        cashChange: cashChange, // 传递找零
        voucherAmount: voucherAmount, // 传递券金额
      );

      // 保存到本地数据库（关键：先落单）
      await _databaseService.insertOrder(order);
      _logger.i('订单本地落单成功: $orderId, 订单编号: $orderNo');

      // 第二步：根据设置决定是否打印
      final settingsService = SettingsService();
      await settingsService.initialize();
      final settings = settingsService.getSettings();

      // 自动打印是否开启由打印流程内部统一判断，避免遗漏分支
      await _addToPrintQueue(order);

      // 获取最新的订单（含最新printStatus）
      final printedOrder = await _databaseService.getOrder(orderId);

      // 第三步：根据设置决定是否同步到后端（同步时传递print_status）
      if (printedOrder != null) {
        if (settings.enableAutoSync) {
          _syncToBackendWithPrintStatus(printedOrder);
        } else {
          // 自动同步关闭：标记为已跳过同步
          await _databaseService.updateOrder(
            printedOrder.copyWith(syncStatus: SyncStatus.skipped),
          );
          await _databaseService.insertLog(LogModel(
            orderId: orderId,
            action: 'sync',
            status: 'skipped',
            message: 'Auto sync disabled, marked as skipped',
            timestamp: DateTime.now(),
          ));
        }
      } else {
        _logger.w('无法找到打印后的订单进行同步: $orderId');
      }
      // 返回订单编号
      return orderNo;
    }
    catch (e) {
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

  /// 异步推送同步到后端
  Future<void> _syncToBackendWithPrintStatus(OrderModel order) async {
    try {
      // 调用同步服务，传递printStatus
      await _syncService.syncOrder(order.id, printStatus: order.printStatus);
    } catch (e) {
      _logger.e('同步到后端失败: ${order.id}, 错误: $e');

      // 更新错误信息和重试计数
      final latestOrder = await _databaseService.getOrder(order.id);
      if (latestOrder != null) {
        await _databaseService.updateOrder(latestOrder.copyWith(
          errorMessage: '同步失败: $e',
          syncStatus: SyncStatus.syncFailed,
          retryCount: latestOrder.retryCount + 1,
          lastRetryTime: DateTime.now(),
        ));
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

  /// 添加到打印队列
  Future<void> _addToPrintQueue(OrderModel order) async {
    try {
      final settingsService = SettingsService();
      await settingsService.initialize();
      final settings = settingsService.getSettings();

      if (!settings.enableAutoPrint) {
        if (order.printStatus != PrintStatus.skipped) {
          await _databaseService.updateOrder(
            order.copyWith(
              printStatus: PrintStatus.skipped,
              printedTime: DateTime.now(),
              orderStatus: order.isOnlineOrder
                  ? OrderStatus.confirmed
                  : order.orderStatus,
              errorMessage: null,
            ),
          );

          await _databaseService.insertLog(LogModel(
            orderId: order.id,
            action: 'print',
            status: 'skipped',
            message: 'Auto print disabled, skipped printing',
            timestamp: DateTime.now(),
          ));
        }
        return;
      }

      // 调用打印服务
      await _printService.printOrderWithTemplates(order);
    } catch (e) {
      _logger.e('添加到打印队列失败: ${order.id}, 错误: $e');

      // 更新打印状态为失败
      final dbOrder = await _databaseService.getOrder(order.id);
      if (dbOrder != null) {
        await _databaseService.updateOrder(dbOrder.copyWith(
          printStatus: PrintStatus.printFailed,
          errorMessage: '打印失败: $e',
          retryCount: dbOrder.retryCount + 1,
          lastRetryTime: DateTime.now(),
        ));
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
      final order = await _databaseService.getOrder(orderId);
      if (order == null) {
        throw Exception('订单不存在: $orderId');
      }
      _logger.i('手动重试同步订单: $orderId');
      await _syncToBackendWithPrintStatus(order);
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

        await _syncToBackendWithPrintStatus(order);

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

  /// 获取待同步订单
  Future<List<OrderModel>> getPendingSyncOrders() async {
    return await _databaseService.getPendingSyncOrders();
  }

  /// 获取待打印订单
  Future<List<OrderModel>> getPendingPrintOrders() async {
    return await _databaseService.getPendingPrintOrders();
  }

  /// 获取待完成的在线订单（已拉取、已打印、待结账）
  Future<List<OrderModel>> getPendingOnlineOrders({DateTime? date}) async {
    return await _databaseService.getPendingOnlineOrders(date: date);
  }

  /// 获取订单列表，支持按日期过滤（如果传入 date 则返回该日期的所有订单）
  Future<List<OrderModel>> getOrders(
      {int limit = 50, int offset = 0, DateTime? date}) async {
    if (date != null) {
      return await _databaseService.getOrdersByDate(date);
    }
    return await _databaseService.getAllOrders(limit: limit, offset: offset);
  }

  /// 获取订单详情
  Future<OrderModel?> getOrderById(String orderId) async {
    return await _databaseService.getOrder(orderId);
  }

  /// 获取订单统计，支持按日期统计（如果传入 date，则 todayCount 基于该日期）
  Future<Map<String, int>> getOrderStats({DateTime? date}) async {
    // call via dynamic to avoid potential static analysis mismatch in some toolchains
    return await (_databaseService as dynamic).getOrderStats(date: date);
  }

  /// 清空指定日期的订单（测试用）
  Future<void> clearOrdersByDate(DateTime date) async {
    final orders = await _databaseService.getOrdersByDate(date);
    for (final order in orders) {
      await _databaseService.deleteOrder(order.id);
    }
  }

  /// 清空所有订单（测试用）
  Future<void> clearAllOrders() async {
    await _databaseService.deleteAllOrders();
  }

  /// 获取订单日志
  Future<List<LogModel>> getOrderLogs(String orderId) async {
    return await _databaseService.getOrderLogs(orderId);
  }

  /// 标记订单同步成功
  Future<void> markOrderSynced(String orderId) async {
    final order = await _databaseService.getOrder(orderId);
    if (order != null) {
      await _databaseService.updateOrder(order.copyWith(
        syncStatus: SyncStatus.synced,
        syncedTime: DateTime.now(),
        errorMessage: null, // 清除错误信息
      ));

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

  Future<void> _updateOrderByTerminal(
    OrderModel order,
    List<Map<String, dynamic>> items,
  ) async {
    if (order.remoteOrderId == null &&
        (order.remoteOrderNumber?.isEmpty ?? true)) {
      throw Exception('在线订单缺少远程标识，无法更新服务器订单');
    }

    final payload = {
      'remote_order_id': order.remoteOrderId,
      'remote_order_number': order.remoteOrderNumber,
      'order_time': order.orderTime.toIso8601String(),
      'items': items,
      'total_amount': order.totalAmount,
      'note': order.note,
      'type': order.type,
      'status': order.orderStatus.name,
      'sync_status': order.syncStatus.name,
      'print_status': order.printStatus.name,
    };
    print(payload);

    await _apiService.put(
      '/orders/update-order-by-terminal',
      data: payload,
    );
  }

  Future<void> _completeOrderByTerminal(OrderModel order) async {
    if (order.remoteOrderId == null &&
        (order.remoteOrderNumber?.isEmpty ?? true)) {
      throw Exception('在线订单缺少远程标识，无法完成服务器订单');
    }
    final payload = {
      'remote_order_id': order.remoteOrderId,
      'remote_order_number': order.remoteOrderNumber,
      'order_no': order.orderNo,
      'order_time': order.orderTime.toIso8601String(),
      'total_amount': order.totalAmount,
      'cash_amount': order.cashAmount,
      'pos_amount': order.posAmount,
      'cash_change': order.cashChange,
      'voucher_amount': order.voucherAmount,
      'note': order.note,
      'type': order.type,
      'status': OrderStatus.completed.name,
      'sync_status': SyncStatus.synced.name,
      'print_status': order.printStatus.name,
    };

    print(payload);
    await _apiService.post(
      '/orders/complete-order-by-terminal',
      data: payload,
    );
  }

  /// 完成在线订单结账
  Future<void> completeOnlineOrderCheckout({
    required OrderModel order,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required double discountAmount,
    required double taxRate,
    required double serviceFee,
    required double cashAmount,
    required double posAmount,
    required String? note,
    required String type,
    required double cashChange,
    required double voucherAmount,
    required bool itemsChanged,
  }) async {
    final updatedOrder = order.copyWith(
      items: jsonEncode(items),
      totalAmount: totalAmount,
      discountAmount: discountAmount,
      taxRate: taxRate,
      serviceFee: serviceFee,
      cashAmount: cashAmount,
      posAmount: posAmount,
      cashChange: cashChange,
      voucherAmount: voucherAmount,
      note: note,
      type: type,
      orderStatus: OrderStatus.completed,
      syncedTime: itemsChanged ? DateTime.now() : order.syncedTime,
      errorMessage: null,
    );

    if (itemsChanged) {
      await _updateOrderByTerminal(updatedOrder, items);
    }

    await _completeOrderByTerminal(updatedOrder);

    await _databaseService.updateOrder(updatedOrder);

    await _databaseService.insertLog(LogModel(
      orderId: order.id,
      action: 'checkout',
      status: 'success',
      message: itemsChanged ? '在线订单已完成并同步更新到服务器' : '在线订单已完成',
      timestamp: DateTime.now(),
    ));
  }

  /// 标记订单打印成功
  Future<void> markOrderPrinted(String orderId) async {
    final order = await _databaseService.getOrder(orderId);
    if (order != null) {
      await _databaseService.updateOrder(order.copyWith(
        printStatus: PrintStatus.printed,
        printedTime: DateTime.now(),
      ));

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

  /// 更新订单状态
  Future<void> updateStatus(String orderId,
      {OrderStatus? orderStatus, PrintStatus? printStatus}) async {
    final order = await _databaseService.getOrder(orderId);
    if (order != null) {
      final updatedOrder = order.copyWith(
        orderStatus: orderStatus ?? order.orderStatus,
        printStatus: printStatus ?? order.printStatus,
      );
      await _databaseService.updateOrder(updatedOrder);

      // 记录日志
      if (orderStatus != null) {
        await _databaseService.insertLog(LogModel(
          orderId: orderId,
          action: 'update_status',
          status: 'success',
          message: '订单状态修改为: ${orderStatus.name}',
          timestamp: DateTime.now(),
        ));
      }
      if (printStatus != null) {
        await _databaseService.insertLog(LogModel(
          orderId: orderId,
          action: 'update_print_status',
          status: 'success',
          message: '打印状态修改为: ${printStatus.name}',
          timestamp: DateTime.now(),
        ));
      }

      _logger.i('订单状态更新完成: $orderId');
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

  /// 从服务器获取订单
  Future<List<ServerOrderModel>> getServerOrders({DateTime? date}) async {
    try {
      final params = <String, dynamic>{};
      if (date != null) {
        params['date'] =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      }

      final response =
          await _apiService.get('orders/fetch-for-terminal', params: params);

      if (response.statusCode == 200) {
        final payload = response.data;
        dynamic ordersSource;

        if (payload is Map<String, dynamic>) {
          if (payload['success'] == false) {
            throw Exception(payload['message'] ?? 'Failed to fetch orders');
          }
          ordersSource = payload['data'];
        } else {
          ordersSource = payload;
        }

        if (ordersSource == null) {
          return [];
        }

        final List<dynamic> ordersData;
        if (ordersSource is List) {
          ordersData = ordersSource;
        } else if (ordersSource is Map<String, dynamic>) {
          // 兼容接口返回单个订单对象，而不是数组的情况
          ordersData = [ordersSource];
        } else {
          throw Exception(
              'Unexpected server order payload: ${ordersSource.runtimeType}');
        }

        return ordersData
            .whereType<Map<String, dynamic>>()
            .map((order) => ServerOrderModel.fromMap(order))
            .toList();
      } else {
        throw Exception('Failed to fetch orders: ${response.statusCode}');
      }
    } catch (e) {
      _logger.e('获取服务器订单失败: $e');
      rethrow;
    }
  }

  /// 拉取服务器订单到本地数据库
  Future<String> pullServerOrderToLocal(ServerOrderModel serverOrder) async {
    try {
      final alreadyExistsById =
          await _databaseService.existsOrderByRemoteId(serverOrder.id);
      final alreadyExistsByNumber = serverOrder.orderNumber.isNotEmpty
          ? await _databaseService
              .existsOrderByRemoteNumber(serverOrder.orderNumber)
          : false;

      if (alreadyExistsById || alreadyExistsByNumber) {
        throw Exception('该服务器订单已在本地落单，无需重复拉取');
      }

      final DateTime orderTime = serverOrder.orderTime ?? DateTime.now();
      final String orderId =
          '${serverOrder.orderNo}-${(orderTime.month).toString().padLeft(2, '0')}${orderTime.day.toString()}${orderTime.hour.toString()}${orderTime.minute.toString()}${orderTime.second.toString()}';

      // 创建本地订单
      final order = OrderModel(
        id: orderId,
        orderNo: serverOrder.orderNo,
        orderTime: orderTime,
        items: jsonEncode(serverOrder.items),
        totalAmount: double.tryParse(serverOrder.finalAmount) ?? 0.0,
        discountAmount: double.tryParse(serverOrder.discountAmount) ?? 0.0,
        taxRate: double.tryParse(serverOrder.taxRate) ?? 10.0,
        serviceFee: 0.0,
        cashAmount: 0.0,
        posAmount: 0.0,
        orderStatus: OrderStatus.pending,
        syncStatus: SyncStatus.synced,
        printStatus: PrintStatus.pending,
        note: serverOrder.note,
        type: serverOrder.type,
        remoteOrderId: serverOrder.id,
        remoteOrderNumber: serverOrder.orderNumber,
      );

      // 保存到本地数据库
      await _databaseService.insertOrder(order);
      _logger.i('服务器订单拉取成功: ${serverOrder.orderNumber} -> $orderId');

      // 添加到打印队列
      await _addToPrintQueue(order);

      // 获取最新的订单
      final printedOrder = await _databaseService.getOrder(orderId);
      if (printedOrder != null) {
        // 异步同步到后端
        final settingsService = SettingsService();
        await settingsService.initialize();
        final settings = settingsService.getSettings();
        if (settings.enableAutoSync) {
          _syncToBackendWithPrintStatus(printedOrder);
        } else {
          _logger.i('在线订单已落地并完成打印，跳过额外同步');
        }
      }

      return orderId;
    } catch (e) {
      _logger.e('拉取服务器订单失败: $e');
      rethrow;
    }
  }

  /// 重新打印服务器订单（不能跳过）
  Future<void> reprintServerOrder(ServerOrderModel serverOrder) async {
    try {
      _logger.i('重新打印服务器订单: ${serverOrder.orderNumber}');

      final DateTime orderTime = serverOrder.orderTime ?? DateTime.now();

      // 创建临时订单对象用于打印
      final tempOrder = OrderModel(
        id: serverOrder.id.toString(),
        orderNo: serverOrder.orderNo,
        orderTime: orderTime,
        items: jsonEncode(serverOrder.items),
        totalAmount: double.tryParse(serverOrder.finalAmount) ?? 0.0,
        discountAmount: double.tryParse(serverOrder.discountAmount) ?? 0.0,
        taxRate: double.tryParse(serverOrder.taxRate) ?? 10.0,
        note: serverOrder.note,
        type: serverOrder.type,
        remoteOrderId: serverOrder.id,
        remoteOrderNumber: serverOrder.orderNumber,
      );

      // 直接调用打印服务，不允许跳过
      await _printService.printOrderWithTemplates(tempOrder);
      _logger.i('服务器订单打印完成: ${serverOrder.orderNumber}');
    } catch (e) {
      _logger.e('打印服务器订单失败: $e');
      rethrow;
    }
  }
}
