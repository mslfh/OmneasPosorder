import 'dart:convert';
import 'package:flutter/material.dart';
import '../../common/models/order_model.dart';
import '../../common/models/server_order_model.dart';
import '../../common/services/order_service.dart';
import '../../common/services/database_service.dart';
import '../../common/services/order_match_service.dart';
import '../../common/services/language_service.dart';
import '../widgets/date_range_filter_bar.dart';
import 'order_detail_page.dart';

// 统一订单匹配与同步状态
enum UnifiedOrderStatus {
  normal, // 本地和服务器数据一致
  dataMismatch, // 存在对应关系，但数据不一致（如金额、菜品数、同步状态等）
  missingInLocal, // 服务器有，本地没有（重大失误，醒目显示，需拉取）
  missingInServer, // 本地有，服务器没有（未同步，提供重新同步按钮）
}

// 统一过滤类型
enum UnifiedFilter {
  all,
  normal,
  missingInLocal,
  missingInServer,
  dataMismatch,
  pendingPrint,
}

// 统一显示项模型
class UnifiedOrderItem {
  final OrderModel? localOrder;
  final ServerOrderModel? serverOrder;
  final UnifiedOrderStatus status;
  final List<String> mismatchDetails;
  final DateTime sortTime;

  UnifiedOrderItem({
    this.localOrder,
    this.serverOrder,
    required this.status,
    this.mismatchDetails = const [],
    required this.sortTime,
  });

  String get displayOrderNo {
    if (localOrder != null && localOrder!.orderNo.isNotEmpty) {
      return localOrder!.orderNo;
    }
    if (serverOrder != null && serverOrder!.orderNo.isNotEmpty) {
      return serverOrder!.orderNo;
    }
    if (serverOrder != null && serverOrder!.orderNumber.isNotEmpty) {
      return serverOrder!.orderNumber;
    }
    return localOrder?.id ?? '-';
  }

  double get displayTotalAmount {
    if (localOrder != null) {
      return localOrder!.totalAmount;
    }
    if (serverOrder != null) {
      return double.tryParse(serverOrder!.finalAmount) ?? 0.0;
    }
    return 0.0;
  }

  String get displayItemsText {
    if (localOrder != null) {
      try {
        final decoded = jsonDecode(localOrder!.items);
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
                return item.toString();
              })
              .where((n) => n.trim().isNotEmpty)
              .toList();
          if (names.isNotEmpty) return names.join(', ');
        }
      } catch (_) {}
    }
    if (serverOrder != null && serverOrder!.items.isNotEmpty) {
      return serverOrder!.items
          .map((item) {
            if (item is Map) {
              return (item['product_title'] ??
                      item['name'] ??
                      item['product_name'] ??
                      '')
                  .toString();
            }
            return item.toString();
          })
          .where((n) => n.trim().isNotEmpty)
          .join(', ');
    }
    return '-';
  }

  String get searchTargetText {
    final buffer = StringBuffer();
    if (localOrder != null) {
      buffer.write(
          '${localOrder!.orderNo} ${localOrder!.id} ${localOrder!.remoteOrderNumber ?? ''} ${localOrder!.note ?? ''} ');
    }
    if (serverOrder != null) {
      buffer.write(
          '${serverOrder!.orderNo} ${serverOrder!.orderNumber} ${serverOrder!.note ?? ''} ${serverOrder!.remark ?? ''} ');
    }
    buffer.write(displayItemsText);
    return buffer.toString().toLowerCase();
  }
}

class OrderListPage extends StatefulWidget {
  const OrderListPage({super.key});

  @override
  State<OrderListPage> createState() => _OrderListPageState();
}

class _OrderListPageState extends State<OrderListPage> {
  final OrderService _orderService = OrderService();
  final TextEditingController _searchController = TextEditingController();

  List<UnifiedOrderItem> _unifiedItems = [];
  bool _isLoading = false;

