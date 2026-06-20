import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../models/order_model.dart';
import 'database_service.dart';
import 'print_service.dart';

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

  /// 推送单个订单到后端（支持传递printStatus）
  Future<void> syncOrder(String orderId, {PrintStatus? printStatus}) async {
    try {
      final order = await _databaseService.getOrder(orderId);
      if (order == null) {
        throw Exception('订单不存在: $orderId');
      }
      // 新增：如果是服务器订单，直接跳过同步
      if (order.isOnlineOrder) {
        _logger.i('Online Order不需要同步到服务器: $orderId');
        return;
      }

      // 打印原始订单数据
      print('\n========== 订单同步开始 ==========');
      print('原始订单数据:');
      print('--------------------------------');

      _logger.i('开始同步订单到后端: $orderId');

      // 构建请求数据，增加print_status字段
      final requestData = {
        'order_id': order.id,
        'order_no': order.orderNo,
        'order_time': order.orderTime.toIso8601String(),
        'items': jsonDecode(order.items),
        'total_amount': order.totalAmount,
        'discount_amount': order.discountAmount,
        'tax_rate': order.taxRate,
        'service_fee': order.serviceFee,
        'cash_amount': order.cashAmount,
        'pos_amount': order.posAmount,
        'cash_change': order.cashChange,
        'local_created_at': order.orderTime.toIso8601String(),
        'note': order.note,
        'type': order.type,
        'print_status': (printStatus ?? order.printStatus).toString().split('.').last, // 传递打印状态
      };

      // 打印格式化的请求数据
      print('\n发送到后端的数据:');
      print(const JsonEncoder.withIndent('  ').convert(requestData));
      print('--------------------------------');

      // 发送到后端API
      final response = await _dio.post(
        '/orders/terminal-place',
        data: requestData,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer \'${await _getAuthToken()}\'',
          },
        ),
      );

      // 打印响应数据
      print('\n后端响应数据:');
      print('状态码: ${response.statusCode}');
      print('响应数据:');
      print(const JsonEncoder.withIndent('  ').convert(response.data));
      print('========== 订单同步结束 ==========\n');

      // 检查响应
      if (response.statusCode == 200 || response.statusCode == 201) {
        final remoteOrderId = response.data['data']['id'];
        // 同步成功，更新本地状态
        await _updateOrderSyncSuccess(order, remoteOrderId);
        _logger.i('订单同步成功: $orderId');
      } else {
        throw Exception('后端返回错误状态: ${response.statusCode}');
      }

    } on DioException catch (e) {
      print('\n========== 同步错误信息 ==========');
      print('错误类型: DioException');
      print('错误消息: ${e.message}');
      print('错误响应: ${e.response?.data != null ? const JsonEncoder.withIndent('  ').convert(e.response?.data) : "无响应数据"}');
      print('================================\n');

      await _handleSyncError(orderId, e);
      rethrow;
    } catch (e) {
      print('\n========== 同步错误信息 ==========');
      print('错误类型: ${e.runtimeType}');
      print('错误消息: $e');
      print('================================\n');

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
  Future<void> _updateOrderSyncSuccess(OrderModel order, dynamic remoteOrderId) async {
    final updatedOrder = order.copyWith(
      orderStatus: OrderStatus.synced,
      syncedTime: DateTime.now(),
      remoteOrderId: remoteOrderId,
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
      orderStatus: order.orderStatus == OrderStatus.synced ? OrderStatus.synced : OrderStatus.pendingSync,
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
    _dio.options.baseUrl = baseUrl;
    _logger.i('后端API地址已配置: $baseUrl');
  }

  /// 拉取服务器新订单并同步到本地数据库
  Future<void> fetchAndSyncRemoteOrders() async {
    try {

      // 1. 获取本地已同步的最大 remote_order_id
      int latestId = await _databaseService.getMaxRemoteOrderId() ?? 0;
      //Debug for 0
      _logger.i('本地最新remote_order_id: $latestId');

      // 2. 拉取服务器新订单
      final response = await _dio.get('/orders/fetch-new-order?latestId=$latestId');
      if (response.statusCode == 200 && response.data['success'] == true) {
        final List<dynamic> orders = response.data['data'] ?? [];
        _logger.i('拉取到${orders.length}个新订单');
        for (final order in orders) {
          print('拉取到新订单: ${const JsonEncoder.withIndent('  ').convert(order)}');
          // 3. 插入server_orders表
          await _databaseService.insertServerOrder(order);
          final remoteOrderNumber = order['order_number'];
          final remoteOrderId = order['id'];
          // 4. 本地orders表去重，插入本地orders表并触发打印
          final exists = await _databaseService.existsOrderByRemoteNumber(remoteOrderNumber);
          if (!exists) {
            // 使用方法映射items和options
            final items = _mapServerItemsToLocalItems(order['items'] as List<dynamic>? ?? []);
            // 为拉取的订单生成本地唯一ID（避免与本地订单ID冲突）
            // 保证本地ID的唯一性和一致性，同时通过remoteOrderId和remoteOrderNumber追踪来源
            final now = DateTime.now();
            final localOrderId = 'ONLINE-$remoteOrderId-${now.millisecondsSinceEpoch}';
            final remoteOrderTime = _parseRemoteOrderTime(order);
            // 映射为本地OrderModel
            final orderModel = OrderModel(
              id: localOrderId, // 生成的唯一本地ID，避免与本地订单ID冲突
              orderNo: order['order_no'] ?? '',
              orderTime: remoteOrderTime,
              items: jsonEncode(items),
              totalAmount: double.tryParse(order['total_amount'] ?? '0') ?? 0.0,
              discountAmount: double.tryParse(order['discount_amount'] ?? '0') ?? 0.0,
              taxRate: double.tryParse(order['tax_rate'] ?? '10') ?? 10.0,
              serviceFee: 0.0,
              cashAmount: 0.0, // 线下支付，初始为0
              posAmount: 0.0,  // 线下支付，初始为0
              orderStatus: OrderStatus.synced, // 服务器订单状态应为已同步
              printStatus: PrintStatus.pending,
              note: order['note'],
              type: order['type'],
              cashChange: 0.0,
              voucherAmount: 0.0,
              remoteOrderId: remoteOrderId,
              remoteOrderNumber: remoteOrderNumber,
              isOnlineOrder: true, // 标记为服务器拉取订单
            );
            // 插入本地orders表并触发打印
            await _databaseService.insertOrder(orderModel);
            _logger.i('新订单已同步到本地并待打印: $remoteOrderNumber');
            // 记录拉取日志
            await _databaseService.insertLog(LogModel(
              orderId: orderModel.id,
              action: 'fetch_remote',
              status: 'success',
              message: '服务器新订单已拉取并同步到本地',
              timestamp: DateTime.now(),
            ));

            // 触发打印流程
            final printService = PrintService();
            // 使用样式打印双联小票（顾客用+后厨用）
            await printService.printOrderWithTemplates(orderModel);
          }
          else {
            _logger.i('订单已存在本地: $remoteOrderNumber');
          }
        }
        // 5. 回调接口告知服务器订单已成功拉取并处理
        _logger.i('开始确认拉取后的订单：');
        _logger.i(orders.map((o) => o['id']).toList());

        if(orders.isEmpty) {
          _logger.i('没有新订单需要确认拉取');
          return;
        }
        else{
          final resp =  await _dio.post('/orders/confirm-pulled-order', data: {
            'ids': orders.map((o) => o['id']).toList(),
          }, options: Options(
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer \'${await _getAuthToken()}\'',
            },
          ));
          if (resp.statusCode == 200) {
            _logger.i('服务器订单已成功拉取并处理');
          } else {
            _logger.w('确认拉取订单失败: ${response.data['message'] ?? response.statusMessage}');
          }
        }
      } else {
        _logger.w('拉取服务器订单失败: ${response.data['message'] ?? response.statusMessage}');
      }

    } catch (e, stack) {
      _logger.e('同步服务器订单异常: $e\n$stack');
    }
  }

  /// 服务器items映射为本地OrderModel的items和options
  List<Map<String, dynamic>> _mapServerItemsToLocalItems(List<dynamic> serverItems) {
    return serverItems.map((item) {
      final customizations = item['customization'] as List<dynamic>? ?? [];
      final List<Map<String, dynamic>> options = [];
      for (final c in customizations) {
        if (c['type'] == 'replacement') {
          options.add({
            'type': 'CHANGE',
            'option_id': null,
            //'option_name': '${c['originalName']}->${c['replacementName']}',
            'option_name': '${c['replacementName']}',
            'extra_price': double.tryParse(c['priceChange']?.toString() ?? '0') ?? 0.0,
          });
        } else if (c['type'] == 'quantity') {
          final int original = int.tryParse(c['originalQuantity']?.toString() ?? '0') ?? 0;
          final int current = int.tryParse(c['currentQuantity']?.toString() ?? '0') ?? 0;
          final int diff = current - original;
          final double priceChange = double.tryParse(c['priceChange']?.toString() ?? '0') ?? 0.0;
          if (diff > 0) {
            final double singlePrice = diff > 0 ? priceChange / diff : priceChange;
            for (int i = 0; i < diff; i++) {
              final ingredientName = c['ingredientName']?.toString() ?? '';
              final hasExtra = ingredientName.toLowerCase().contains('extra');
              final normalizedName = hasExtra 
                ? ingredientName.replaceAll(RegExp(r'extra|Extra|EXTRA', caseSensitive: false), 'EXTRA')
                : 'EXTRA $ingredientName';
              options.add({
                'type': 'EXTRA',
                'option_id': null,
                'option_name': normalizedName,
                'extra_price': singlePrice,
              });
            }
          }
          else if (diff < 0 && current == 0) {
            options.add({
              'type': 'NO',
              'option_id': null,
              'option_name': 'No ${c['ingredientName']}',
              'extra_price': priceChange,
            });
          }
          else if (diff < 0 && current > 0)
          {
            options.add({
              'type': 'CHANGE',
              'option_id': null,
              'option_name': '${c['ingredientName']} - ${current.abs()}',
              'extra_price': priceChange,
            });
          }
        }
      }
       return {
         'id': item['product_id'],
         'name': item['product_title'],
         'price': double.tryParse(item['final_amount']?.toString() ?? '0') ?? 0.0,
         'quantity': item['quantity'] ?? 1,
         'options': options,
         'is_printable': item['product']['is_printable'] ?? true,
       };
    }).toList();
  }

  DateTime _parseRemoteOrderTime(Map<String, dynamic> order) {
    final rawOrderTime = order['order_time']?.toString();
    if (rawOrderTime != null && rawOrderTime.isNotEmpty) {
      final normalized = rawOrderTime.contains('T')
          ? rawOrderTime
          : rawOrderTime.replaceFirst(' ', 'T');
      final parsed = DateTime.tryParse(normalized);
      if (parsed != null) {
        return parsed.toLocal();
      }
    }

    final rawCreatedAt = order['created_at']?.toString();
    if (rawCreatedAt != null && rawCreatedAt.isNotEmpty) {
      final parsed = DateTime.tryParse(rawCreatedAt);
      if (parsed != null) {
        return parsed.toLocal();
      }
    }

    return DateTime.now();
  }
}
