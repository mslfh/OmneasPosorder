import 'package:flutter/material.dart';
import '../../common/models/order_model.dart';
import '../../common/models/server_order_model.dart';
import '../../common/services/order_service.dart';
import 'order_detail_page.dart';

// 本地订单筛选
enum OrderChannelFilter { all, local, online }

class OrderListPage extends StatefulWidget {
  @override
  _OrderListPageState createState() => _OrderListPageState();
}

class _OrderListPageState extends State<OrderListPage> {
  final OrderService _orderService = OrderService();
  List<OrderModel> _orders = [];
  List<ServerOrderModel> _serverOrders = [];
  Map<String, int> _stats = {};
  bool _isLoading = false;
  bool _showServerOrders = false; // 切换标志
  DateTime _selectedDate = DateTime.now();
  int _currentPage = 0;
  final int _pageSize = 20;
  OrderChannelFilter _orderChannelFilter = OrderChannelFilter.all;

  List<OrderModel> get _filteredOrders {
    switch (_orderChannelFilter) {
      case OrderChannelFilter.local:
        return _orders.where((o) => !o.isOnlineOrder).toList();
      case OrderChannelFilter.online:
        return _orders.where((o) => o.isOnlineOrder).toList();
      case OrderChannelFilter.all:
      default:
        return _orders;
    }
  }

