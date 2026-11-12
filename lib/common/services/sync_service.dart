import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../models/order_model.dart';
import '../models/server_order_model.dart';
import 'api_service.dart';
import 'database_service.dart';
import 'order_service.dart';
import '../utils/local_order_log_helper.dart';
import '../utils/order_item_mapper.dart';
import '../utils/type_utils.dart';

enum FetchOrdersStatus { success, error }

class FetchOrdersEvent {
  final FetchOrdersStatus status;
  final DateTime timestamp;
  FetchOrdersEvent(this.status, this.timestamp);
}

class SyncService {
  static final Logger _logger = Logger();
  final DatabaseService _databaseService = DatabaseService();
  final ApiService _apiService = ApiService();
  final ValueNotifier<FetchOrdersEvent?> fetchOrdersEventNotifier = ValueNotifier<FetchOrdersEvent?>(null);

  // 单例模式
  static SyncService? _instance;
  SyncService._internal();

  factory SyncService() {
    _instance ??= SyncService._internal();
    return _instance!;
  }

  bool get isBaseUrlConfigured => _apiService.isBaseUrlConfigured;

  //将本地订单映射为服务器订单载荷
  Map<String, dynamic> _buildTerminalOrderPayload(
    OrderModel order, {
    List<Map<String, dynamic>>? overrideItems,
  }) {
    final itemsList = overrideItems ?? order.getItemsList();

    final formattedItems = itemsList
        .map((item) => item.toStandardTerminalPayload())
        .toList();

    final paidAmount = (order.cashAmount - order.cashChange) + order.posAmount + order.voucherAmount;

    return {
      'order_number': order.id,
      'order_no': order.orderNo,
      if (order.remoteOrderId != null) 'remote_order_id': order.remoteOrderId,
      if (order.remoteOrderNumber != null) 'remote_order_number': order.remoteOrderNumber,
      'type': order.normalizedApiType,
      'status': order.orderStatus.apiValue,
      'print_status': order.printStatus.apiValue,
      'order_time': order.orderTime.toStandardDateTimeString(),
      'note': order.note ?? '',
      'total_amount': order.totalAmount,
      'paid_amount': paidAmount,
      'service_fee': order.serviceFee,
      'discount_amount': order.discountAmount,
      'cash_amount': order.cashAmount,
      'cash_change': order.cashChange,
      'pos_amount': order.posAmount,
      'voucher_amount': order.voucherAmount,
      if (order.tableName != null && order.tableName!.isNotEmpty)
        'table_name': order.tableName,
      'items': formattedItems,
    };
  }

  /// 【异步/后台推送订单入口】推送本地单个订单到云端服务器
  ///
  /// **业务场景**：
  /// - 1. 后台定时批量重试未同步订单任务
  /// - 2. 订单列表页 / 订单详情页点击“重新同步”按钮
  ///
  Future<void> pushOrderToRemote(String orderId) async {
    try {
      if (!isBaseUrlConfigured) {
        _logger.w('未配置后端 API 地址，跳过订单同步发包: $orderId');
        return;
      }

      final order = await _databaseService.getOrder(orderId);
      if (order == null) {
        throw Exception('订单不存在: $orderId');
      }

      // 1. 已存在远程 ID：调用 syncTerminalOrderChanges 覆盖更新服务器订单
      if (order.remoteOrderId != null) {
        await syncTerminalOrderChanges(order);
        return;
      }

      // 2. 本地新创建的订单：调用 POST /orders/terminal-place 接口进行服务器下单
      _logger.i('开始推送新订单到云端 (POST /orders/terminal-place): $orderId');
      LocalOrderLogHelper.logOrder(order, tag: 'SYNC_START', message: '发起网络同步请求 (/orders/terminal-place)');

      final requestData = _buildTerminalOrderPayload(order);

      _logger.d('发送到后端的数据 (/orders/terminal-place): ${const JsonEncoder.withIndent("  ").convert(requestData)}');

      Response response;
      try {
        response = await _apiService.post(
          '/orders/terminal-place',
          data: requestData,
        );
      } on DioException catch (e) {
        final errorMsg = e.response?.data?.toString() ?? e.message ?? '';
        // 容错兜底：若调用新建接口时服务端提示"已存在"，自动切为 syncTerminalOrderChanges 覆盖更新
        if (errorMsg.contains('已存在') ||
            errorMsg.contains('already exists') ||
            errorMsg.contains('Duplicate entry')) {
          _logger.w('服务端提示订单已存在，自动回退切换至 syncTerminalOrderChanges 覆盖更新: $orderId');
          await syncTerminalOrderChanges(order);
          return;
        } else {
          rethrow;
        }
      }

      _logger.d('后端响应数据 (状态码 ${response.statusCode}): ${response.data}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = response.data;
        final dataMap = resData is Map ? (resData['data'] ?? resData) : null;
        final remoteOrderId = dataMap?['id'];
        final remoteOrderNumber =
            (dataMap?['order_number'])?.toString();
        await _updateOrderSyncSuccess(
          order,
          remoteOrderId,
          remoteOrderNumber: remoteOrderNumber,
        );
        _logger.i('新订单创建同步成功: $orderId (remoteOrderId: $remoteOrderId)');
      } else {
        throw Exception('后端返回错误状态: ${response.statusCode}');
      }
    } on DioException catch (e) {
      _logger.e('同步 DioException 错误: ${e.message}, 响应: ${e.response?.data}');
      await _handleSyncError(orderId, e);
      rethrow;
    } catch (e) {
      _logger.e('同步异常: $e');
      await _handleSyncError(orderId, e);
      rethrow;
    }
  }

