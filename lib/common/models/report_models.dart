// 报告相关的数据模型

class OrderStats {
  final double totalRevenue;
  final double cashRevenue;
  final double posRevenue;
  final double voucherRevenue;
  final double totalDiscount;
  final int totalOrders;
  final int completedOrders;
  final int cancelledOrders;
  final int dineInOrders;
  final double dineInRevenue;
  final int takeawayOrders;
  final double takeawayRevenue;
  final double averageOrderValue;
  final List<TopSellingItem> topSellingItems;

  OrderStats({
    required this.totalRevenue,
    required this.cashRevenue,
    required this.posRevenue,
    this.voucherRevenue = 0.0,
    this.totalDiscount = 0.0,
    required this.totalOrders,
    required this.completedOrders,
    required this.cancelledOrders,
    this.dineInOrders = 0,
    this.dineInRevenue = 0.0,
    this.takeawayOrders = 0,
    this.takeawayRevenue = 0.0,
    required this.averageOrderValue,
    required this.topSellingItems,
  });
}

class TopSellingItem {
  final String name;
  final int quantity;

  TopSellingItem({
    required this.name,
    required this.quantity,
  });
}

/// 日终结算/日结单数据模型 (Z-Report / Daily Settlement)
class DailySettlementModel {
  final String settlementId; // 日结单编号 e.g. "Z-20261026"
  final DateTime date; // 日结自然日
  final DateTime createdAt; // 操作日结时间
  final double totalRevenue; // 销售总额 (实收总额)
  final double cashRevenue; // 现金总额
  final double posRevenue; // POS刷卡总额
  final double voucherRevenue; // 优惠券/代金券金额
  final double totalDiscount; // 优惠折扣总额
  final int totalOrders; // 总订单笔数
  final int completedOrders; // 完成订单笔数
  final int cancelledOrders; // 取消/退款订单笔数
  final int dineInOrders; // 堂食笔数
  final double dineInRevenue; // 堂食金额
  final int takeawayOrders; // 外带/外卖笔数
  final double takeawayRevenue; // 外带/外卖金额
  final double averageOrderValue; // 客单价

  DailySettlementModel({
    required this.settlementId,
    required this.date,
    required this.createdAt,
    required this.totalRevenue,
    required this.cashRevenue,
    required this.posRevenue,
    this.voucherRevenue = 0.0,
    this.totalDiscount = 0.0,
    required this.totalOrders,
    required this.completedOrders,
    required this.cancelledOrders,
    this.dineInOrders = 0,
    this.dineInRevenue = 0.0,
    this.takeawayOrders = 0,
    this.takeawayRevenue = 0.0,
    required this.averageOrderValue,
  });

  Map<String, dynamic> toJson() {
    return {
      'settlement_id': settlementId,
      'date':
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'created_at': createdAt.toIso8601String(),
      'total_revenue': totalRevenue,
      'cash_revenue': cashRevenue,
      'pos_revenue': posRevenue,
      'voucher_revenue': voucherRevenue,
      'total_discount': totalDiscount,
      'total_orders': totalOrders,
      'completed_orders': completedOrders,
      'cancelled_orders': cancelledOrders,
      'dine_in_orders': dineInOrders,
      'dine_in_revenue': dineInRevenue,
      'takeaway_orders': takeawayOrders,
      'takeaway_revenue': takeawayRevenue,
      'average_order_value': averageOrderValue,
    };
  }
}
