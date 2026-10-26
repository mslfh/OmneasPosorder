import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../common/services/database_service.dart';
import '../../common/services/print_service.dart';
import '../../common/services/order_service.dart';
import '../../common/services/language_service.dart';
import '../../common/models/order_model.dart';
import '../../common/models/report_models.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final DatabaseService _databaseService = DatabaseService();
  final PrintService _printService = PrintService();

  // 默认显示今天的数据
  DateTime _startDate =
      DateTime.now().copyWith(hour: 0, minute: 0, second: 0, microsecond: 0);
  DateTime _endDate = DateTime.now()
      .copyWith(hour: 23, minute: 59, second: 59, microsecond: 999);

  OrderStats? _stats;
  List<OrderModel> _orders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReportData();
  }

  Future<void> _loadReportData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final orders =
          await _databaseService.getOrdersByDateRange(_startDate, _endDate);
      final stats = _calculateStats(orders);

      if (!mounted) return;
      setState(() {
        _orders = orders;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load data: $e')),
      );
    }
  }

  OrderStats _calculateStats(List<OrderModel> orders) {
    double totalRevenue = 0;
    double cashRevenue = 0;
    double posRevenue = 0;
    double voucherRevenue = 0;
    double totalDiscount = 0;
    int totalOrders = orders.length;
    int completedOrders = 0;
    int cancelledOrders = 0;
    int dineInOrders = 0;
    double dineInRevenue = 0.0;
    int takeawayOrders = 0;
    double takeawayRevenue = 0.0;
    Map<String, int> itemCounts = {};

    for (final order in orders) {
      if (order.orderStatus == OrderStatus.cancelled) {
        cancelledOrders++;
        continue; // 已取消订单不计入总营业额与商品销售统计
      }

      completedOrders++;
      totalRevenue += order.totalAmount;
      totalDiscount += order.discountAmount;
      voucherRevenue += order.voucherAmount;

      if (order.cashAmount == 0 && order.posAmount == 0) {
        cashRevenue += order.totalAmount;
      } else {
        cashRevenue += order.cashAmount;
        posRevenue += order.posAmount;
      }

      // 订单用餐类型划分 (堂食 vs 外卖/自提)
      final typeStr = order.type?.toLowerCase() ?? '';
      bool isDineIn = typeStr.contains('dine') || typeStr.contains('table') || order.isTableOrder;
      if (isDineIn) {
        dineInOrders++;
        dineInRevenue += order.totalAmount;
      } else {
        takeawayOrders++;
        takeawayRevenue += order.totalAmount;
      }

      // 统计商品销量
      try {
        final items = order.getItemsList();
        for (final item in items) {
          final name = item['name'] as String? ?? 'Unknown Item';
          final quantity = item['quantity'] as int? ?? 1;
          itemCounts[name] = (itemCounts[name] ?? 0) + quantity;
        }
      } catch (e) {
        debugPrint('Error parsing items for order ${order.id}: $e');
      }
    }

    return OrderStats(
      totalRevenue: totalRevenue,
      cashRevenue: cashRevenue,
      posRevenue: posRevenue,
      voucherRevenue: voucherRevenue,
      totalDiscount: totalDiscount,
      totalOrders: totalOrders,
      completedOrders: completedOrders,
      cancelledOrders: cancelledOrders,
      dineInOrders: dineInOrders,
      dineInRevenue: dineInRevenue,
      takeawayOrders: takeawayOrders,
      takeawayRevenue: takeawayRevenue,
      averageOrderValue: completedOrders > 0 ? totalRevenue / completedOrders : 0,
      topSellingItems: _getTopSellingItems(itemCounts),
    );
  }

  List<TopSellingItem> _getTopSellingItems(Map<String, int> itemCounts) {
    final items = itemCounts.entries
        .map((e) => TopSellingItem(name: e.key, quantity: e.value))
        .toList();
    items.sort((a, b) => b.quantity.compareTo(a.quantity));
    return items.take(5).toList();
  }

  void _setDatePreset(String preset) {
    final now = DateTime.now();
    DateTime start;
    DateTime end = now.copyWith(hour: 23, minute: 59, second: 59, microsecond: 999);

    switch (preset) {
      case 'today':
        start = now.copyWith(hour: 0, minute: 0, second: 0, microsecond: 0);
        break;
      case 'yesterday':
        final yesterday = now.subtract(const Duration(days: 1));
        start = yesterday.copyWith(hour: 0, minute: 0, second: 0, microsecond: 0);
        end = yesterday.copyWith(hour: 23, minute: 59, second: 59, microsecond: 999);
        break;
      case 'week':
        final monday = now.subtract(Duration(days: now.weekday - 1));
        start = monday.copyWith(hour: 0, minute: 0, second: 0, microsecond: 0);
        break;
      case 'month':
        start = DateTime(now.year, now.month, 1);
        break;
      default:
        start = now.copyWith(hour: 0, minute: 0, second: 0, microsecond: 0);
    }

    setState(() {
      _startDate = start;
      _endDate = end;
    });
    _loadReportData();
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end.copyWith(hour: 23, minute: 59, second: 59, microsecond: 999);
      });
      _loadReportData();
    }
  }

  Future<void> _printReport() async {
    if (_stats == null) return;

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在发送银收与营业统计小票至打印机...'),
          duration: Duration(seconds: 1),
        ),
      );
      await _printService.printReport(_stats!, _startDate, _endDate);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('统计和银收小票已成功发送到前台打印机'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('打印失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleDailySettlement() async {
    try {
      final orderService = OrderService();
      final settlement = await orderService.generateDailySettlement(date: _startDate);

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.assignment_turned_in, color: Colors.indigo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '日终结算对账 (Z-Report) #${settlement.settlementId}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '结算日期: ${DateFormat('yyyy-MM-dd').format(settlement.date)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Divider(height: 20),
                _buildSettlementRow('销售总额 (实收)', '￥${settlement.totalRevenue.toStringAsFixed(2)}', isBold: true),
                _buildSettlementRow('现金实收', '￥${settlement.cashRevenue.toStringAsFixed(2)}'),
                _buildSettlementRow('POS 刷卡收入', '￥${settlement.posRevenue.toStringAsFixed(2)}'),
                if (settlement.voucherRevenue > 0)
                  _buildSettlementRow('代金券金额', '￥${settlement.voucherRevenue.toStringAsFixed(2)}'),
                if (settlement.totalDiscount > 0)
                  _buildSettlementRow('优惠折扣总额', '-￥${settlement.totalDiscount.toStringAsFixed(2)}'),
                const Divider(height: 16),
                _buildSettlementRow('有效完成笔数', '${settlement.completedOrders} 笔'),
                _buildSettlementRow('取消/退款笔数', '${settlement.cancelledOrders} 笔'),
                _buildSettlementRow('总订单笔数', '${settlement.totalOrders} 笔'),
                _buildSettlementRow('客单价', '￥${settlement.averageOrderValue.toStringAsFixed(2)}'),
                const Divider(height: 16),
                _buildSettlementRow('堂食笔数/金额', '${settlement.dineInOrders}笔 / ￥${settlement.dineInRevenue.toStringAsFixed(2)}'),
                _buildSettlementRow('外买/自提笔数/金额', '${settlement.takeawayOrders}笔 / ￥${settlement.takeawayRevenue.toStringAsFixed(2)}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text('cancel'.tr),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.print, size: 18),
              label: const Text('确认日结并打单'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                try {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('正在执行日终结算并发送 Z-Report 小票...'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                  await orderService.executeDailySettlement(settlement);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('日终结算成功！已打印 Z-Report 并记入日志 (单号: ${settlement.settlementId})'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('日结执行失败: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成日结数据失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildSettlementRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: isBold ? Colors.indigo[900] : Colors.grey[800])),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: isBold ? Colors.indigo[900] : Colors.black87)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('report_title'.tr),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.assignment_turned_in, size: 16),
              label: const Text('日终结算 (Z-Report)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                elevation: 2,
              ),
              onPressed: _stats != null ? _handleDailySettlement : null,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _selectDateRange,
            tooltip: 'edit'.tr,
          ),
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _stats != null ? _printReport : null,
            tooltip: 'reprint'.tr,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReportData,
            tooltip: 'reset'.tr,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _stats == null
              ? Center(child: Text('no_orders'.tr))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDateRangeCard(),
                      const SizedBox(height: 16),
                      _buildStatsOverview(),
                      const SizedBox(height: 16),
                      _buildPaymentBreakdown(),
                      const SizedBox(height: 16),
                      _buildOrderTypeBreakdown(),
                      const SizedBox(height: 16),
                      _buildTopSellingItems(),
                      const SizedBox(height: 16),
                      _buildRecentOrders(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildDateRangeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Report Period: ${DateFormat('yyyy-MM-dd').format(_startDate)} ~ ${DateFormat('yyyy-MM-dd').format(_endDate)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.edit_calendar, size: 18),
                  label: const Text('Custom'),
                  onPressed: _selectDateRange,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Today'),
                  onPressed: () => _setDatePreset('today'),
                ),
                ActionChip(
                  label: const Text('Yesterday'),
                  onPressed: () => _setDatePreset('yesterday'),
                ),
                ActionChip(
                  label: const Text('This Week'),
                  onPressed: () => _setDatePreset('week'),
                ),
                ActionChip(
                  label: const Text('This Month'),
                  onPressed: () => _setDatePreset('month'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsOverview() {
    final stats = _stats!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sales Overview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: [
                _buildStatItem(
                  title: 'Total Revenue',
                  value: '\$${stats.totalRevenue.toStringAsFixed(2)}',
                  icon: Icons.attach_money,
                  color: Colors.green,
                ),
                _buildStatItem(
                  title: 'Valid / Total Orders',
                  value: '${stats.completedOrders} / ${stats.totalOrders}',
                  icon: Icons.receipt,
                  color: Colors.blue,
                ),
                _buildStatItem(
                  title: 'Average Order',
                  value: '\$${stats.averageOrderValue.toStringAsFixed(2)}',
                  icon: Icons.trending_up,
                  color: Colors.purple,
                ),
                _buildStatItem(
                  title: 'Cancelled Orders',
                  value: '${stats.cancelledOrders}',
                  icon: Icons.cancel,
                  color: Colors.red[400]!,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentBreakdown() {
    final stats = _stats!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment & Cashier Breakdown (银收统计)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    title: 'Cash Revenue',
                    value: '\$${stats.cashRevenue.toStringAsFixed(2)}',
                    icon: Icons.payments,
                    color: Colors.green[600]!,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatItem(
                    title: 'POS Sales',
                    value: '\$${stats.posRevenue.toStringAsFixed(2)}',
                    icon: Icons.credit_card,
                    color: Colors.blue[600]!,
                  ),
                ),
              ],
            ),
            if (stats.voucherRevenue > 0 || stats.totalDiscount > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (stats.voucherRevenue > 0)
                    Expanded(
                      child: _buildStatItem(
                        title: 'Vouchers',
                        value: '\$${stats.voucherRevenue.toStringAsFixed(2)}',
                        icon: Icons.card_giftcard,
                        color: Colors.orange[700]!,
                      ),
                    ),
                  if (stats.voucherRevenue > 0 && stats.totalDiscount > 0)
                    const SizedBox(width: 16),
                  if (stats.totalDiscount > 0)
                    Expanded(
                      child: _buildStatItem(
                        title: 'Total Discount',
                        value: '-\$${stats.totalDiscount.toStringAsFixed(2)}',
                        icon: Icons.local_offer,
                        color: Colors.deepOrange,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOrderTypeBreakdown() {
    final stats = _stats!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Order Type Breakdown (用餐类型)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    title: 'Dine In (堂食)',
                    value: '${stats.dineInOrders} orders\n\$${stats.dineInRevenue.toStringAsFixed(2)}',
                    icon: Icons.restaurant,
                    color: Colors.indigo,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatItem(
                    title: 'Takeaway (外卖)',
                    value: '${stats.takeawayOrders} orders\n\$${stats.takeawayRevenue.toStringAsFixed(2)}',
                    icon: Icons.takeout_dining,
                    color: Colors.teal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSellingItems() {
    final stats = _stats!;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top Selling Items',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            if (stats.topSellingItems.isEmpty)
              const Text('No data available')
            else
              ...stats.topSellingItems.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getRankColor(index),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(item.name),
                  trailing: Text(
                    '${item.quantity} pcs',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Color _getRankColor(int index) {
    switch (index) {
      case 0:
        return Colors.amber;
      case 1:
        return Colors.grey;
      case 2:
        return Colors.brown;
      default:
        return Colors.blue;
    }
  }

  Widget _buildRecentOrders() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Orders',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            if (_orders.isEmpty)
              Text('No orders available')
            else
              ListView.separated(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: _orders.take(10).length,
                separatorBuilder: (context, index) => Divider(),
                itemBuilder: (context, index) {
                  final order = _orders[index];
                  return ListTile(
                    title: Text('Order #${order.id.substring(0, 8)}'),
                    subtitle: Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(order.orderTime)),
                    trailing: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '\$${order.totalAmount.toStringAsFixed(2)}',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _getStatusText(order.orderStatus),
                          style: TextStyle(
                            color: _getStatusColor(order.orderStatus),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.blue;
      case OrderStatus.completed:
        return Colors.green;
      case OrderStatus.cancelled:
        return Colors.red;
    }
  }
}