  /// 【内存态/改单结账同步入口】将本地已有订单的改单/加菜与最新状态同步至云端
  /// **业务场景**：
  /// - 收银台修改/加菜并结算时，将最新的与菜品一次性更新至服务端的菜品明细、总额与结账状态。
  Future<void> syncTerminalOrderChanges(
    OrderModel order, {
    List<Map<String, dynamic>>? overrideItems,
  })
  async {
    try {
      if (!isBaseUrlConfigured) {
        _logger.w('未配置后端 API 地址，跳过终端订单同步发包: ${order.id}');
        return;
      }

      _logger.i('开始更新终端订单: ${order.id} (remoteOrderId: ${order.remoteOrderId})');
      LocalOrderLogHelper.logOrder(order, tag: 'TERMINAL_SYNC_START', message: '覆盖更新已有订单数据 (/orders/terminal-sync)');

      final requestData = _buildTerminalOrderPayload(
        order,
        overrideItems: overrideItems,
      );

      _logger.d('发送到后端的数据 (/orders/terminal-sync): ${const JsonEncoder.withIndent("  ").convert(requestData)}');

      final response = await _apiService.post(
        '/orders/terminal-sync',
        data: requestData,
      );

      _logger.d('后端响应数据 (状态码 ${response.statusCode}): ${response.data}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = response.data;
        final dataMap = resData is Map ? (resData['data'] ?? resData) : null;
        final remoteOrderId = dataMap?['id'] ?? dataMap?['order_id'];
        final remoteOrderNumber =
            (dataMap?['order_number'] ?? dataMap?['order_no'])?.toString();
        await _updateOrderSyncSuccess(
          order,
          remoteOrderId,
          remoteOrderNumber: remoteOrderNumber,
        );
        _logger.i('终端订单覆盖更新成功: ${order.id} (remoteOrderId: $remoteOrderId)');
      } else {
        throw Exception('后端返回错误状态: ${response.statusCode}');
      }
    } catch (e) {
      _logger.e('终端订单覆盖更新失败: ${order.id}, 错误: $e');
      await _handleSyncError(order.id, e);
      rethrow;
    }
  }

  /// 终端完成订单收银结账 (POST /orders/complete-order-by-terminal)
  Future<void> completeOrderByTerminal(
    OrderModel order, {
    List<Map<String, dynamic>>? overrideItems,
  })
  async {
    try {
      if (!isBaseUrlConfigured) {
        _logger.w('未配置后端 API 地址，跳过终端完成订单发包: ${order.id}');
        return;
      }
      _logger.i('开始终端完成订单结账: ${order.id} (remoteOrderId: ${order.remoteOrderId})');
      LocalOrderLogHelper.logOrder(order, tag: 'COMPLETE_ORDER_START', message: '完成订单收银结账 (/orders/complete-order-by-terminal)');

      final completedOrder = order.copyWith(
        orderStatus: OrderStatus.completed,
        syncStatus: SyncStatus.synced,
      );
      final requestData = _buildTerminalOrderPayload(
        completedOrder,
        overrideItems: overrideItems,
      );

      Response response = await _apiService.post(
        '/orders/complete-order-by-terminal',
        data: requestData,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = response.data;
        final dataMap = resData is Map ? (resData['data'] ?? resData) : null;
        final remoteOrderId = dataMap?['id'] ?? dataMap?['order_id'];
        final remoteOrderNumber = (dataMap?['order_number'] ?? dataMap?['order_no'])?.toString();
        await _updateOrderSyncSuccess(
          completedOrder,
          remoteOrderId,
          remoteOrderNumber: remoteOrderNumber,
        );
      } else {
        throw Exception('后端返回错误状态: ${response.statusCode}');
      }
    } catch (e) {
      _logger.e('终端完成订单失败: ${order.id}, 错误: $e');
      await _handleSyncError(order.id, e);
      rethrow;
    }
  }


