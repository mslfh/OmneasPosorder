import 'dart:convert';
import 'package:flutter/material.dart';
import '../../common/models/order_model.dart';
import '../../common/models/server_order_model.dart';
import '../../common/services/order_service.dart';
import 'order_detail_page.dart';
import 'server_order_detail_page.dart';

// 本地订单筛选
enum OrderChannelFilter { all, local, online, pendingSync, pendingPrint }

// 服务器订单来源筛选
enum ServerPlaceFilter { all, online, terminal }

// 服务器订单状态筛选
enum ServerStatusFilter { all, pending, completed, cancelled }

class OrderListPage extends StatefulWidget {
  @override
  _OrderListPageState createState() => _OrderListPageState();
}

class _OrderListPageState extends State<OrderListPage> {
  final OrderService _orderService = OrderService();
  final TextEditingController _searchController = TextEditingController();
  List<OrderModel> _orders = [];
  List<ServerOrderModel> _serverOrders = [];
  Map<String, int> _stats = {};
  bool _isLoading = false;
  bool _showServerOrders = false; // 切换标志
  DateTime _selectedDate = DateTime.now();
  int _currentPage = 0;
  final int _pageSize = 20;
  OrderChannelFilter _orderChannelFilter = OrderChannelFilter.all;
  ServerPlaceFilter _serverPlaceFilter = ServerPlaceFilter.all;
  ServerStatusFilter _serverStatusFilter = ServerStatusFilter.all;

  String get _searchQuery => _searchController.text.trim().toLowerCase();

  String _normalizeSearchText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  bool _isOrderedSubsequence(String query, String target) {
    if (query.isEmpty) return true;
    if (target.isEmpty) return false;

    int qIndex = 0;
    for (int i = 0; i < target.length && qIndex < query.length; i++) {
      if (target[i] == query[qIndex]) {
        qIndex++;
      }
    }
    return qIndex == query.length;
  }

  bool _containsQuery(String? value) {
    if (_searchQuery.isEmpty) return true;
    final query = _normalizeSearchText(_searchQuery);
    final target = _normalizeSearchText(value ?? '');
    return _isOrderedSubsequence(query, target);
  }

  String _localItemSearchText(OrderModel order) {
    try {
      final decoded = jsonDecode(order.items);
      if (decoded is List) {
        return decoded
            .map((item) {
              if (item is Map) {
                final name = item['name'] ??
                    item['product_title'] ??
                    item['product_name'] ??
                    '';
                final note = item['note'] ?? '';
                return '$name $note';
              }
              return item.toString();
            })
            .join(' ')
            .toLowerCase();
      }
    } catch (_) {}
    return '';
  }

  String _serverItemSearchText(ServerOrderModel order) {
    return order.items
        .map((item) {
          if (item is Map) {
            final name = item['product_title'] ??
                item['name'] ??
                item['product_name'] ??
                '';
            final note = item['note'] ?? '';
            return '$name $note';
          }
          return item.toString();
        })
        .join(' ')
        .toLowerCase();
  }

  String _serverCustomerSearchText(ServerOrderModel order) {
    return order.additions
        .map((item) {
          if (item is Map) {
            final name = item['customer_name'] ?? item['name'] ?? '';
            final phone = item['customer_phone'] ?? item['phone'] ?? '';
            final remark = item['remark'] ?? item['note'] ?? '';
            return '$name $phone $remark';
          }
          return item.toString();
        })
        .join(' ')
        .toLowerCase();
  }

  String _localItemNamesDisplayText(OrderModel order) {
    try {
      final decoded = jsonDecode(order.items);
      if (decoded is List) {
        final names = decoded
            .map((item) {
              if (item is Map) {
                return (item['name'] ??
                        item['product_title'] ??
                        item['product_name'] ??
                        '')
                    .toString();
              }
              return '';
            })
            .where((name) => name.trim().isNotEmpty)
            .toList();

        if (names.isNotEmpty) {
          return names.join(', ');
        }
      }
    } catch (_) {}
    return '-';
  }

  bool _matchesLocalOrder(OrderModel order) {
    if (_searchQuery.isEmpty) return true;
    final itemText = _localItemSearchText(order);
    return _containsQuery(order.orderNo) ||
        _containsQuery(itemText) ||
        _containsQuery(order.note) ||
        _containsQuery(order.remoteOrderNumber);
  }