  // 日期筛选机制：支持单日、范围、ALL(不限制日期)
  bool _isAllDateMode = false;
  DateTimeRange _selectedDateRange = DateTimeRange(
    start: DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day),
    end: DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day),
  );

  int _currentPage = 0;
  final int _pageSize = 20;
  UnifiedFilter _selectedFilter = UnifiedFilter.all;

  bool get _isSingleDay {
    if (_isAllDateMode) return false;
    final start = _selectedDateRange.start;
    final end = _selectedDateRange.end;
    return start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
  }

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

  bool _containsQuery(String targetText) {
    if (_searchQuery.isEmpty) return true;
    final query = _normalizeSearchText(_searchQuery);
    final target = _normalizeSearchText(targetText);
    return _isOrderedSubsequence(query, target);
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _selectedDateRange = DateTimeRange(start: today, end: today);
    _loadData();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<String> _compareOrderData(OrderModel local, ServerOrderModel server) {
    return OrderMatchService.compareOrderData(local, server);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    DateTime? dateParam;
    DateTimeRange? dateRangeParam;

    if (!_isAllDateMode) {
      if (_isSingleDay) {
        dateParam = _selectedDateRange.start;
      } else {
        dateRangeParam = _selectedDateRange;
      }
    }

    try {
      // 1. 并行获取本地订单与服务器订单
      List<ServerOrderModel> serverOrders = [];
      try {
        serverOrders = await _orderService.getServerOrders(
          date: dateParam,
          dateRange: dateRangeParam,
        );
      } catch (e) {
        debugPrint('获取服务器订单失败: $e');
      }

      final localOrders = await _orderService.getOrders(
        limit: 1000,
        date: dateParam,
        dateRange: dateRangeParam,
      );

      // 2. 比对与合并逻辑
      final Set<String> matchedLocalIds = {};
      final List<UnifiedOrderItem> unifiedList = [];

      // 2.1 遍历服务器订单，匹配本地订单
      for (final server in serverOrders) {
        OrderModel? matchedLocal;

        for (final local in localOrders) {
          if (matchedLocalIds.contains(local.id)) continue;

          bool isMatch = false;
          // 按 remoteOrderId 匹配
          if (local.remoteOrderId != null && local.remoteOrderId == server.id) {
            isMatch = true;
          }
          // 按 remoteOrderNumber 匹配
          else if (local.remoteOrderNumber != null &&
              local.remoteOrderNumber!.isNotEmpty &&
              local.remoteOrderNumber == server.orderNumber) {
            isMatch = true;
          }
          // 同一天同 orderNo 匹配
          else if (local.orderNo.isNotEmpty &&
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
          // 兜底检查：如果在当前日期过滤范围外但本地数据库已存有该远程订单，按远程ID/编号获取
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
          // 本地和服务器均存在该订单：检查数据是否完全一致
          final mismatches = _compareOrderData(matchedLocal, server);
          if (mismatches.isEmpty) {
            unifiedList.add(UnifiedOrderItem(
              localOrder: matchedLocal,
              serverOrder: server,
              status: UnifiedOrderStatus.normal,
              mismatchDetails: [],
              sortTime: matchedLocal.orderTime,
            ));
          } else {
            unifiedList.add(UnifiedOrderItem(
              localOrder: matchedLocal,
              serverOrder: server,
              status: UnifiedOrderStatus.dataMismatch,
              mismatchDetails: mismatches,
              sortTime: matchedLocal.orderTime,
            ));
          }
        } else {
          // 服务器有，本地没有：重大失误，未拉取到本地！
          final orderTime = server.orderTime ??
              (server.createdAt != null
                  ? DateTime.tryParse(server.createdAt!) ?? DateTime.now()
                  : DateTime.now());
          unifiedList.add(UnifiedOrderItem(
            localOrder: null,
            serverOrder: server,
            status: UnifiedOrderStatus.missingInLocal,
            mismatchDetails: ['【重大提示】订单未拉取到本地数据库'],
            sortTime: orderTime,
          ));
        }
      }

      // 2.2 遍历尚未匹配的本地订单：说明本地有而服务器没有（未同步）
      for (final local in localOrders) {
        if (!matchedLocalIds.contains(local.id)) {
          unifiedList.add(UnifiedOrderItem(
            localOrder: local,
            serverOrder: null,
            status: UnifiedOrderStatus.missingInServer,
            mismatchDetails: ['订单尚未同步到服务器'],
            sortTime: local.orderTime,
          ));
        }
      }

      // 按照时间倒序排列
      unifiedList.sort((a, b) => b.sortTime.compareTo(a.sortTime));

      setState(() {
        _unifiedItems = unifiedList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('加载订单失败: $e');
    }
  }

  Future<void> _refreshData() async {
    _currentPage = 0;
    await _loadData();
  }

  String _getDateRangeDisplayText() {
    if (_isAllDateMode) {
      return '全部订单 (ALL)';
    }

    final start = _selectedDateRange.start;
    final end = _selectedDateRange.end;
    final now = DateTime.now();
    final isToday = start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;

    if (_isSingleDay) {
      final dateStr =
          '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
      return isToday ? '$dateStr (今天)' : dateStr;
    }

    return '${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')} ~ ${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
  }

  // 重新同步本地订单到服务器
  Future<void> _retryOrder(OrderModel order) async {
    final nav = Navigator.of(context);
    try {
      _showLoadingDialog('正在重新同步订单到服务器...');
      await _orderService.retrySyncOrder(order.id);
      if (!mounted) return;
      nav.pop();
      _showSuccessSnackBar('重新同步提交成功');
      await _refreshData();
    } catch (e) {
      if (!mounted) return;
      nav.pop();
      _showErrorSnackBar('重试同步失败: $e');
    }
  }

  // 拉取服务器订单落地到本地
  Future<void> _putServerOrder(ServerOrderModel serverOrder) async {
    final nav = Navigator.of(context);
    try {
      _showLoadingDialog('正在落地订单到本地数据库...');
      final localOrderId =  await _orderService.putServerOrderToLocal(serverOrder);
      if (!mounted) return;
      nav.pop();
      if (localOrderId.isNotEmpty) {
        _showSuccessSnackBar('订单已成功落盘到本地');
      }
      else{
        _showErrorSnackBar('该服务器订单已在本地落单!');
      }
      await Future.delayed(const Duration(milliseconds: 300));
      await _refreshData();
    } catch (e) {
      if (!mounted) return;
      nav.pop();
      _showErrorSnackBar('拉取订单失败: $e');
    }
  }

  // 重新打印服务器订单
  Future<void> _reprintServerOrder(ServerOrderModel serverOrder) async {
    final nav = Navigator.of(context);
    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重新打印小票'),
          content: Text('确定要重新打印订单 ${serverOrder.orderNumber} 的小票吗？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('重新打印')),
          ],
        ),
      );

      if (confirm == true) {
        _showLoadingDialog('正在发送到打印机...');
        await _orderService.reprintServerOrder(serverOrder);
        if (!mounted) return;
        nav.pop();
        _showSuccessSnackBar('打印请求已提交');
        await _refreshData();
      }
    } catch (e) {
      if (!mounted) return;
      nav.pop();
      _showErrorSnackBar('打印失败: $e');
    }
  }

  // 批量拉取服务器订单同步落盘到本地数据库
  Future<void> _pullAllServerOrders() async {
    final nav = Navigator.of(context);
    final mode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量拉取服务器订单到本地'),
        content: const Text(
          '将服务器订单同步落盘到本地数据库，确保本地与服务器订单完全匹配（可恢复因重装设备丢失的本地数据）。\n\n请选择拉取范围：',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'range'),
            child: Text('拉取此范围 (${_getDateRangeDisplayText()})'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'all'),
            child: const Text('拉取全部服务器订单'),
          ),
        ],
      ),
    );

    if (mode != null && mode != 'cancel') {
      try {
        _showLoadingDialog('正在批量拉取服务器订单...');
        final targetDate = (mode == 'range' && _isSingleDay)
            ? _selectedDateRange.start
            : null;
        final count =
            await _orderService.pullAllServerOrdersToLocal(date: targetDate);
        if (!mounted) return;
        nav.pop();
        _showSuccessSnackBar('成功拉取 $count 个服务器订单到本地数据库');
        await _refreshData();
      } catch (e) {
        if (!mounted) return;
        nav.pop();
        _showErrorSnackBar('批量拉取失败: $e');
      }
    }
  }

  // 计算过滤后的列表
  List<UnifiedOrderItem> get _filteredItems {
    return _unifiedItems.where((item) {
      if (!_containsQuery(item.searchTargetText)) return false;

      switch (_selectedFilter) {
        case UnifiedFilter.normal:
          return item.status == UnifiedOrderStatus.normal;
        case UnifiedFilter.missingInLocal:
          return item.status == UnifiedOrderStatus.missingInLocal;
        case UnifiedFilter.missingInServer:
          return item.status == UnifiedOrderStatus.missingInServer;
        case UnifiedFilter.dataMismatch:
          return item.status == UnifiedOrderStatus.dataMismatch;
        case UnifiedFilter.pendingPrint:
          return item.localOrder != null &&
              item.localOrder!.printStatus != PrintStatus.printed;
        case UnifiedFilter.all:
        default:
          return true;
      }
    }).toList();
  }

  // 清空本地所有订单数据（测试用）
  Future<void> _clearAllLocalOrders() async {
    final nav = Navigator.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 危险操作：清空本地订单'),
        content: const Text(
          '确定要清空本地数据库中的所有订单和日志数据吗？\n\n此操作仅用于测试调优，本地数据清空后不可恢复！',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        _showLoadingDialog('正在清空本地订单数据...');
        final dbService = DatabaseService();
        await dbService.deleteAllOrders();
        if (!mounted) return;
        nav.pop();
        _showSuccessSnackBar('本地订单数据已完全清空');
        await _refreshData();
      } catch (e) {
        if (!mounted) return;
        nav.pop();
        _showErrorSnackBar('清空订单数据失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredItems;
    final totalCount = filtered.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('order_list_title'.tr),
        actions: [
          // 清空本地订单数据 (测试用)
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
            tooltip: '清空本地订单 (测试用)',
            onPressed: _clearAllLocalOrders,
          ),
          // 批量拉取服务器订单
          IconButton(
            icon: const Icon(Icons.cloud_download),
            tooltip: 'pull_all'.tr,
            onPressed: _pullAllServerOrders,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
          ),
        ],
      ),
      body: Column(
        children: [
          // 日期范围导航栏
          DateRangeFilterBar(
            selectedDateRange: _selectedDateRange,
            isAllDateMode: _isAllDateMode,
            onDateRangeChanged: (newRange) {
              setState(() {
                _isAllDateMode = false;
                _selectedDateRange = newRange;
                _currentPage = 0;
              });
              _loadData();
            },
            onAllDateModeSelected: () {
              setState(() {
                _isAllDateMode = true;
                _currentPage = 0;
              });
              _loadData();
            },
          ),

          // 统计卡片 (显示总数、未拉本地、未同步服务器、数据异常等)
          _buildStatsCards(),

          // 筛选与搜索栏
          _buildOrderFilterBar(),

          // 订单列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _refreshData,
                    child: filtered.isEmpty
                        ? _buildEmptyState()
                        : _buildUnifiedOrderList(filtered),
                  ),
          ),

          // 分页控制栏
          _buildPaginationBar(totalCount),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    final total = _unifiedItems.length;
    final missingLocal = _unifiedItems
        .where((i) => i.status == UnifiedOrderStatus.missingInLocal)
        .length;
    final missingServer = _unifiedItems
        .where((i) => i.status == UnifiedOrderStatus.missingInServer)
        .length;
    final mismatch = _unifiedItems
        .where((i) => i.status == UnifiedOrderStatus.dataMismatch)
        .length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              '总订单 (${_getDateRangeDisplayText()})',
              total.toString(),
              Colors.blue,
              Icons.receipt_long,
              onTap: () {
                setState(() {
                  _selectedFilter = UnifiedFilter.all;
                  _currentPage = 0;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              '未拉本地',
              missingLocal.toString(),
              missingLocal > 0 ? Colors.red : Colors.grey[700]!,
              Icons.cloud_download,
              highlight: missingLocal > 0,
              onTap: () {
                setState(() {
                  _selectedFilter = UnifiedFilter.missingInLocal;
                  _currentPage = 0;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              '未同步',
              missingServer.toString(),
              missingServer > 0 ? Colors.orange : Colors.grey[700]!,
              Icons.sync_problem,
              onTap: () {
                setState(() {
                  _selectedFilter = UnifiedFilter.missingInServer;
                  _currentPage = 0;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              '数据异常',
              mismatch.toString(),
              mismatch > 0 ? Colors.amber[800]! : Colors.grey[700]!,
              Icons.warning_amber_rounded,
              onTap: () {
                setState(() {
                  _selectedFilter = UnifiedFilter.dataMismatch;
                  _currentPage = 0;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, Color color, IconData icon,
      {bool highlight = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: highlight ? 2 : 0,
        color: highlight ? color.withOpacity(0.12) : color.withOpacity(0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: color.withOpacity(highlight ? 0.6 : 0.2),
            width: highlight ? 2.0 : 1.0,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(icon, color: color, size: 14),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 16,
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
                  fontSize: 10,
                  color: Colors.grey[700],
                  fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() => _currentPage = 0),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'search_order_hint'.tr,
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
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('全部', UnifiedFilter.all),
                const SizedBox(width: 6),
                _buildFilterChip('正常订单', UnifiedFilter.normal),
                const SizedBox(width: 6),
                _buildFilterChip('未拉本地 (重大失误)', UnifiedFilter.missingInLocal,
                    isWarning: true),
                const SizedBox(width: 6),
                _buildFilterChip('未同步服务器', UnifiedFilter.missingInServer),
                const SizedBox(width: 6),
                _buildFilterChip('数据异常', UnifiedFilter.dataMismatch),
                const SizedBox(width: 6),
                _buildFilterChip('待打印', UnifiedFilter.pendingPrint),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, UnifiedFilter value,
      {bool isWarning = false}) {
    final selected = _selectedFilter == value;
    final activeColor = isWarning ? Colors.red : Colors.green;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected
              ? (isWarning ? Colors.red[900] : Colors.green[900])
              : Colors.black87,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 10),
      side: BorderSide(
        color: selected ? activeColor : Colors.grey[300]!,
        width: selected ? 1.5 : 1.0,
      ),
      selectedColor: activeColor.withOpacity(0.18),
      backgroundColor: Colors.white,
      onSelected: (_) {
        setState(() {
          _selectedFilter = value;
          _currentPage = 0;
        });
      },
    );
  }

  Widget _buildUnifiedOrderList(List<UnifiedOrderItem> items) {
    final startIndex = _currentPage * _pageSize;
    final pageItems = items.skip(startIndex).take(_pageSize).toList();

    return ListView.builder(
      itemCount: pageItems.length,
      itemBuilder: (context, index) {
        final item = pageItems[index];
        return _buildUnifiedOrderCard(item);
      },
    );
  }

  Widget _buildUnifiedOrderCard(UnifiedOrderItem item) {
    switch (item.status) {
      case UnifiedOrderStatus.missingInLocal:
        return _buildMissingInLocalCard(item);
      case UnifiedOrderStatus.missingInServer:
        return _buildMissingInServerCard(item);
      case UnifiedOrderStatus.dataMismatch:
        return _buildDataMismatchCard(item);
      case UnifiedOrderStatus.normal:
      default:
        return _buildNormalCard(item);
    }
  }

  // 1. 【重大失误】服务器有，本地没有 (醒目红框显示)
  Widget _buildMissingInLocalCard(UnifiedOrderItem item) {
    final serverOrder = item.serverOrder!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.red, width: 2),
      ),
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 醒目提示条
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    '【重大提示】订单未拉取落盘到本地数据库',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '订单号: ${item.displayOrderNo} (${serverOrder.orderNumber})',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  '￥${item.displayTotalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '来源: ${serverOrder.placeIn.toUpperCase()} | 类型: ${serverOrder.type.toUpperCase()} | 时间: ${_formatTime(item.sortTime)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[800]),
            ),
            if (item.displayItemsText != '-') ...[
              const SizedBox(height: 4),
              Text(
                '菜品: ${item.displayItemsText}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.cloud_download, size: 18),
                    label: const Text('立刻落地到本地数据库',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => _putServerOrder(serverOrder),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.print, size: 16),
                  label: const Text('打印', style: TextStyle(fontSize: 12)),
                  onPressed: () => _reprintServerOrder(serverOrder),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 2. 本地有，服务器没有 (未同步到服务器)
  Widget _buildMissingInServerCard(UnifiedOrderItem item) {
    final localOrder = item.localOrder!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.orange, width: 1.5),
      ),
      color: Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '未同步到服务器',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Order ${localOrder.orderNo}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  '￥${localOrder.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '时间: ${_formatTime(localOrder.orderTime)} | 状态: ${_getSyncStatusText(localOrder.syncStatus)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[800]),
            ),
            if (item.displayItemsText != '-') ...[
              const SizedBox(height: 4),
              Text(
                '菜品: ${item.displayItemsText}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (localOrder.errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                '错误提示: ${localOrder.errorMessage}',
                style: const TextStyle(color: Colors.red, fontSize: 11),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('重新同步到服务器',
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _retryOrder(localOrder),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _navigateToOrderDetail(localOrder),
                  child: const Text('查看详情', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 3. 数据存在对应，但存在字段差异 (数据异常)
  Widget _buildDataMismatchCard(UnifiedOrderItem item) {
    final localOrder = item.localOrder!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber[800]!, width: 1.5),
      ),
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber[800],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '数据对比存在不一致',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Order ${item.displayOrderNo}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  '￥${item.displayTotalAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber[900],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: item.mismatchDetails
                    .map((detail) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ',
                                  style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold)),
                              Expanded(
                                child: Text(
                                  detail,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (localOrder.syncStatus != SyncStatus.synced)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('重新同步', style: TextStyle(fontSize: 12)),
                    onPressed: () => _retryOrder(localOrder),
                  ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _navigateToOrderDetail(localOrder),
                  child: const Text('查看详情', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 4. 正常匹配订单
  Widget _buildNormalCard(UnifiedOrderItem item) {
    final localOrder = item.localOrder!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.green,
          child: Icon(Icons.check, color: Colors.white),
        ),
        title: Row(
          children: [
            Text(
              'Order ${localOrder.orderNo}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (localOrder.isOnlineOrder) ...[
              const SizedBox(width: 8),
              const Chip(
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
            Text('金额: ￥${localOrder.totalAmount.toStringAsFixed(2)}'),
            Text('时间: ${_formatTime(localOrder.orderTime)}'),
            if (item.displayItemsText != '-')
              Text(
                '菜品: ${item.displayItemsText}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildStatusChip(
                  _getOrderStatusText(localOrder.orderStatus),
                  _getOrderStatusColor(localOrder.orderStatus),
                ),
                const SizedBox(width: 6),
                _buildStatusChip(
                  _getSyncStatusText(localOrder.syncStatus),
                  _getSyncStatusColor(localOrder.syncStatus),
                ),
                const SizedBox(width: 6),
                _buildStatusChip(
                  _getPrintStatusText(localOrder.printStatus),
                  _getPrintStatusColor(localOrder.printStatus),
                ),
              ],
            ),
          ],
        ),
        onTap: () => _navigateToOrderDetail(localOrder),
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          const Icon(Icons.receipt_long, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'no_orders'.tr,
            style: const TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            'no_orders_sub'.tr,
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationBar(int totalItemCount) {
    final totalPages = (totalItemCount / _pageSize).ceil();
    if (totalPages <= 1) {
      return const SizedBox.shrink();
    }

    final bool hasPrev = _currentPage > 0;
    final bool hasNext = (_currentPage + 1) < totalPages;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('上一页', style: TextStyle(fontSize: 12)),
            onPressed: hasPrev
                ? () {
                    setState(() => _currentPage--);
                  }
                : null,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
          ),
          Text(
            '第 ${_currentPage + 1} / $totalPages 页 (共 $totalItemCount 项)',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('下一页', style: TextStyle(fontSize: 12)),
            onPressed: hasNext
                ? () {
                    setState(() => _currentPage++);
                  }
                : null,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
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
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
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
    return '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
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
