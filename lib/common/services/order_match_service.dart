import 'package:logger/logger.dart';
import 'api_service.dart';
import 'database_service.dart';
import '../models/order_model.dart';

/// 订单匹配验证数据模型
class OrderMatchData {
  final int onlineCount;
  final int onlineSyncedCount;
  final String onlineLastOrderNo;
  final int terminalCount;
  final int terminalSyncedCount;
  final String terminalLastOrderNo;
  final int? latestOrderId;
  final int? latestRemoteOrderId;

  OrderMatchData({
    required this.onlineCount,
    required this.onlineSyncedCount,
    required this.onlineLastOrderNo,
    required this.terminalCount,
    required this.terminalSyncedCount,
    required this.terminalLastOrderNo,
    this.latestOrderId,
    this.latestRemoteOrderId,
  });

  factory OrderMatchData.fromJson(Map<String, dynamic> json) {
    return OrderMatchData(
      onlineCount: json['online_count'] as int? ?? 0,
      onlineSyncedCount: json['online_synced_count'] as int? ?? 0,
      onlineLastOrderNo: json['online_last_order_no'] as String? ?? '',
      terminalCount: json['terminal_count'] as int? ?? 0,
      terminalSyncedCount: json['terminal_synced_count'] as int? ?? 0,
      terminalLastOrderNo: json['terminal_last_order_no'] as String? ?? '',
      latestOrderId: _parseInt(json['latest_order_id']),
      latestRemoteOrderId: _parseInt(json['latest_remote_order_id']),
    );
  }
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

/// 订单匹配验证结果
class OrderMatchResult {
  final bool isMatched;
  final OrderMatchData? serverData;
  final OrderMatchData? localData;
  final String? onlineCountMatch; // null表示匹配
  final String? onlineSyncedMatch;
  final String? onlineLastOrderMatch;
  final String? terminalCountMatch;
  final String? terminalSyncedMatch;
  final String? terminalLastOrderMatch;
  final String? latestOrderIdMatch;
  final String? errorMessage;
  final DateTime? lastCheckTime;

  OrderMatchResult({
    required this.isMatched,
    this.serverData,
    this.localData,
    this.onlineCountMatch,
    this.onlineSyncedMatch,
    this.onlineLastOrderMatch,
    this.terminalCountMatch,
    this.terminalSyncedMatch,
    this.terminalLastOrderMatch,
    this.latestOrderIdMatch,
    this.errorMessage,
    this.lastCheckTime,
  });

  /// 获取所有不匹配项
  List<String> getMismatchedItems() {
    final items = <String>[];
    if (onlineCountMatch != null) items.add('Online订单数: $onlineCountMatch');
    if (onlineSyncedMatch != null) items.add('Online已同步数: $onlineSyncedMatch');
    if (onlineLastOrderMatch != null)
      items.add('Online最新号: $onlineLastOrderMatch');
    if (terminalCountMatch != null)
      items.add('Terminal订单数: $terminalCountMatch');
    if (terminalSyncedMatch != null)
      items.add('Terminal已同步数: $terminalSyncedMatch');
    if (terminalLastOrderMatch != null)
      items.add('Terminal最新号: $terminalLastOrderMatch');
    if (latestOrderIdMatch != null) items.add('最新订单ID: $latestOrderIdMatch');
    return items;
  }
}

class OrderMatchService {
  static final Logger _logger = Logger();
  static final OrderMatchService _instance = OrderMatchService._internal();

  factory OrderMatchService() => _instance;
  OrderMatchService._internal();

  final ApiService _apiService = ApiService();
  final DatabaseService _databaseService = DatabaseService();