  /// 批量同步待同步订单
  Future<void> syncPendingOrders()
  async {
    try {
      if (!isBaseUrlConfigured) {
        _logger.w('未配置后端API地址，跳过批量同步任务');
        return;
      }

      final pendingOrders = await _databaseService.getPendingSyncOrders();

      if (pendingOrders.isEmpty) {
        _logger.i('没有待同步的订单');
        return;
      }

      _logger.i('开始批量同步 ${pendingOrders.length} 个订单');

      int successCount = 0;
      int failCount = 0;

      for (final order in pendingOrders) {
        try {
          // 检查重试间隔
          if (order.lastRetryTime != null) {
            final timeDiff = DateTime.now().difference(order.lastRetryTime!);
            if (timeDiff.inMinutes < 5) {
              continue; // 跳过频繁重试
            }
          }

          // 检查重试次数
          if (order.retryCount >= 10) {
            _logger.w('订单重试次数超限，标记为失败: ${order.id}');
            await _markOrderSyncFailed(order, '重试次数超限');
            failCount++;
            continue;
          }

          await pushOrderToRemote(order.id);
          successCount++;

          // 控制同步频率，避免对后端造成压力
          await Future.delayed(Duration(milliseconds: 500));
        } catch (e) {
          _logger.e('订单同步失败: ${order.id}, 错误: $e');
          failCount++;
        }
      }

      _logger.i('批量同步完成 - 成功: $successCount, 失败: $failCount');
    } catch (e) {
      _logger.e('批量同步过程出错: $e');
    }
  }

  /// 检查网络连接状态
  Future<bool> checkNetworkConnectivity() async {
    try {
      if (!isBaseUrlConfigured) {
        _logger.w('未配置后端API地址，跳过网络连通性检查');
        return false;
      }

      final response = await _apiService.get('health');
      return response.statusCode == 200;
    } catch (e) {
      _logger.w('网络连接检查失败: $e');
      return false;
    }
  }

  /// 更新订单同步成功状态
  Future<void> _updateOrderSyncSuccess(
    OrderModel order,
    dynamic remoteOrderId, {
    String? remoteOrderNumber,
  })
  async {
    final parsedRemoteId = remoteOrderId is int
        ? remoteOrderId
        : int.tryParse(remoteOrderId?.toString() ?? '');

    final updatedOrder = order.copyWith(
      syncStatus: SyncStatus.synced,
      syncedTime: DateTime.now(),
      remoteOrderId: parsedRemoteId ?? order.remoteOrderId,
      remoteOrderNumber: (remoteOrderNumber != null && remoteOrderNumber.isNotEmpty)
          ? remoteOrderNumber
          : order.remoteOrderNumber,
      errorMessage: null, // 清除错误信息
    );

    await _databaseService.updateOrder(updatedOrder);

    // 记录成功日志
    await _databaseService.insertLog(LogModel(
      orderId: order.id,
      action: 'sync',
      status: 'success',
      message: '同步到后端成功',
      timestamp: DateTime.now(),
    ));
  }

