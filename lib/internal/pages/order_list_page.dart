import 'package:flutter/material.dart';
import '../../common/models/order_model.dart';
import '../../common/services/order_service.dart';
import 'order_detail_page.dart';

class OrderListPage extends StatefulWidget {
  @override
  _OrderListPageState createState() => _OrderListPageState();
}

class _OrderListPageState extends State<OrderListPage> {
  final OrderService _orderService = OrderService();
  List<OrderModel> _orders = [];
  Map<String, int> _stats = {};
  bool _isLoading = false;
  int _currentPage = 0;
  final int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final orders = await _orderService.getOrders(
        limit: _pageSize,
        offset: _currentPage * _pageSize
      );
      final stats = await _orderService.getOrderStats();

      setState(() {
        _orders = orders;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Failed to load orders: $e');
    }
  }

  Future<void> _refreshData() async {
    _currentPage = 0;
    await _loadData();
  }

  Future<void> _retryOrder(OrderModel order) async {
    try {
      if (order.orderStatus != OrderStatus.synced) {
        await _orderService.retrySyncOrder(order.id);
        _showSuccessSnackBar('Sync retry submitted');
      }

      if (order.printStatus != PrintStatus.printed) {
        await _orderService.retryPrintOrder(order.id);
        _showSuccessSnackBar('Print retry submitted');
      }

      await _refreshData();
    } catch (e) {
      _showErrorSnackBar('Retry failed: $e');
    }
  }

  Future<void> _retryAllFailed() async {
    try {
      await _orderService.retryAllPendingSyncOrders();
      await _orderService.retryAllPendingPrintOrders();
      _showSuccessSnackBar('Batch retry started');
      await _refreshData();
    } catch (e) {
      _showErrorSnackBar('Batch retry failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Order Management'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _refreshData,
          ),
          IconButton(
            icon: Icon(Icons.replay),
            onPressed: _retryAllFailed,
          ),
        ],
      ),
      body: Column(
        children: [
          // 统计卡片
          _buildStatsCards(),

          // 订单列表
          Expanded(
            child: _isLoading
              ? Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _refreshData,
                  child: _orders.isEmpty
                    ? _buildEmptyState()
                    : _buildOrderList(),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Today\'s Orders',
              _stats['todayCount']?.toString() ?? '0',
              Colors.blue,
              Icons.receipt,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Pending Sync',
              _stats['pendingSyncCount']?.toString() ?? '0',
              Colors.orange,
              Icons.sync_problem,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Pending Print',
              _stats['pendingPrintCount']?.toString() ?? '0',
              Colors.red,
              Icons.print_disabled,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderList() {
    return ListView.builder(
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        final order = _orders[index];
        return _buildOrderCard(order);
      },
    );
  }

  Widget _buildOrderCard(OrderModel order) {
    final hasError = order.orderStatus != OrderStatus.synced ||
                     order.printStatus != PrintStatus.printed;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: hasError ? Colors.red : Colors.green,
          child: Icon(
            hasError ? Icons.error : Icons.check,
            color: Colors.white,
          ),
        ),
        title: Row(
          children: [
            Text(
              'Order ${order.id.substring(0, 8)}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (order.isOnlineOrder) ...[
              SizedBox(width: 8),
              Chip(
                label: Text('Online Order', style: TextStyle(fontSize: 10, color: Colors.blueAccent)),
                backgroundColor: Colors.transparent,
                side: BorderSide(color: Colors.blueAccent, width: 1),
                padding: EdgeInsets.symmetric(horizontal:4, vertical: 0),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount: ¥${order.totalAmount.toStringAsFixed(2)}'),
            Text('Time: ${_formatTime(order.orderTime)}'),
            Row(
              children: [
                _buildStatusChip(
                  _getOrderStatusText(order.orderStatus),
                  _getOrderStatusColor(order.orderStatus),
                ),
                SizedBox(width: 8),
                _buildStatusChip(
                  _getPrintStatusText(order.printStatus),
                  _getPrintStatusColor(order.printStatus),
                ),
              ],
            ),
            if (order.errorMessage != null) ...[
              SizedBox(height: 4),
              Text(
                'Error: ${order.errorMessage}',
                style: TextStyle(color: Colors.red, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: hasError
          ? IconButton(
              icon: Icon(Icons.refresh, color: Colors.orange),
              onPressed: () => _retryOrder(order),
            )
          : null,
        onTap: () => _navigateToOrderDetail(order),
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No Orders',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'Orders will appear here after placing',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  void _navigateToOrderDetail(OrderModel order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderDetailPage(orderId: order.id),
      ),
    ).then((_) => _refreshData());
  }

  String _formatTime(DateTime time) {
    return '${time.month}-${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _getOrderStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.pendingSync:
        return 'Syncing';
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

  Color _getOrderStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.grey;
      case OrderStatus.pendingSync:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.blue;
      case OrderStatus.completed:
        return Colors.green;
      case OrderStatus.cancelled:
        return Colors.red;
      case OrderStatus.synced:
        return Colors.green[700]!;
    }
  }

  String _getPrintStatusText(PrintStatus status) {
    switch (status) {
      case PrintStatus.pending:
        return 'Print Pending';
      case PrintStatus.printed:
        return 'Printed';
      case PrintStatus.printFailed:
        return 'Print Failed';
    }
  }

  Color _getPrintStatusColor(PrintStatus status) {
    switch (status) {
      case PrintStatus.pending:
        return Colors.grey;
      case PrintStatus.printed:
        return Colors.green;
      case PrintStatus.printFailed:
        return Colors.red;
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}
