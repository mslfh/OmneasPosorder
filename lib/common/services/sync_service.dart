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
import '../utils/type_utils.dart';

enum FetchOrdersStatus { success, error }

class FetchOrdersEvent {
  final FetchOrdersStatus status;
  final DateTime timestamp;
  FetchOrdersEvent(this.status, this.timestamp);
}

class SyncService {
  static final Logger _logger = Logger();
  late Dio _dio;
  final DatabaseService _databaseService = DatabaseService();
  final ApiService _apiService = ApiService();
  final ValueNotifier<FetchOrdersEvent?> fetchOrdersEventNotifier = ValueNotifier<FetchOrdersEvent?>(null);

  // 单例模式
  static SyncService? _instance;
  SyncService._internal() {
    _initDio();
  }

  factory SyncService() {
    _instance ??= SyncService._internal();
    return _instance!;
  }

  void _initDio() {
    _dio = Dio();
    _dio.options.connectTimeout = Duration(seconds: 10);
    _dio.options.receiveTimeout = Duration(seconds: 10);
    _dio.options.sendTimeout = Duration(seconds: 10);

    // 添加请求拦截器记录日志
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        _logger.d('请求: ${options.method} ${options.uri}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        _logger.d('响应: ${response.statusCode} ${response.requestOptions.uri}');
        handler.next(response);
      },
      onError: (error, handler) {
        _logger.e('网络错误: ${error.message}');
        handler.next(error);
      },
    ));
  }

  bool _hasValidBaseUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final parsed = Uri.tryParse(url.trim());
    return parsed != null && parsed.hasScheme && parsed.host.isNotEmpty;
  }

  String _normalizeBaseUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  bool get isBaseUrlConfigured => _hasValidBaseUrl(_dio.options.baseUrl);

  Map<String, dynamic> _buildTerminalOrderPayload(
    OrderModel order, {
    List<Map<String, dynamic>>? overrideItems,
  }) {
    final itemsList = overrideItems ?? order.getItemsList();

    final formattedItems = itemsList.map((item) {
      final itemId = NumberFormatUtils.toInt(item['id'] ?? item['product_id']);
      final quantity = NumberFormatUtils.toInt(item['quantity'] ?? item['count'], 1);
      final price = NumberFormatUtils.toDouble(
        item['price'] ?? item['product_selling_price'] ?? item['unit_price'],
      );
      final options = item['options'] ?? item['customization'] ?? [];

      return {
        'id': itemId,
        'quantity': quantity,
        'price': price,
        'options': options,
      };
    }).toList();

    final paidAmount = order.cashAmount + order.posAmount + order.voucherAmount;

    return {
      'order_id': order.id,
      if (order.remoteOrderId != null) 'remote_order_id': order.remoteOrderId,
      if (order.orderNo.isNotEmpty) 'order_no': order.orderNo,
      'type': order.normalizedApiType,
      'status': order.orderStatus == OrderStatus.completed ? 'completed' : 'pending',
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

  static String _formatOrderTimeStr(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  /// 推送单个订单到后端（自动根据 remoteOrderId 判定调用 /orders/terminal-place 或 /orders/terminal-sync）
  Future<void> syncOrder(String orderId) async {
    try {
      if (!isBaseUrlConfigured) {
        _logger.w('未配置后端 API 地址，跳过订单同步发包: $orderId');
        return;
      }

      final order = await _databaseService.getOrder(orderId);
      if (order == null) {
        throw Exception('订单不存在: $orderId');
      }

      // 自动判定：已存在远程 ID，则使用 terminal-sync 覆盖更新；否则使用 terminal-place 新建
      final isUpdate = order.remoteOrderId != null;
      var endpoint = isUpdate ? '/orders/terminal-sync' : '/orders/terminal-place';

      _logger.i('开始同步订单到后端 (${isUpdate ? "覆盖更新" : "新建创建"}): $orderId (endpoint: $endpoint)');
      LocalOrderLogHelper.logOrder(order, tag: 'SYNC_START', message: '发起网络同步请求 ($endpoint)');

      final requestData = _buildTerminalOrderPayload(order);

      _logger.d('发送到后端的数据 ($endpoint): ${const JsonEncoder.withIndent("  ").convert(requestData)}');

      Response response;
      try {
        response = await _apiService.post(
          endpoint,
          data: requestData,
        );
      } on DioException catch (e) {
        final errorMsg = e.response?.data?.toString() ?? e.message ?? '';
        // 容错兜底：若调用新建接口 (terminal-place) 时服务端返回"已存在"，自动切为 terminal-sync 覆盖更新
        if (!isUpdate &&
            (errorMsg.contains('已存在') ||
                errorMsg.contains('already exists') ||
                errorMsg.contains('Duplicate entry'))) {
          _logger.w('服务端提示订单已存在，自动回退切换至 terminal-sync 覆盖更新: $orderId');
          endpoint = '/orders/terminal-sync';
          response = await _apiService.post(
            endpoint,
            data: requestData,
          );
        } else {
          rethrow;
        }
      }

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
        _logger.i('订单同步成功: $orderId (remoteOrderId: $remoteOrderId)');
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

  /// 明确覆盖更新已有订单到后端 (POST /orders/terminal-sync)
  Future<void> syncTerminalOrder(
    OrderModel order, {
    List<Map<String, dynamic>>? overrideItems,
  }) async {
    try {
      if (!isBaseUrlConfigured) {
        _logger.w('未配置后端 API 地址，跳过终端订单同步发包: ${order.id}');
        return;
      }

      _logger.i('开始覆盖更新终端订单: ${order.id} (remoteOrderId: ${order.remoteOrderId})');
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

  /// 批量同步待同步订单
  Future<void> syncPendingOrders() async {
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

          await syncOrder(order.id);
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

      final response = await _dio.get(
        '/health', // 移除 /api 前缀，因为baseUrl已经包含了
        options: Options(
          receiveTimeout: Duration(seconds: 5),
        ),
      );
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
  }) async {
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

  /// 配置后端API地址
  void configureBaseUrl(String baseUrl) {
    final normalized = _normalizeBaseUrl(baseUrl);
    _dio.options.baseUrl = normalized;

    if (isBaseUrlConfigured) {
      _logger.i('后端API地址已配置: $normalized');
    } else {
      _logger.w('后端API地址未配置，网络任务将被跳过');
    }
  }

  void _notifyFetchStatus(FetchOrdersStatus status) {
    fetchOrdersEventNotifier.value = FetchOrdersEvent(status, DateTime.now());
  }

  /// 拉取服务器新订单并落地到本地数据库 (支持自动多页完整拉取)
  Future<void> fetchAndSyncRemoteOrders() async {
    try {
      if (!isBaseUrlConfigured) {
        _logger.w('未配置后端API地址，跳过拉取服务器订单任务');
        _notifyFetchStatus(FetchOrdersStatus.error);
        return;
      }

      int latestId = await _databaseService.getMaxRemoteOrderId() ?? 0;
      _logger.i('本地最新 remote_order_id: $latestId');

      int totalFetchedCount = 0;
      final orderService = OrderService();
      final List<dynamic> confirmedIds = [];
      bool hasMorePages = true;
      int currentPage = 1;

      while (hasMorePages) {
        final params = <String, dynamic>{
          'latestId': latestId,
          'page': currentPage,
        };

        final response = await _apiService.get(
          'orders/fetch-new-order',
          params: params,
        );

        if (response.statusCode != 200) {
          _logger.w('拉取服务器新订单失败，状态码: ${response.statusCode}');
          break;
        }

        final parsedPage = parseOrderResponseData(response.data);
        final rawOrders = parsedPage.orders;

        if (rawOrders.isEmpty) {
          break;
        }

        _logger.i('第 $currentPage 页拉取到 ${rawOrders.length} 个新订单');

        for (final rawOrder in rawOrders) {
          try {
            final serverOrder = ServerOrderModel.fromMap(rawOrder);

            final localOrderId = await orderService.putServerOrderToLocal(
              serverOrder,
              autoPrint: true,
              confirmPulled: false, // 批量拉取统一在循环后进行回调确认
            );

            if (localOrderId.isNotEmpty) {
              _logger.i('新订单已同步落地到本地并队列打印: ${serverOrder.orderNumber}');
            }
            confirmedIds.add(serverOrder.id);
            totalFetchedCount++;

            if (serverOrder.id > latestId) {
              latestId = serverOrder.id;
            }
          } catch (e, st) {
            _logger.e('处理单笔服务器新订单落地失败: $e\n$st');
          }
        }

        if (parsedPage.hasMore && parsedPage.currentPage < parsedPage.lastPage) {
          currentPage++;
        } else {
          hasMorePages = false;
        }
      }

      _logger.i('新订单全部页拉取完成，共拉取到 $totalFetchedCount 个新订单');

      if (confirmedIds.isNotEmpty) {
        final isSuccess = await orderService.confirmPulledOrders(confirmedIds);
        if (isSuccess) {
          _notifyFetchStatus(FetchOrdersStatus.success);
        } else {
          _notifyFetchStatus(FetchOrdersStatus.error);
        }
      } else {
        _notifyFetchStatus(FetchOrdersStatus.success);
      }
    } catch (e, stack) {
      _logger.e('同步服务器订单异常: $e\n$stack');
      _notifyFetchStatus(FetchOrdersStatus.error);
    }
  }
}