  bool _matchesServerOrder(ServerOrderModel order) {
    if (_searchQuery.isEmpty) return true;
    final itemText = _serverItemSearchText(order);
    final customerText = _serverCustomerSearchText(order);
    return _containsQuery(order.orderNo) ||
        _containsQuery(order.orderNumber) ||
        _containsQuery(itemText) ||
        _containsQuery(customerText) ||
        _containsQuery(order.note) ||
        _containsQuery(order.remark);
  }

  List<OrderModel> get _filteredOrders {
    switch (_orderChannelFilter) {
      case OrderChannelFilter.local:
        return _orders
            .where((o) => !o.isOnlineOrder && _matchesLocalOrder(o))
            .toList();
      case OrderChannelFilter.online:
        return _orders
            .where((o) => o.isOnlineOrder && _matchesLocalOrder(o))
            .toList();
      case OrderChannelFilter.pendingSync:
        return _orders
            .where((o) =>
                o.syncStatus != SyncStatus.synced &&
                o.syncStatus != SyncStatus.skipped &&
                _matchesLocalOrder(o))
            .toList();
      case OrderChannelFilter.pendingPrint:
        return _orders
            .where((o) =>
                o.printStatus != PrintStatus.printed && _matchesLocalOrder(o))
            .toList();
      case OrderChannelFilter.all:
      default:
        return _orders.where(_matchesLocalOrder).toList();
    }
  }

  List<ServerOrderModel> get _filteredServerOrders {
    return _serverOrders.where((o) {
      if (!_matchesServerOrder(o)) return false;
      bool placeMatch = true;
      if (_serverPlaceFilter == ServerPlaceFilter.online) {
        placeMatch = o.placeIn == 'online';
      } else if (_serverPlaceFilter == ServerPlaceFilter.terminal) {
        placeMatch = o.placeIn == 'terminal';
      }

      bool statusMatch = true;
      if (_serverStatusFilter == ServerStatusFilter.pending) {
        statusMatch = o.status == 'pending';
      } else if (_serverStatusFilter == ServerStatusFilter.completed) {
        statusMatch = o.status == 'completed';
      } else if (_serverStatusFilter == ServerStatusFilter.cancelled) {
        statusMatch = o.status == 'cancelled';
      }

      return placeMatch && statusMatch;
    }).toList();
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
        List<OrderModel> orders;
        if (_orderChannelFilter == OrderChannelFilter.pendingSync) {
          orders = await _orderService.getPendingSyncOrders();
        } else if (_orderChannelFilter == OrderChannelFilter.pendingPrint) {
          orders = await _orderService.getPendingPrintOrders();
        } else {
          orders = await _orderService.getOrders(
            limit: _pageSize,
            offset: _currentPage * _pageSize,
            date: _selectedDate,
          );
        }

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

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
  }

