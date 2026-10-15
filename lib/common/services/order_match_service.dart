import 'dart:convert';
import 'package:logger/logger.dart';
import '../models/order_model.dart';
import '../models/server_order_model.dart';
import 'order_service.dart';
import 'database_service.dart';

/// 匹配结果严重级别 (用于指示图标颜色及系统状态)
enum OrderMatchSeverity {
  green,  // 绿色：完全正常，本地与服务器订单完全比对匹配
  orange, // 橙黄色：有未同步到服务器的本地订单
  red,    // 红色：有未拉取落盘到本地的服务器订单，或存在数据不一致异常
}

/// 统一订单匹配验证结果模型
class OrderMatchResult {
  final OrderMatchSeverity severity;
  final bool isMatched; // 当且仅当 severity == green 时为 true
  final int totalCount;
  final int normalCount;
  final int missingInLocalCount;  // 未落单 (服务器有，本地没有)
  final int missingInServerCount; // 未同步 (本地有，服务器没有)
  final int dataMismatchCount;    // 数据异常 (数据对应但字段不一致)
  final List<String> mismatchSummary; // 详细异常描述
  final String? errorMessage;
  final DateTime lastCheckTime;

  OrderMatchResult({
    required this.severity,
    required this.isMatched,
    this.totalCount = 0,
    this.normalCount = 0,
    this.missingInLocalCount = 0,
    this.missingInServerCount = 0,
    this.dataMismatchCount = 0,
    this.mismatchSummary = const [],
    this.errorMessage,
    required this.lastCheckTime,
  });

  factory OrderMatchResult.error(String msg) {
    return OrderMatchResult(
      severity: OrderMatchSeverity.red,
      isMatched: false,
      errorMessage: msg,
      lastCheckTime: DateTime.now(),
    );
  }

  /// 获取所有不匹配项/异常的描述列表
  List<String> getMismatchedItems() => mismatchSummary;
}

class OrderMatchService {
  static final Logger _logger = Logger();
  static final OrderMatchService _instance = OrderMatchService._internal();

  factory OrderMatchService() => _instance;
  OrderMatchService._internal();

  final OrderService _orderService = OrderService();