  /// 处理同步错误
  Future<void> _handleSyncError(String orderId, dynamic error) async {
    final order = await _databaseService.getOrder(orderId);
    if (order == null) return;

    String errorMessage = error.toString();

    // 分析错误类型
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          errorMessage = '网络超时';
          break;
        case DioExceptionType.connectionError:
          errorMessage = '网络连接失败';
          break;
        case DioExceptionType.badResponse:
          errorMessage = '服务器响应错误: ${error.response?.statusCode}';
          break;
        default:
          errorMessage = '网络请求失败: ${error.message}';
      }
    }

    // 更新订单错误信息
    final updatedOrder = order.copyWith(
      syncStatus: SyncStatus.syncFailed,
      errorMessage: errorMessage,
      retryCount: order.retryCount + 1,
      lastRetryTime: DateTime.now(),
    );

    await _databaseService.updateOrder(updatedOrder);

    // 记录错误日志
    await _databaseService.insertLog(LogModel(
      orderId: orderId,
      action: 'sync',
      status: 'error',
      message: errorMessage,
      timestamp: DateTime.now(),
    ));
  }

  /// 标记订单同步永久失败
  Future<void> _markOrderSyncFailed(OrderModel order, String reason) async {
    final updatedOrder = order.copyWith(
      errorMessage: reason,
      lastRetryTime: DateTime.now(),
    );

    await _databaseService.updateOrder(updatedOrder);

    // 记录失败日志
    await _databaseService.insertLog(LogModel(
      orderId: order.id,
      action: 'sync',
      status: 'failed',
      message: reason,
      timestamp: DateTime.now(),
    ));
  }

  /// 获取认证Token（从本地存储或其他来源）
  Future<String> _getAuthToken() async {
    // 这里应该从安全存储中获取token
    // 暂时返回空字符串，实际项目中需要实现
    return '';
  }

  /// 配置后端API地址（统一收口至 ApiService）
  void configureBaseUrl(String baseUrl) {
    _apiService.updateBaseUrlInternal(baseUrl);
    if (isBaseUrlConfigured) {
      _logger.i('后端API地址已配置: $baseUrl');
    } else {
      _logger.w('后端API地址未配置，网络任务将被跳过');
    }
  }

  void _notifyFetchStatus(FetchOrdersStatus status) {
    fetchOrdersEventNotifier.value = FetchOrdersEvent(status, DateTime.now());
  }

  /// 【后台/手动拉取新网单入口】拉取云端新产生的在线订单并落地到本地
  ///
  /// **业务场景**：
  /// - 1. 后台定时轮询任务（`BackgroundTaskManager`）定时调起拉取新网单
  /// - 2. 服务配置弹窗（`showServerConfigDialog`）点击“拉取/PULL”按钮手动触发
  ///
  Future<void> fetchAndLandNewRemoteOrders() async {
    try {
      if (!isBaseUrlConfigured) {
        _logger.w('未配置后端 API 地址，跳过拉取服务器新订单任务');
        _notifyFetchStatus(FetchOrdersStatus.error);
        return;
      }

      final int latestId = await _databaseService.getMaxRemoteOrderId() ?? 0;
      _logger.i('开始拉取服务器新网单，本地最新 remote_order_id: $latestId');

      final response = await _apiService.get(
        'orders/fetch-new-order',
        params: {'latestId': latestId},
      );

      if (response.statusCode != 200) {
        _logger.w('拉取服务器新订单失败，服务端状态码: ${response.statusCode}');
        _notifyFetchStatus(FetchOrdersStatus.error);
        return;
      }

      final parsedPage = parseOrderResponseData(response.data);
      final rawOrders = parsedPage.orders;

      if (rawOrders.isEmpty) {
        _logger.i('服务器暂无新网单');
        _notifyFetchStatus(FetchOrdersStatus.success);
        return;
      }

      _logger.i('成功拉取到 ${rawOrders.length} 条服务器新订单，开始依次落地到本地...');
      final orderService = OrderService();
      int landedCount = 0;

      for (final rawOrder in rawOrders) {
        try {
          final serverOrder = ServerOrderModel.fromMap(rawOrder);

          // 落地一笔即触发队列打单并向服务器确认拉取 (confirmPulled: true)
          final localOrderId = await orderService.landServerOrderToLocal(
            serverOrder,
            autoPrint: true,
            confirmPulled: true,
          );

          if (localOrderId.isNotEmpty) {
            _logger.i('新网单已成功落地本地并加入队列打印: ${serverOrder.orderNumber}');
            landedCount++;
          }
        } catch (e, st) {
          _logger.e('处理单笔服务器新订单落地失败: $e\n$st');
        }
      }

      _logger.i('服务器新订单处理完成，共新增落地 $landedCount 笔订单');
      _notifyFetchStatus(FetchOrdersStatus.success);
    } catch (e, stack) {
      _logger.e('拉取服务器新网单过程发生异常: $e\n$stack');
      _notifyFetchStatus(FetchOrdersStatus.error);
    }
  }
}
