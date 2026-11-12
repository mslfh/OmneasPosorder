import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../models/order_model.dart';
import '../models/server_order_model.dart';
import '../models/report_models.dart';
import '../utils/order_item_mapper.dart';
import '../utils/type_utils.dart';
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
  Future<String> generateOrderNo() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 获取今天的所有订单
    final todayOrders = await _databaseService.getOrdersByDate(today);

    // 计算今天的本地订单数量 + 1
    final orderCount = todayOrders.length + 1;

    // 格式化订单编号：B + 3位序号，例如：B001
    return 'B${orderCount.toString().padLeft(3, '0')}';
  }

  /// 结账下单
  /// 1. 先本地落单（pending状态）
  /// 2. 异步打印（先打印小票）
  /// 3. 异步推送到后端
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
    DateTime? expectedTime, // 可选的预计时间
  })
  async {
    final DateTime now = DateTime.now();
    final DateTime createdAt = now;
    final DateTime orderTime = expectedTime ?? now;
    final String orderNo = await generateOrderNo();
    final String orderId =
        '$orderNo-${createdAt.month.toString().padLeft(2, '0')}${createdAt.day.toString().padLeft(2, '0')}${createdAt.hour.toString().padLeft(2, '0')}${createdAt.minute.toString().padLeft(2, '0')}${createdAt.second.toString().padLeft(2, '0')}';

    try {

      // 第一步：本地落单
      final order = OrderModel(
        id: orderId,
        orderNo: orderNo,
        orderTime: orderTime,
        createdAt: createdAt,
        items: jsonEncode(items),
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
        cashChange: cashChange,
        voucherAmount: voucherAmount,
      );

      // 保存到本地数据库（关键：先落单）
      await _databaseService.insertOrder(order);
      _logger.i('订单本地落单成功: $orderId, 订单编号: $orderNo');

      // 第二步：根据设置决定是否打印
      // 自动打印是否开启由打印流程内部统一判断，避免遗漏分支
      await _addToPrintQueue(order);

      // 获取最新的订单（含最新printStatus）
      final printedOrder = await _databaseService.getOrder(orderId);

      // 第三步：根据设置决定是否推送到后端
      final settingsService = SettingsService();
      await settingsService.initialize();
      final settings = settingsService.getSettings();

      if (printedOrder != null) {
        if (settings.enableAutoSync) {
          _pushOrderToBackend(printedOrder);
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

  /// 推送订单到后端
  Future<void> _pushOrderToBackend(OrderModel order) async {
    try {
      // 将待推送订单状态更新为 pending
      if (order.syncStatus != SyncStatus.pending) {
        await _databaseService.updateOrder(
          order.copyWith(syncStatus: SyncStatus.pending),
        );
      }
      // 调用同步服务
      await _syncService.pushOrderToRemote(order.id);
    } catch (e) {
      _logger.e('同步到后端失败: ${order.id}, 错误: $e');
    }
  }

  /// 添加到打印队列
  Future<void> _addToPrintQueue(OrderModel order) async {
    try {
      final isAutoPrint = await _printService.isAutoPrintEnabled();

      if (!isAutoPrint) {
        if (order.printStatus != PrintStatus.skipped) {
          await _databaseService.updateOrder(
            order.copyWith(
              printStatus: PrintStatus.skipped,
              printedTime: DateTime.now(),
              orderStatus: order.orderStatus,
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

  /// 手动重新推送订单到云端
  Future<void> retrySyncOrderToRemote(String orderId) async {
    try {
      final order = await _databaseService.getOrder(orderId);
      if (order == null) {
        throw Exception('订单不存在: $orderId');
      }

      _logger.i('手动重试推送订单到云端: $orderId');
      await _pushOrderToBackend(order);
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

        await _pushOrderToBackend(order);

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

  /// 获取待完成的在线订单（已拉取、已打印、待结账）
  Future<List<OrderModel>> getPendingOnlineOrders({DateTime? date}) async {
    return await _databaseService.getPendingOnlineOrders(date: date);
  }

  /// 获取订单列表，支持按单日期/日期范围/全部过滤
  Future<List<OrderModel>> getOrders({
    int limit = 50,
    int offset = 0,
    DateTime? date,
    DateTimeRange? dateRange,
  })
  async {
    if (dateRange != null) {
      return await _databaseService.getOrdersByDateRange(
        dateRange.start,
        dateRange.end,
        limit: limit,
        offset: offset,
      );
    } else if (date != null) {
      return await _databaseService.getOrdersByDate(date);
    }
    return await _databaseService.getAllOrders(limit: limit, offset: offset);
  }

  /// 获取订单详情
  Future<OrderModel?> getOrderById(String orderId) async {
    return await _databaseService.getOrder(orderId);
  }

  /// 获取订单统计，支持按日期/日期范围统计
  Future<Map<String, int>> getOrderStats({
    DateTime? date,
    DateTimeRange? dateRange,
  })
  async {
    // call via dynamic to avoid potential static analysis mismatch in some toolchains
    return await (_databaseService as dynamic).getOrderStats(
      date: date,
      dateRange: dateRange,
    );
  }

  /// 获取订单日志
  Future<List<LogModel>> getOrderLogs(String orderId) async {
    return await _databaseService.getOrderLogs(orderId);
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
  })
  async {
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
      syncStatus: SyncStatus.pending,
      errorMessage: null,
    );

    // 1. 本地落盘更新 (离线优先，避免网络异常导致本地改单丢失)
    await _databaseService.updateOrder(updatedOrder);

    // 2. 菜品发生变更 (itemsChanged == true) 时通过 syncTerminalOrderChanges 覆盖更新菜品明细、总额与结账状态；
    //    菜品未变动时通过 complete-order-by-terminal 结账完成（二选一，避免重复调用导致后端抛 500 冲突）
    try {
      if (itemsChanged) {
        await _syncService.syncTerminalOrderChanges(updatedOrder, overrideItems: items);
      } else {
        await _syncService.completeOrderByTerminal(updatedOrder, overrideItems: items);
      }
    } catch (e) {
      _logger.w('修改订单发包至后端异常 (已落地本地数据库，将等待自动重试): $e');
    }

    await _databaseService.insertLog(LogModel(
      orderId: order.id,
      action: 'checkout',
      status: 'success',
      message: itemsChanged ? '在线订单已完成并同步更新到服务器' : '在线订单已完成',
      timestamp: DateTime.now(),
    ));
  }

  /// 手动更新订单状态
  Future<void> updateStatus(String orderId,
      {OrderStatus? orderStatus, PrintStatus? printStatus})
  async {
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

      // 重试失败的订单
      await retryAllPendingSyncOrders();
      await retryAllPendingPrintOrders();

      _logger.i('订单维护任务完成');
    } catch (e) {
      _logger.e('订单维护任务失败: $e');
    }
  }

  /// 从服务器查询订单列表（用于收银台列表或历史数据同步）
  Future<List<ServerOrderModel>> fetchServerOrders({
    DateTime? date,
    DateTimeRange? dateRange,
  })
  async {
    try {
      if (!_apiService.isBaseUrlConfigured) {
        _logger.w('未配置后端 API 地址，跳过获取服务器订单');
        return [];
      }
      final baseParams = <String, dynamic>{};
      if (dateRange != null) {
        baseParams['start_date'] = dateRange.start.toStandardDateString();
        baseParams['end_date'] = dateRange.end.toStandardDateString();
      } else if (date != null) {
        baseParams['date'] = date.toStandardDateString();
      }

      final List<ServerOrderModel> allServerOrders = [];
      int currentPage = 1;
      bool hasMore = true;

      while (hasMore) {
        final queryParams = Map<String, dynamic>.from(baseParams);
        queryParams['page'] = currentPage;

        _logger.i('拉取服务器订单 (page: $currentPage)...');
        final response =
            await _apiService.get('orders/fetch-for-terminal', params: queryParams);

        if (response.statusCode != 200) {
          throw Exception('Failed to fetch orders: ${response.statusCode}');
        }

        final parsedPage = parseOrderResponseData(response.data);
        if (parsedPage.orders.isEmpty) {
          break;
        }

        final pageOrders = parsedPage.orders
            .map((orderMap) => ServerOrderModel.fromMap(orderMap))
            .toList();
        allServerOrders.addAll(pageOrders);

        _logger.i('服务器订单 page $currentPage 拉取到 ${pageOrders.length} 条 (已累计: ${allServerOrders.length})');

        if (parsedPage.hasMore && parsedPage.currentPage < parsedPage.lastPage) {
          currentPage++;
        } else {
          hasMore = false;
        }
      }

      return allServerOrders;
    } catch (e) {
      _logger.e('获取服务器订单失败: $e');
      rethrow;
    }
  }

  /// 将单笔服务器订单落地到本地
  Future<String> landServerOrderToLocal(
    ServerOrderModel serverOrder, {
    bool autoPrint = true,
    bool confirmPulled = true,
  })
  async {
    try {
      final alreadyExistsById =
          await _databaseService.existsOrderByRemoteId(serverOrder.id);
      final alreadyExistsByNumber = serverOrder.orderNumber.isNotEmpty
          ? await _databaseService
              .existsOrderByRemoteNumber(serverOrder.orderNumber)
          : false;

      // 该服务器订单已在本地落单
      if (alreadyExistsById || alreadyExistsByNumber) {
        _logger.i('服务器订单在本地已存在，跳过: ${serverOrder.orderNumber} (ID: ${serverOrder.id})');
        // 幂等自愈：若本地已存在但服务器再次下发，说明上次确认回调可能网络超时未送达，在此补发确认
        if (confirmPulled) {
          await confirmPulledOrders([serverOrder.id]);
        }
        return '';
      }

      final DateTime orderTime = serverOrder.orderTime ??
          (serverOrder.createdAt != null
              ? DateTime.tryParse(serverOrder.createdAt!) ?? DateTime.now()
              : DateTime.now());
      final DateTime createdAt = serverOrder.createdAt != null
          ? DateTime.tryParse(serverOrder.createdAt!) ?? orderTime
          : orderTime;

      final String orderId = 'ONLINE-${serverOrder.id}';

      // 映射 items 为本地统一数据结构
      final List<Map<String, dynamic>> localItems =
          OrderItemMapper.mapServerItemsToLocalItems(serverOrder.items);

      // 判定服务器订单是否已支付 (用于设置本地实付金额，决定 local OrderModel 的 isPaid 属性)
      final bool isPaid = serverOrder.isPaid;
      final double totalAmt = double.tryParse(serverOrder.finalAmount) ?? 0.0;
      final double paidAmtVal = double.tryParse(serverOrder.paidAmount) ?? 0.0;
      // 已支付订单记录已付金额；未支付 (到店支付 pending) 订单记 0.0，以便本地识别为未支付 (isPaid == false)
      final double cashAmt = isPaid ? (paidAmtVal > 0 ? paidAmtVal : totalAmt) : 0.0;

      // 订单主状态解析：
      // 1. 若服务器订单为 cancelled / refunded / completed 终态，映射为对应状态；
      // 2. 对于新下发的线上订单，无论是 pending (到店支付未结账) 还是 paid (线上已支付)，落地收银台后均统一为 OrderStatus.confirmed (已接单)！
      OrderStatus orderStatus;
      final String normStatus = serverOrder.normalizedStatus;
      if (normStatus == 'cancelled') {
        orderStatus = OrderStatus.cancelled;
      } else if (normStatus == 'refunded') {
        orderStatus = OrderStatus.refunded;
      } else if (normStatus == 'completed') {
        orderStatus = OrderStatus.completed;
      } else {
        // 到店支付 (pending) 或 线上已付 (paid/confirmed)，收银机接单落地后统一为 OrderStatus.confirmed
        orderStatus = OrderStatus.confirmed;
      }

      // 创建本地订单
      final order = OrderModel(
        id: orderId,
        orderNo: serverOrder.orderNo,
        orderTime: orderTime,
        createdAt: createdAt,
        items: jsonEncode(localItems),
        totalAmount: totalAmt,
        discountAmount: double.tryParse(serverOrder.discountAmount) ?? 0.0,
        taxRate: double.tryParse(serverOrder.taxRate) ?? 10.0,
        serviceFee: 0.0,
        cashAmount: cashAmt,
        posAmount: 0.0,
        orderStatus: orderStatus,
        syncStatus: SyncStatus.synced,
        printStatus: PrintStatus.pending,
        note: serverOrder.note,
        type: serverOrder.type,
        cashChange: 0.0,
        voucherAmount: 0.0,
        remoteOrderId: serverOrder.id,
        remoteOrderNumber: serverOrder.orderNumber,
        isOnlineOrder:
            serverOrder.placeIn == 'online' || serverOrder.placeIn.isEmpty,
      );

      // 保存到本地数据库 (orders 表和 server_orders 表)
      await _databaseService.insertOrder(order);
      await _databaseService.insertServerOrder(serverOrder.toMap());
      await _databaseService.insertLog(LogModel(
        orderId: order.id,
        action: 'fetch_remote',
        status: 'success',
        message: '服务器订单已同步落地到本地',
        timestamp: DateTime.now(),
      ));

      _logger.i('服务器订单落地成功: ${serverOrder.orderNumber} -> $orderId');

      if (autoPrint) {
        // 添加到打印队列
        await _addToPrintQueue(order);
      } else {
        await _databaseService.updateOrder(order.copyWith(
          printStatus: PrintStatus.skipped,
          printedTime: DateTime.now(),
        ));
      }

      if (confirmPulled) {
        await confirmPulledOrders([serverOrder.id]);
      }

      return orderId;
    } catch (e) {
      _logger.e('落地服务器订单失败: $e');
      rethrow;
    }
  }

  /// 重新打印服务器订单
  Future<void> reprintServerOrder(ServerOrderModel serverOrder) async {
    try {
      _logger.i('重新打印服务器订单: ${serverOrder.orderNumber}');

      final DateTime orderTime = serverOrder.orderTime ?? DateTime.now();
      final List<Map<String, dynamic>> localItems =
          OrderItemMapper.mapServerItemsToLocalItems(serverOrder.items);

      // 创建临时订单对象用于打印
      final tempOrder = OrderModel(
        id: 'ONLINE-${serverOrder.id}',
        orderNo: serverOrder.orderNo,
        orderTime: orderTime,
        createdAt: serverOrder.createdAt != null
            ? DateTime.tryParse(serverOrder.createdAt!) ?? DateTime.now()
            : DateTime.now(),
        items: jsonEncode(localItems),
        totalAmount: double.tryParse(serverOrder.finalAmount) ?? 0.0,
        discountAmount: double.tryParse(serverOrder.discountAmount) ?? 0.0,
        taxRate: double.tryParse(serverOrder.taxRate) ?? 10.0,
        note: serverOrder.note,
        type: serverOrder.type,
        remoteOrderId: serverOrder.id,
        remoteOrderNumber: serverOrder.orderNumber,
        isOnlineOrder:
            serverOrder.placeIn == 'online' || serverOrder.placeIn.isEmpty,
      );

      // 直接调用打印服务，不允许跳过
      await _printService.printOrderWithTemplates(tempOrder);
      _logger.i('服务器订单打印完成: ${serverOrder.orderNumber}');
    } catch (e) {
      _logger.e('打印服务器订单失败: $e');
      rethrow;
    }
  }

  /// 批量拉取历史服务器订单并落地到本地
  Future<int> restoreServerOrdersToLocal({DateTime? date}) async {
    try {
      final serverOrders = await fetchServerOrders(date: date);
      if (serverOrders.isEmpty) {
        return 0;
      }

      int count = 0;
      final List<dynamic> confirmedIds = [];
      for (final serverOrder in serverOrders) {
        final localOrderId = await landServerOrderToLocal(
          serverOrder,
          autoPrint: false, // 批量恢复历史订单默认跳过打单
          confirmPulled: false, // 统一在循环后确认
        );
        if (localOrderId.isNotEmpty) {
          count++;
          confirmedIds.add(serverOrder.id);
        }
      }

      if (confirmedIds.isNotEmpty) {
        await confirmPulledOrders(confirmedIds);
      }

      _logger.i('批量恢复服务器订单完成，成功同步落地 $count 个订单到本地数据库');
      return count;
    } catch (e) {
      _logger.e('批量恢复服务器订单失败: $e');
      rethrow;
    }
  }

  /// 回调告知服务器订单已成功拉取并处理
  Future<bool> confirmPulledOrders(List<dynamic> ids) async {
    if (ids.isEmpty) return true;
    try {
      if (!_apiService.isBaseUrlConfigured) {
        _logger.w('未配置后端 API 地址，跳过确认拉取回调');
        return true;
      }
      _logger.i('开始确认拉取后的订单： $ids');
      final response = await _apiService.post(
        '/orders/confirm-pulled-order',
        data: {'ids': ids},
      );
      if (response.statusCode == 200) {
        _logger.i('服务器订单已成功确认拉取: $ids');
        return true;
      } else {
        _logger.w('确认拉取订单失败，状态码: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _logger.e('确认拉取订单回调异常 ($ids): $e');
      return false;
    }
  }

  /// 通知顾客取餐（后厨菜品做好，标记本地订单为待取餐并触发叫号取餐通知推送）
  Future<void> notifyOrderReadyForPickup(OrderModel order) async {
    try {
      final updatedOrder = order.copyWith(
        orderStatus: OrderStatus.readyForPickup,
      );
      await _databaseService.updateOrder(updatedOrder);

      await _databaseService.insertLog(LogModel(
        orderId: order.id,
        action: 'notify_ready',
        status: 'success',
        message: '餐品制作完成，标记订单为待取餐 (ready_for_pickup) 并通知顾客',
        timestamp: DateTime.now(),
      ));

      _logger.i('订单已标记 ready_for_pickup 并触发取餐通知: ${order.id}');

      // 调用后端 API 通知顾客取餐 (/api/orders/notify-customer-ready)
      try {
        if (!_apiService.isBaseUrlConfigured) {
          _logger.w('未配置后端 API 地址，跳过触发取餐通知发包');
          return;
        }
        if (order.remoteOrderId != null ||
            (order.remoteOrderNumber?.isNotEmpty ?? false)) {
          await _apiService.post(
            '/orders/notify-customer-ready',
            data: {
              'remote_order_id': order.remoteOrderId,
              'remote_order_number': order.remoteOrderNumber,
              'order_no': order.orderNo,
              'status': 'ready_for_pickup',
            },
          );
        }
      } catch (e) {
        _logger.w('调用后端通知顾客取餐接口异常: $e');
      }
    } catch (e) {
      _logger.e('处理取餐通知异常: ${order.id}, 错误: $e');
      rethrow;
    }
  }

  /// 生成指定日期的日终结算汇总数据 (Daily Settlement / Z-Report)
  Future<DailySettlementModel> generateDailySettlement({DateTime? date}) async {
    final targetDate = date ?? DateTime.now();
    final start = DateTime(targetDate.year, targetDate.month, targetDate.day, 0, 0, 0);
    final end = DateTime(targetDate.year, targetDate.month, targetDate.day, 23, 59, 59, 999);

    final orders = await _databaseService.getOrdersByDateRange(start, end);

    double totalRevenue = 0;
    double cashRevenue = 0;
    double posRevenue = 0;
    double voucherRevenue = 0;
    double totalDiscount = 0;
    int totalOrders = orders.length;
    int completedOrders = 0;
    int cancelledOrders = 0;
    int dineInOrders = 0;
    double dineInRevenue = 0;
    int takeawayOrders = 0;
    double takeawayRevenue = 0;

    for (final order in orders) {
      if (order.orderStatus == OrderStatus.cancelled) {
        cancelledOrders++;
        continue;
      }

      completedOrders++;
      totalRevenue += order.totalAmount;
      totalDiscount += order.discountAmount;
      voucherRevenue += order.voucherAmount;

      if (order.cashAmount == 0 && order.posAmount == 0) {
        cashRevenue += order.totalAmount;
      } else {
        cashRevenue += order.cashAmount;
        posRevenue += order.posAmount;
      }

      if (order.isDineIn) {
        dineInOrders++;
        dineInRevenue += order.totalAmount;
      } else {
        takeawayOrders++;
        takeawayRevenue += order.totalAmount;
      }
    }

    final dateStr = '${targetDate.year}${targetDate.month.toString().padLeft(2, '0')}${targetDate.day.toString().padLeft(2, '0')}';
    final settlementId = 'Z-$dateStr';

    return DailySettlementModel(
      settlementId: settlementId,
      date: targetDate,
      createdAt: DateTime.now(),
      totalRevenue: totalRevenue,
      cashRevenue: cashRevenue,
      posRevenue: posRevenue,
      voucherRevenue: voucherRevenue,
      totalDiscount: totalDiscount,
      totalOrders: totalOrders,
      completedOrders: completedOrders,
      cancelledOrders: cancelledOrders,
      dineInOrders: dineInOrders,
      dineInRevenue: dineInRevenue,
      takeawayOrders: takeawayOrders,
      takeawayRevenue: takeawayRevenue,
      averageOrderValue: completedOrders > 0 ? totalRevenue / completedOrders : 0,
    );
  }

  /// 执行日结：记日志、打纸质小票、并提交给服务器预留 API
  Future<void> executeDailySettlement(DailySettlementModel settlement) async {
    try {
      _logger.i('开始执行日终结算 (Z-Report): ${settlement.settlementId}');

      // 1. 本地日志记录
      await _databaseService.insertLog(LogModel(
        orderId: settlement.settlementId,
        action: 'daily_settlement',
        status: 'success',
        message: '[Z-Report 日终结算] 完成总额: ￥${settlement.totalRevenue.toStringAsFixed(2)}, 现金: ￥${settlement.cashRevenue.toStringAsFixed(2)}, POS: ￥${settlement.posRevenue.toStringAsFixed(2)}, 有效笔数: ${settlement.completedOrders}',
        timestamp: DateTime.now(),
      ));

      // 2. 打印纸质 Z-Report 日结总结小票
      await _printService.printDailySettlement(settlement);

      // 3. 预留：向后端 API 提交上报日结数据 (POST /api/reports/daily-settlement)
      try {
        await _apiService.post(
          '/reports/daily-settlement',
          data: settlement.toJson(),
        );
        _logger.i('日结数据已成功上报至服务器: ${settlement.settlementId}');
      } catch (e) {
        _logger.w('调用后端日结提交 API 预留接口（暂未开放）: $e');
      }
    } catch (e) {
      _logger.e('执行日结操作失败: $e');
      rethrow;
    }
  }
}