  @override
  void initState() {
    super.initState();
    // 默认显示当天订单
    _selectedDate =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      if (_showServerOrders) {
        // 加载服务器订单
        final serverOrders =
            await _orderService.getServerOrders(date: _selectedDate);
        setState(() {
          _serverOrders = serverOrders;
          _isLoading = false;
        });
      } else {
        // 加载本地订单
        final orders = await _orderService.getOrders(
          limit: _pageSize,
          offset: _currentPage * _pageSize,
          date: _selectedDate,
        );
        final stats = await _orderService.getOrderStats(date: _selectedDate);

        setState(() {
          _orders = orders;
          _stats = stats;
          _isLoading = false;
        });
      }
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

  /// 拉取服务器订单到本地
  Future<void> _pullServerOrder(ServerOrderModel serverOrder) async {
    try {
      _showLoadingDialog('Pulling order...');
      await _orderService.pullServerOrderToLocal(serverOrder);
      Navigator.pop(context); // 关闭加载对话框
      _showSuccessSnackBar('Order pulled successfully');
      await Future.delayed(Duration(milliseconds: 500));
      await _refreshData();
    } catch (e) {
      Navigator.pop(context); // 关闭加载对话框
      _showErrorSnackBar('Pull failed: $e');
    }
  }

  /// 重新打印服务器订单
  Future<void> _reprintServerOrder(ServerOrderModel serverOrder) async {
    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Reprint Order'),
          content: Text('Really reprint order ${serverOrder.orderNumber}?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Reprint')),
          ],
        ),
      );

      if (confirm == true) {
        _showLoadingDialog('Printing...');
        await _orderService.reprintServerOrder(serverOrder);
        Navigator.pop(context); // 关闭加载对话框
        _showSuccessSnackBar('Print submitted');
        // 刷新列表
        await Future.delayed(Duration(milliseconds: 500));
        await _refreshData();
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showErrorSnackBar('Print failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showServerOrders ? 'Server Orders' : 'Order Management'),
        actions: [
          // 切换本地/服务器订单
          IconButton(
            icon: Icon(_showServerOrders ? Icons.cloud : Icons.cloud_off),
            tooltip:
                _showServerOrders ? 'Show Local Orders' : 'Show Server Orders',
            onPressed: () async {
              setState(() {
                _showServerOrders = !_showServerOrders;
                _currentPage = 0;
              });
              await _loadData();
            },
          ),

          // 切换日期（日历）
          IconButton(
            icon: Icon(Icons.calendar_today),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );

              if (picked != null) {
                setState(() => _selectedDate =
                    DateTime(picked.year, picked.month, picked.day));
                await _refreshData();
              }
            },
          ),

          // 清空选定日期订单（测试用） - 仅本地订单显示
          if (!_showServerOrders)
            IconButton(
              icon: Icon(Icons.delete_outline),
              tooltip: 'Clear orders for selected date (test)',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Confirm delete'),
                    content: Text(
                        'Delete all orders for ${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text('Delete')),
                    ],
                  ),
                );

                if (confirm == true) {
                  try {
                    await _orderService.clearOrdersByDate(_selectedDate);
                    _showSuccessSnackBar('Orders cleared');
                    await _refreshData();
                  } catch (e) {
                    _showErrorSnackBar('Clear failed: $e');
                  }
                }
              },
            ),

          // 清空全部订单（测试用） - 仅本地订单显示
          if (!_showServerOrders)
            IconButton(
              icon: Icon(Icons.delete_sweep),
              tooltip: 'Clear ALL orders (test)',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Confirm delete all'),
                    content: Text(
                        'Delete ALL orders in local database? This action cannot be undone.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text('Delete All')),
                    ],
                  ),
                );

                if (confirm == true) {
                  try {
                    await _orderService.clearAllOrders();
                    _showSuccessSnackBar('All orders cleared');
                    await _refreshData();
                  } catch (e) {
                    _showErrorSnackBar('Clear all failed: $e');
                  }
                }
              },
            ),

          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _refreshData,
          ),

          if (!_showServerOrders)
            IconButton(
              icon: Icon(Icons.replay),
              onPressed: _retryAllFailed,
            ),
        ],
      ),
      body: Column(
        children: [
          // 统计卡片 - 仅本地订单显示
          if (!_showServerOrders) _buildStatsCards(),

          // 本地订单筛选按钮
          if (!_showServerOrders) _buildOrderFilterBar(),

          // 订单列表
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _refreshData,
                    child: _showServerOrders
                        ? (_serverOrders.isEmpty
                            ? _buildEmptyState()
                            : _buildServerOrderList())
                        : (_filteredOrders.isEmpty
                            ? _buildEmptyState()
                            : _buildOrderList()),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chips = [
            _buildFilterChip('All', OrderChannelFilter.all),
            _buildFilterChip('Local', OrderChannelFilter.local),
            _buildFilterChip('Online', OrderChannelFilter.online),
          ];

          if (constraints.maxWidth < 320) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips,
            );
          }

          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.start,
                    children: chips,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String label, OrderChannelFilter value) {
    final selected = _orderChannelFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 14),
      side: BorderSide(
        color: selected ? Colors.green.withOpacity(0.3) : Colors.grey[300]!,
      ),
      selectedColor: Colors.green.withOpacity(0.24),
      backgroundColor: Colors.white,
      onSelected: (_) {
        if (!selected) {
          setState(() => _orderChannelFilter = value);
        }
      },
    );
  }

  Widget _buildStatsCards() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Orders (${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')})',
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

  Widget _buildStatCard(
      String title, String value, Color color, IconData icon) {
    return Card(
      elevation: 0,
      color: color.withOpacity(0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderList() {
    final filteredOrders = _filteredOrders;
     return ListView.builder(
      itemCount: filteredOrders.length,
       itemBuilder: (context, index) {
        final order = filteredOrders[index];
         return _buildOrderCard(order);
       },
     );
   }

  Widget _buildServerOrderList() {
    return ListView.builder(
      itemCount: _serverOrders.length,
      itemBuilder: (context, index) {
        final order = _serverOrders[index];
        return _buildServerOrderCard(order);
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
              'Order ${order.orderNo.substring(0, 4)}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (order.isOnlineOrder) ...[
              SizedBox(width: 8),
              Chip(
                label: Text('Online',
                    style: TextStyle(fontSize: 9, color: Colors.blueAccent)),
                backgroundColor: Colors.transparent,
                side: BorderSide(color: Colors.blueAccent, width: 1),
                padding: EdgeInsets.symmetric(horizontal: 1, vertical: 0),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount: ￥${order.totalAmount.toStringAsFixed(2)}'),
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

  Widget _buildServerOrderCard(ServerOrderModel order) {
    final syncStatus = order.getSyncStatus();
    final printStatus = order.getPrintStatus();
    final hasError = syncStatus != ServerSyncStatus.synced ||
        printStatus != ServerPrintStatus.printed;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: hasError ? Colors.orange : Colors.green,
          child: Icon(
            hasError ? Icons.cloud_off : Icons.cloud,
            color: Colors.white,
          ),
        ),
        title: Row(
          children: [
            Text(
              'Order ${order.orderNo}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(width: 8),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount: ￥${order.finalAmount}'),
            Text('Time: ${_formatTime(order.orderTime ?? DateTime.now())}'),
            Row(
              children: [
                _buildStatusChip(
                 "Sync ${order.syncStatus}",
                    Colors.orange
                ),
                SizedBox(width: 8),
                _buildStatusChip(
                    "Print ${order.printStatus}",
                    Colors.blue
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.download, size: 16),
                    label: Text('Pull', style: TextStyle(fontSize: 12)),
                    onPressed: () => _pullServerOrder(order),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.print, size: 16),
                    label: Text('Reprint', style: TextStyle(fontSize: 12)),
                    onPressed: () => _reprintServerOrder(order),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      backgroundColor: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text(message),
          ],
        ),
      ),
    );
  }

  String _getServerSyncStatusText(ServerSyncStatus status) {
    switch (status) {
      case ServerSyncStatus.pending:
        return 'Sync Pending';
      case ServerSyncStatus.synced:
        return 'Synced';
      case ServerSyncStatus.failed:
        return 'Sync Failed';
    }
  }

  Color _getServerSyncStatusColor(ServerSyncStatus status) {
    switch (status) {
      case ServerSyncStatus.pending:
        return Colors.orange;
      case ServerSyncStatus.synced:
        return Colors.green;
      case ServerSyncStatus.failed:
        return Colors.red;
    }
  }

  String _getServerPrintStatusText(ServerPrintStatus status) {
    switch (status) {
      case ServerPrintStatus.pending:
        return 'Print Pending';
      case ServerPrintStatus.printed:
        return 'Printed';
      case ServerPrintStatus.failed:
        return 'Print Failed';
    }
  }

  Color _getServerPrintStatusColor(ServerPrintStatus status) {
    switch (status) {
      case ServerPrintStatus.pending:
        return Colors.orange;
      case ServerPrintStatus.printed:
        return Colors.green;
      case ServerPrintStatus.failed:
        return Colors.red;
    }
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
    return '${time.month.toString().padLeft(2, '0')}-${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
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
      case PrintStatus.skipped:
        return 'Skipped';
      default:
        return 'Unknown';
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
      case PrintStatus.skipped:
        return Colors.orange;
      default:
        return Colors.grey;
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
