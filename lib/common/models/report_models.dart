// 报告相关的数据模型

class OrderStats {
  final double totalRevenue;
  final double cashRevenue;
  final double posRevenue;
  final int totalOrders;
  final int completedOrders;
  final int cancelledOrders;
  final double averageOrderValue;
  final List<TopSellingItem> topSellingItems;

  OrderStats({
    required this.totalRevenue,
    required this.cashRevenue,
    required this.posRevenue,
    required this.totalOrders,
    required this.completedOrders,
    required this.cancelledOrders,
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