  /// 获取服务器数据并执行订单匹配验证
  Future<OrderMatchResult> verifyOrdersMatch() async {
    try {
      final today = DateTime.now();
      final dateStr =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      // 1. 调用服务器接口获取数据，传递日期参数以确保同步
      final response = await _apiService
          .get('orders/match-order-data', params: {'date': dateStr});

      if (response.statusCode != 200) {
        return OrderMatchResult(
          isMatched: false,
          errorMessage: '服务器返回错误: ${response.statusCode}',
          lastCheckTime: DateTime.now(),
        );
      }

      // 解析响应数据
      final responseData = response.data as Map<String, dynamic>?;
      if (responseData == null || responseData['success'] != true) {
        return OrderMatchResult(
          isMatched: false,
          errorMessage: responseData?['message'] ?? '服务器响应格式错误',
          lastCheckTime: DateTime.now(),
        );
      }

      final data =
          OrderMatchData.fromJson(responseData['data'] as Map<String, dynamic>);

      // 2. 获取本地数据
      final localOrders = await _databaseService.getOrdersByDate(today);

      // 分离online订单（拉取的远程订单）和terminal订单（本地生成的订单）
      final onlineOrders = localOrders.where((o) => o.isOnlineOrder).toList();
      final terminalOrders =
          localOrders.where((o) => !o.isOnlineOrder).toList();

      // 已同步的online订单
      final onlineSyncedOrders =
          onlineOrders.where((o) => o.syncStatus == SyncStatus.synced).toList();

      // 已同步的terminal订单
      final terminalSyncedOrders = terminalOrders
          .where((o) => o.syncStatus == SyncStatus.synced)
          .toList();

      // 从数据库获取最大的 remote_order_id
      final latestRemoteOrderId =
          await _databaseService.getMaxRemoteOrderId() ?? 0;

      // 3. 执行验证
      String? onlineCountError;
      String? onlineSyncedError;
      String? onlineLastOrderError;
      String? terminalCountError;
      String? terminalSyncedError;
      String? terminalLastOrderError;
      String? latestOrderIdError;

      // 验证online订单数量
      if (onlineOrders.length != data.onlineCount) {
        onlineCountError = '本地${onlineOrders.length} != 服务器${data.onlineCount}';
      }

      // 验证online已同步数量
      if (onlineSyncedOrders.length != data.onlineSyncedCount) {
        onlineSyncedError =
            '本地${onlineSyncedOrders.length} != 服务器${data.onlineSyncedCount}';
      }

      // 验证online最新order_no
      final onlineLastOrderNo = _getLastOrderNo(onlineOrders);
      if (onlineLastOrderNo != data.onlineLastOrderNo) {
        onlineLastOrderError =
            '本地$onlineLastOrderNo != 服务器${data.onlineLastOrderNo}';
      }

      // 验证terminal订单数量
      if (terminalOrders.length != data.terminalCount) {
        terminalCountError =
            '本地${terminalOrders.length} != 服务器${data.terminalCount}';
      }

      // 验证terminal已同步数量
      if (terminalSyncedOrders.length != data.terminalSyncedCount) {
        terminalSyncedError =
            '本地${terminalSyncedOrders.length} != 服务器${data.terminalSyncedCount}';
      }

      // 验证terminal最新order_no
      final terminalLastOrderNo = _getLastOrderNo(terminalOrders);
      if (terminalLastOrderNo != data.terminalLastOrderNo) {
        terminalLastOrderError =
            '本地$terminalLastOrderNo != 服务器${data.terminalLastOrderNo}';
      }

      // 验证最新订单ID（本地 remote_order_id vs 服务器 latest_order_id）
      final serverLatestOrderId = data.latestOrderId ?? 0;
      if (latestRemoteOrderId != serverLatestOrderId) {
        latestOrderIdError =
            '本地$latestRemoteOrderId != 服务器$serverLatestOrderId';
      }

      final localData = OrderMatchData(
        onlineCount: onlineOrders.length,
        onlineSyncedCount: onlineSyncedOrders.length,
        onlineLastOrderNo: onlineLastOrderNo,
        terminalCount: terminalOrders.length,
        terminalSyncedCount: terminalSyncedOrders.length,
        terminalLastOrderNo: terminalLastOrderNo,
        latestRemoteOrderId: latestRemoteOrderId,
      );

      final isMatched = onlineCountError == null &&
          onlineSyncedError == null &&
          onlineLastOrderError == null &&
          terminalCountError == null &&
          terminalSyncedError == null &&
          terminalLastOrderError == null &&
          latestOrderIdError == null;

      final result = OrderMatchResult(
        isMatched: isMatched,
        serverData: data,
        localData: localData,
        onlineCountMatch: onlineCountError,
        onlineSyncedMatch: onlineSyncedError,
        onlineLastOrderMatch: onlineLastOrderError,
        terminalCountMatch: terminalCountError,
        terminalSyncedMatch: terminalSyncedError,
        terminalLastOrderMatch: terminalLastOrderError,
        latestOrderIdMatch: latestOrderIdError,
        lastCheckTime: DateTime.now(),
      );

      _logger.i('订单匹配验证完成: 匹配=$isMatched');
      return result;
    } catch (e) {
      _logger.e('订单匹配验证失败: $e');
      return OrderMatchResult(
        isMatched: false,
        errorMessage: '验证失败: $e',
        lastCheckTime: DateTime.now(),
      );
    }
  }

  /// 获取订单列表中的最后一个order_no
  String _getLastOrderNo(List<OrderModel> orders) {
    if (orders.isEmpty) return '';
    // 按order_time降序排序，获取最后一个订单
    orders.sort((a, b) => b.orderTime.compareTo(a.orderTime));
    return orders.first.orderNo;
  }
}
