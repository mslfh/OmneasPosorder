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