  Future<void> _retryOrder(OrderModel order) async {
    try {
      if (order.syncStatus != SyncStatus.synced &&
          order.syncStatus != SyncStatus.skipped) {
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
            icon: Icon(_showServerOrders ? Icons.cloud_off : Icons.cloud),
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
          final searchBar = Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索订单号 / 商品名 / 顾客名',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          );

          if (_showServerOrders) {
            return Column(
              children: [
                searchBar,
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text('Source: ',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      _buildServerPlaceFilterChip('All', ServerPlaceFilter.all),
                      SizedBox(width: 8),
                      _buildServerPlaceFilterChip(
                          'Online', ServerPlaceFilter.online),
                      SizedBox(width: 8),
                      _buildServerPlaceFilterChip(
                          'Terminal', ServerPlaceFilter.terminal),
                    ],
                  ),
                ),
                SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text('Status: ',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      _buildServerStatusFilterChip(
                          'All', ServerStatusFilter.all),
                      SizedBox(width: 8),
                      _buildServerStatusFilterChip(
                          'Pending', ServerStatusFilter.pending),
                      SizedBox(width: 8),
                      _buildServerStatusFilterChip(
                          'Completed', ServerStatusFilter.completed),
                      SizedBox(width: 8),
                      _buildServerStatusFilterChip(
                          'Cancelled', ServerStatusFilter.cancelled),
                    ],
                  ),
                ),
              ],
            );
          }

          final chips = [
            _buildFilterChip('All', OrderChannelFilter.all),
            _buildFilterChip('Local', OrderChannelFilter.local),
            _buildFilterChip('Online', OrderChannelFilter.online),
            if (_orderChannelFilter == OrderChannelFilter.pendingSync)
              _buildFilterChip('Pending Sync', OrderChannelFilter.pendingSync),
            if (_orderChannelFilter == OrderChannelFilter.pendingPrint)
              _buildFilterChip(
                  'Pending Print', OrderChannelFilter.pendingPrint),
          ];

          if (constraints.maxWidth < 320) {
            return Column(
              children: [
                searchBar,
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: chips,
                ),
              ],
            );
          }

          return Column(
            children: [
              searchBar,
              Container(
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
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildServerPlaceFilterChip(String label, ServerPlaceFilter value) {
    final selected = _serverPlaceFilter == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() => _serverPlaceFilter = value),
    );
  }

  Widget _buildServerStatusFilterChip(String label, ServerStatusFilter value) {
    final selected = _serverStatusFilter == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() => _serverStatusFilter = value),
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
              onTap: () {
                setState(() => _orderChannelFilter = OrderChannelFilter.all);
                _refreshData();
              },
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Pending Sync',
              _stats['pendingSyncCount']?.toString() ?? '0',
              Colors.orange,
              Icons.sync_problem,
              onTap: () {
                setState(
                    () => _orderChannelFilter = OrderChannelFilter.pendingSync);
                _refreshData();
              },
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Pending Print',
              _stats['pendingPrintCount']?.toString() ?? '0',
              Colors.red,
              Icons.print_disabled,
              onTap: () {
                setState(() =>
                    _orderChannelFilter = OrderChannelFilter.pendingPrint);
                _refreshData();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 0,
        color: color.withOpacity(0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: color.withOpacity(0.18), width: onTap != null ? 1.5 : 1.0),
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
    final filtered = _filteredServerOrders;
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final order = filtered[index];
        return _buildServerOrderCard(order);
      },
    );
  }

  Widget _buildOrderCard(OrderModel order) {
    final hasError = (order.syncStatus != SyncStatus.synced &&
            order.syncStatus != SyncStatus.skipped) ||
        order.printStatus != PrintStatus.printed;
    final itemNames = _localItemNamesDisplayText(order);

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
                  _getSyncStatusText(order.syncStatus),
                  _getSyncStatusColor(order.syncStatus),
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
            ? SizedBox(
                width: 170,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        itemNames,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh, color: Colors.orange),
                      onPressed: () => _retryOrder(order),
                    ),
                  ],
                ),
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
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ServerOrderDetailPage(order: order),
            ),
          );
        },
        leading: CircleAvatar(
          backgroundColor: hasError ? Colors.red : Colors.green,
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
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: order.placeIn == 'online'
                    ? Colors.purple[50]
                    : Colors.blue[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                order.placeIn.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  color:
                      order.placeIn == 'online' ? Colors.purple : Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Amount: \$${order.finalAmount} | ${order.type.toUpperCase()}'),
            if (order.items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  order.items.map((item) => item['product_title']).join(', '),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            SizedBox(height: 4),
            Row(
              children: [
                _buildStatusChip(
                  order.status.toUpperCase(),
                  order.status == 'completed'
                      ? Colors.green
                      : (order.status == 'cancelled'
                          ? Colors.red
                          : Colors.orange),
                ),
                SizedBox(width: 8),
                _buildStatusChip("Sync ${order.syncStatus}", Colors.orange),
                SizedBox(width: 8),
                _buildStatusChip("Print ${order.printStatus}", Colors.blue),
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
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color _getOrderStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.grey;
      case OrderStatus.confirmed:
        return Colors.blue;
      case OrderStatus.completed:
        return Colors.green;
      case OrderStatus.cancelled:
        return Colors.red;
    }
  }

  String _getSyncStatusText(SyncStatus status) {
    switch (status) {
      case SyncStatus.pending:
        return 'Sync Pending';
      case SyncStatus.synced:
        return 'Synced';
      case SyncStatus.syncFailed:
        return 'Sync Failed';
      case SyncStatus.skipped:
        return 'Skipped';
    }
  }

  Color _getSyncStatusColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.pending:
        return Colors.orange;
      case SyncStatus.synced:
        return Colors.green;
      case SyncStatus.syncFailed:
        return Colors.red;
      case SyncStatus.skipped:
        return Colors.grey;
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