  /// 执行当天 (或指定日期) 的服务器与本地订单数据比对与分类匹配
  Future<OrderMatchResult> verifyOrdersMatch({DateTime? targetDate}) async {
    final today = targetDate ?? DateTime.now();

    try {
      // 1. 获取服务器订单
      List<ServerOrderModel> serverOrders = [];
      try {
        serverOrders = await _orderService.getServerOrders(date: today);
      } catch (e) {
        _logger.w('订单匹配验证：获取服务器订单失败 ($e)');
        return OrderMatchResult.error('获取服务器订单失败: $e');
      }

      // 2. 获取本地订单
      final localOrders = await _orderService.getOrders(
        limit: 1000,
        date: today,
      );

      // 3. 执行单条对比分类
      final Set<String> matchedLocalIds = {};
      int normalCount = 0;
      int missingInLocalCount = 0;
      int missingInServerCount = 0;
      int dataMismatchCount = 0;
      final List<String> summary = [];

      for (final server in serverOrders) {
        OrderModel? matchedLocal;

        for (final local in localOrders) {
          if (matchedLocalIds.contains(local.id)) {
            continue;
          }

          bool isMatch = false;
          if (local.remoteOrderId != null && local.remoteOrderId == server.id) {
            isMatch = true;
          } else if (local.remoteOrderNumber != null &&
              local.remoteOrderNumber!.isNotEmpty &&
              local.remoteOrderNumber == server.orderNumber) {
            isMatch = true;
          } else if (local.orderNo.isNotEmpty &&
              local.orderNo == server.orderNo &&
              _isSameDay(local.orderTime,
                  server.orderTime ?? (server.createdAt != null ? DateTime.tryParse(server.createdAt!) ?? local.orderTime : local.orderTime))) {
            isMatch = true;
          }

          if (isMatch) {
            matchedLocal = local;
            matchedLocalIds.add(local.id);
            break;
          }
        }

        if (matchedLocal == null) {
          final dbService = DatabaseService();
          OrderModel? dbOrder = await dbService.getOrderByRemoteId(server.id);
          if (dbOrder == null && server.orderNumber.isNotEmpty) {
            dbOrder = await dbService.getOrderByRemoteNumber(server.orderNumber);
          }
          if (dbOrder != null && !matchedLocalIds.contains(dbOrder.id)) {
            matchedLocal = dbOrder;
            matchedLocalIds.add(dbOrder.id);
          }
        }

        if (matchedLocal != null) {
          final mismatches = compareOrderData(matchedLocal, server);
          if (mismatches.isEmpty) {
            normalCount++;
          } else {
            dataMismatchCount++;
            summary.add('Order ${server.orderNo}: ${mismatches.join(", ")}');
          }
        } else {
          missingInLocalCount++;
          summary.add('服务器订单 #${server.orderNumber} 未拉取到本地数据库');
        }
      }

      // 3.2 遍历未匹配到的本地订单 (说明未同步)
      for (final local in localOrders) {
        if (!matchedLocalIds.contains(local.id)) {
          missingInServerCount++;
          summary.add('本地订单 ${local.orderNo} 尚未同步到服务器');
        }
      }

      final totalCount = serverOrders.length + missingInServerCount;

      // 4. 根据比对结果判定 severity (颜色指示)
      // - 红色 (red): 有未落单 (missingInLocal) 或 数据异常 (dataMismatch)
      // - 橙色 (orange): 有未同步 (missingInServer)
      // - 绿色 (green): 完全正常匹配
      OrderMatchSeverity severity = OrderMatchSeverity.green;
      if (missingInLocalCount > 0 || dataMismatchCount > 0) {
        severity = OrderMatchSeverity.red;
      } else if (missingInServerCount > 0) {
        severity = OrderMatchSeverity.orange;
      }

      final result = OrderMatchResult(
        severity: severity,
        isMatched: severity == OrderMatchSeverity.green,
        totalCount: totalCount,
        normalCount: normalCount,
        missingInLocalCount: missingInLocalCount,
        missingInServerCount: missingInServerCount,
        dataMismatchCount: dataMismatchCount,
        mismatchSummary: summary,
        lastCheckTime: DateTime.now(),
      );

      _logger.i('订单匹配验证完成: severity=${severity.name}, total=$totalCount, normal=$normalCount, missingLocal=$missingInLocalCount, missingServer=$missingInServerCount, mismatch=$dataMismatchCount');
      return result;
    } catch (e) {
      _logger.e('订单匹配验证异常: $e');
      return OrderMatchResult.error('验证异常: $e');
    }
  }

  /// 共享的订单字段对比方法
  static List<String> compareOrderData(OrderModel local, ServerOrderModel server) {
    final details = <String>[];

    // 1. 同步状态
    if (local.syncStatus != SyncStatus.synced &&
        local.syncStatus != SyncStatus.skipped) {
      details.add('本地未同步到服务器');
    }

    // 2. 金额对比
    final serverAmount = double.tryParse(server.finalAmount) ?? 0.0;
    if ((local.totalAmount - serverAmount).abs() > 0.01) {
      details.add('金额不一致 (本地 ￥${local.totalAmount.toStringAsFixed(2)} / 服务器 ￥${serverAmount.toStringAsFixed(2)})');
    }

    // 3. 序号对比
    if (local.orderNo.isNotEmpty &&
        server.orderNo.isNotEmpty &&
        local.orderNo != server.orderNo) {
      details.add('序号不匹配 (本地 ${local.orderNo} / 服务器 ${server.orderNo})');
    }

    // 4. 菜品项数对比
    int localItemCount = 0;
    try {
      final decoded = jsonDecode(local.items);
      if (decoded is List) {
        localItemCount = decoded.length;
      }
    } catch (_) {}
    if (localItemCount != server.items.length) {
      details.add('菜品项数不一致 (本地 $localItemCount 项 / 服务器 ${server.items.length} 项)');
    }

    return details;
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
