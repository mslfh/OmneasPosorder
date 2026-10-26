import 'package:flutter/foundation.dart';
import '../models/order_model.dart';

/// 本地订单完整数据结构格式化控制台调试日志工具类
class LocalOrderLogHelper {
  /// 是否开启可视化控制台日志
  static bool enabled = true;

  /// 格式化并打印本地订单完整结构
  static void logOrder(
    OrderModel order, {
    required String tag,
    String? message,
  }) {
    if (!enabled || !kDebugMode) return;

    final buffer = StringBuffer();
    buffer.writeln('\n======================= [LOCAL ORDER DEBUG LOG] =======================');
    buffer.writeln('Tag / Action: [$tag] ${message ?? ""}');
    buffer.writeln('----------------------------------------------------------------------');

    // 1. 基础标识与类型信息
    buffer.writeln('【基础信息】');
    buffer.writeln('  • 本地 Order ID:       ${order.id}');
    buffer.writeln('  • 订单流水号 (orderNo): ${order.orderNo}');
    buffer.writeln('  • 下单时间 (createdAt):  ${_formatDateTime(order.createdAt)}');
    buffer.writeln('  • 预定/期望时间:        ${_formatDateTime(order.orderTime)}');
    buffer.writeln('  • 订单来源/场景:        ${order.displayOrderSource}');
    buffer.writeln('  • 是否在线订单:         ${order.isOnlineOrder ? "YES (Online)" : "NO (Offline/POS)"}');
    if (order.remoteOrderId != null || (order.remoteOrderNumber?.isNotEmpty ?? false)) {
      buffer.writeln('  • 服务器关联标识:       ID: ${order.remoteOrderId ?? "-"} / 单号: ${order.remoteOrderNumber ?? "-"}');
    }

    // 2. 状态与控制属性
    buffer.writeln('\n【状态与控制属性】');
    buffer.writeln('  • 订单业务状态 (orderStatus): ${_getOrderStatusLabel(order.orderStatus)}');
    buffer.writeln('  • 远程同步状态 (syncStatus):  ${_getSyncStatusLabel(order.syncStatus)}');
    buffer.writeln('  • 打印小票状态 (printStatus): ${_getPrintStatusLabel(order.printStatus)}');
    buffer.writeln('  • 重试次数 / 时间:          ${order.retryCount} 次 / ${order.lastRetryTime != null ? _formatDateTime(order.lastRetryTime!) : "无"}');
    buffer.writeln('  • 打印时间 / 同步时间:       ${order.printedTime != null ? _formatDateTime(order.printedTime!) : "未打"} / ${order.syncedTime != null ? _formatDateTime(order.syncedTime!) : "未同步"}');
    if (order.errorMessage != null && order.errorMessage!.isNotEmpty) {
      buffer.writeln('  • 异常错误信息:             ${order.errorMessage}');
    }

    // 3. 财务与支付分账明细
    buffer.writeln('\n【财务与支付明细】');
    buffer.writeln('  • 订单总金额 (total):       ￥${order.totalAmount.toStringAsFixed(2)}');
    buffer.writeln('  • 优惠折扣金额 (discount):  ￥${order.discountAmount.toStringAsFixed(2)}');
    buffer.writeln('  • 税率 / 服务费:            ${order.taxRate}% / ￥${order.serviceFee.toStringAsFixed(2)}');
    buffer.writeln('  • 现金实收 (cashAmount):     ￥${order.cashAmount.toStringAsFixed(2)}');
    buffer.writeln('  • POS刷卡实收 (posAmount):   ￥${order.posAmount.toStringAsFixed(2)}');
    buffer.writeln('  • 券抵扣金额 (voucher):      ￥${order.voucherAmount.toStringAsFixed(2)}');
    buffer.writeln('  • 现金找零 (cashChange):     ￥${order.cashChange.toStringAsFixed(2)}');
    buffer.writeln('  • 财务支付完成 (isPaid):     ${order.isPaid ? "YES (已付清)" : "NO (未付清)"}');

    // 4. 菜品结构化列表展开
    final items = order.getItemsList();
    buffer.writeln('\n【菜品明细结构 (${items.length}项)】');
    if (items.isEmpty) {
      buffer.writeln('  (无菜品数据)');
    } else {
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final name = item['name'] ?? item['product_title'] ?? '未知商品';
        final quantity = item['quantity'] ?? 1;
        final price = double.tryParse(item['price']?.toString() ?? item['product_selling_price']?.toString() ?? '0') ?? 0.0;
        final finalAmt = double.tryParse(item['final_amount']?.toString() ?? '') ?? (price * quantity);

        buffer.writeln('  ${i + 1}. $name  x$quantity  @ ￥${price.toStringAsFixed(2)}  = ￥${finalAmt.toStringAsFixed(2)}');

        final options = item['options'] as List<dynamic>? ?? [];
        if (options.isNotEmpty) {
          final optStrs = options.map((opt) {
            if (opt is Map) {
              final optName = opt['option_name'] ?? opt['name'] ?? '';
              final extra = double.tryParse(opt['extra_price']?.toString() ?? '0') ?? 0.0;
              return extra > 0 ? '$optName(+￥${extra.toStringAsFixed(2)})' : optName;
            }
            return opt.toString();
          }).join(', ');
          buffer.writeln('     └─ 选配规格: [$optStrs]');
        }
      }
    }

    // 5. 备注与尾部
    if (order.note != null && order.note!.isNotEmpty) {
      buffer.writeln('\n【订单整单备注】');
      buffer.writeln('  • Note: ${order.note}');
    }

    buffer.writeln('================================================----------------------\n');

    print(buffer.toString());
  }

  static String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  static String _getOrderStatusLabel(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'PENDING (待处理/待付)';
      case OrderStatus.confirmed:
        return 'CONFIRMED (已确认/待出餐)';
      case OrderStatus.completed:
        return 'COMPLETED (已完成)';
      case OrderStatus.cancelled:
        return 'CANCELLED (已取消)';
    }
  }

  static String _getSyncStatusLabel(SyncStatus status) {
    switch (status) {
      case SyncStatus.pending:
        return 'PENDING (待同步)';
      case SyncStatus.synced:
        return 'SYNCED (已同步到服务器)';
      case SyncStatus.syncFailed:
        return 'SYNC_FAILED (同步失败)';
      case SyncStatus.skipped:
        return 'SKIPPED (已跳过同步)';
    }
  }

  static String _getPrintStatusLabel(PrintStatus status) {
    switch (status) {
      case PrintStatus.pending:
        return 'PENDING (待打印)';
      case PrintStatus.printed:
        return 'PRINTED (已打印)';
      case PrintStatus.printFailed:
        return 'PRINT_FAILED (打印失败)';
      case PrintStatus.skipped:
        return 'SKIPPED (跳过打印)';
    }
  }
}
