import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../models/order_model.dart';
import 'database_service.dart';

class SyncService {
  static final Logger _logger = Logger();
  late Dio _dio;
  final DatabaseService _databaseService = DatabaseService();

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

    // 设置默认的API地址（演示用）
    _dio.options.baseUrl = 'https://api.example.com';

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

  /// 同步单个订单到后端
  Future<void> syncOrder(String orderId) async {
    try {
      final order = await _databaseService.getOrder(orderId);
      if (order == null) {
        throw Exception('订单不存在: $orderId');
      }

      _logger.i('开始同步订单到后端: $orderId');

      // 构建请求数据
      final requestData = {
        'order_id': order.id,
        'order_time': order.orderTime.toIso8601String(),
        'items': jsonDecode(order.items),
        'total_amount': order.totalAmount,
        'local_created_at': order.orderTime.toIso8601String(),
      };

      // 发送到后端API
      final response = await _dio.post(
        '/orders/place', // 移除 /api 前缀，因为baseUrl已经包含了
        data: requestData,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${await _getAuthToken()}',
          },
        ),
      );

      // 检查响应
      if (response.statusCode == 200 || response.statusCode == 201) {
        // 同步成功，更新本地状态
        await _updateOrderSyncSuccess(order);
        _logger.i('订单同步成功: $orderId');
      } else {
        throw Exception('后端返回错误状态: ${response.statusCode}');
      }

    } on DioException catch (e) {
      await _handleSyncError(orderId, e);
      rethrow;
    } catch (e) {
      await _handleSyncError(orderId, e);
      rethrow;
    }
  }

  /// 批量同步待同步订单
  Future<void> syncPendingOrders() async {
    try {
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
  Future<void> _updateOrderSyncSuccess(OrderModel order) async {
    final updatedOrder = order.copyWith(
      orderStatus: OrderStatus.synced,
      syncedTime: DateTime.now(),
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
      orderStatus: OrderStatus.pendingSync,
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

  /// 手动重置订单同步状态
  Future<void> resetOrderSyncStatus(String orderId) async {
    final order = await _databaseService.getOrder(orderId);
    if (order == null) return;

    final resetOrder = order.copyWith(
      orderStatus: OrderStatus.pendingSync,
      errorMessage: null,
      retryCount: 0,
      lastRetryTime: null,
    );

    await _databaseService.updateOrder(resetOrder);

    // 记录重置日志
    await _databaseService.insertLog(LogModel(
      orderId: orderId,
      action: 'sync',
      status: 'reset',
      message: '手动重置同步状态',
      timestamp: DateTime.now(),
    ));

    _logger.i('订单同步状态已重置: $orderId');
  }

  /// 配置后端API地址
  void configureBaseUrl(String baseUrl) {
    _dio.options.baseUrl = baseUrl;
    _logger.i('后端API地址已配置: $baseUrl');
  }
}
