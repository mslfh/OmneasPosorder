import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../common/services/database_service.dart';
import '../../common/services/print_service.dart';
import '../../common/models/order_model.dart';
import '../../common/models/report_models.dart';

class ReportPage extends StatefulWidget {
  @override
  _ReportPageState createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final DatabaseService _databaseService = DatabaseService();
  final PrintService _printService = PrintService();

  // 默认显示今天的数据
  DateTime _startDate = DateTime.now().copyWith(hour: 0, minute: 0, second: 0, microsecond: 0);
  DateTime _endDate = DateTime.now().copyWith(hour: 23, minute: 59, second: 59, microsecond: 999);

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
      final orders = await _databaseService.getOrdersByDateRange(_startDate, _endDate);
      print('Found ${orders.length} orders for date range: ${_startDate} to ${_endDate}');

      // 调试：打印订单信息
      for (final order in orders) {
        print('Order ${order.id}: ${order.totalAmount}, Cash: ${order.cashAmount}, POS: ${order.posAmount}, Status: ${order.orderStatus}');
      }

      final stats = _calculateStats(orders);

      setState(() {
        _orders = orders;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load data: $e')),
      );
      print('Error loading report data: $e');
    }
  }

  OrderStats _calculateStats(List<OrderModel> orders) {
    double totalRevenue = 0;
    double cashRevenue = 0;
    double posRevenue = 0;
    int totalOrders = orders.length;
    int completedOrders = 0;
    int cancelledOrders = 0;
    Map<String, int> itemCounts = {};

    for (final order in orders) {
      totalRevenue += order.totalAmount;

      // 如果cash_amount和pos_amount都为0，则假设全部为现金支付
      if (order.cashAmount == 0 && order.posAmount == 0) {
        cashRevenue += order.totalAmount;
      } else {
        cashRevenue += order.cashAmount;
        posRevenue += order.posAmount;
      }

      switch (order.orderStatus) {
        case OrderStatus.completed:
        case OrderStatus.synced:
          completedOrders++;
          break;
        case OrderStatus.cancelled:
          cancelledOrders++;
          break;
        default:
          break;
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
        print('Error parsing items for order ${order.id}: $e');
      }
    }

    print('Stats calculated - Total: $totalRevenue, Cash: $cashRevenue, POS: $posRevenue, Orders: $totalOrders, Completed: $completedOrders');

    return OrderStats(
      totalRevenue: totalRevenue,
      cashRevenue: cashRevenue,
      posRevenue: posRevenue,
      totalOrders: totalOrders,
      completedOrders: completedOrders,
      cancelledOrders: cancelledOrders,
      averageOrderValue: totalOrders > 0 ? totalRevenue / totalOrders : 0,
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
        _endDate = picked.end;
      });
      _loadReportData();
    }
  }

  Future<void> _printReport() async {
    if (_stats == null) return;

    try {
      await _printService.printReport(_stats!, _startDate, _endDate);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('统计报告已发送到打印机')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打印失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Daily Sales Report'),
        actions: [
          IconButton(
            icon: Icon(Icons.date_range),
            onPressed: _selectDateRange,
            tooltip: 'Select Date Range',
          ),
          IconButton(
            icon: Icon(Icons.print),
            onPressed: _stats != null ? _printReport : null,
            tooltip: 'Print Report',
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadReportData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _stats == null
              ? Center(child: Text('No Data Available'))
              : SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDateRangeCard(),
                      SizedBox(height: 16),
                      _buildStatsOverview(),
                      SizedBox(height: 16),
                      _buildPaymentBreakdown(),
                      SizedBox(height: 16),
                      _buildTopSellingItems(),
                      SizedBox(height: 16),
                      _buildRecentOrders(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildDateRangeCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: Colors.blue),
            SizedBox(width: 8),
            Text(
              'Report Period: ${DateFormat('yyyy-MM-dd').format(_startDate)} to ${DateFormat('yyyy-MM-dd').format(_endDate)}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            Spacer(),
            TextButton(
              onPressed: _selectDateRange,
              child: Text('Change'),
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
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sales Overview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
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
                  title: 'Total Orders',
                  value: '${stats.totalOrders}',
                  icon: Icons.receipt,
                  color: Colors.blue,
                ),
                _buildStatItem(
                  title: 'Completed Orders',
                  value: '${stats.completedOrders}',
                  icon: Icons.check_circle,
                  color: Colors.orange,
                ),
                _buildStatItem(
                  title: 'Average Order',
                  value: '\$${stats.averageOrderValue.toStringAsFixed(2)}',
                  icon: Icons.trending_up,
                  color: Colors.purple,
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
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment Breakdown',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    title: 'Cash Sales',
                    value: '\$${stats.cashRevenue.toStringAsFixed(2)}',
                    icon: Icons.payments,
                    color: Colors.green[600]!,
                  ),
                ),
                SizedBox(width: 16),
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
              Text('No data available')
            else
              ...stats.topSellingItems.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getRankColor(index),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(item.name),
                  trailing: Text(
                    '${item.quantity} pcs',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                );
              }).toList(),
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
                    subtitle: Text(DateFormat('yyyy-MM-dd HH:mm').format(order.orderTime)),
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
      case OrderStatus.pendingSync:
        return 'Pending Sync';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.cancelled:
        return 'Cancelled';
      case OrderStatus.synced:
        return 'Synced';
    }
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.pendingSync:
        return Colors.blue[300]!;
      case OrderStatus.confirmed:
        return Colors.blue;
      case OrderStatus.completed:
        return Colors.green;
      case OrderStatus.cancelled:
        return Colors.red;
      case OrderStatus.synced:
        return Colors.green[300]!;
    }
  }
}
