import 'package:flutter/material.dart';
import '../../common/models/dining_table.dart';
import '../../common/services/dining_table_service.dart';
import '../../common/services/language_service.dart';
import '../utils/ui_helper.dart';

enum DiningTableAction { update, checkout }

/// 桌台选择框返回结果对象
class DiningTableSelectionResult {
  final DiningTable table;
  final List<Map<String, dynamic>>? rawItems;
  final bool isExistingOrder;
  final Map<String, dynamic>? activeOrder;
  final int? guestCount;
  final int? reservationId;
  final DiningTableAction action;

  DiningTableSelectionResult({
    required this.table,
    this.rawItems,
    this.isExistingOrder = false,
    this.activeOrder,
    this.guestCount,
    this.reservationId,
    this.action = DiningTableAction.update,
  });
}

class DiningTableSelectionDialog extends StatefulWidget {
  const DiningTableSelectionDialog({super.key});

  static Future<DiningTableSelectionResult?> show(BuildContext context) {
    return showDialog<DiningTableSelectionResult>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const DiningTableSelectionDialog(),
    );
  }

  @override
  State<DiningTableSelectionDialog> createState() =>
      _DiningTableSelectionDialogState();
}

class _DiningTableSelectionDialogState
    extends State<DiningTableSelectionDialog> with SingleTickerProviderStateMixin {
  final DiningTableService _tableService = DiningTableService();
  late TabController _tabController;

  List<DiningTable> _tables = [];
  TodayReservationsData? _todayReservationsData;
  bool _isLoading = true;
  bool _isReservationsLoading = false;
  String? _selectedArea = 'ALL';

  DateTime _selectedReservationDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAllData(forceRefresh: true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _formattedReservationDate {
    final year = _selectedReservationDate.year;
    final month = _selectedReservationDate.month.toString().padLeft(2, '0');
    final day = _selectedReservationDate.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedReservationDate.year == now.year &&
        _selectedReservationDate.month == now.month &&
        _selectedReservationDate.day == now.day;
  }

  String get _dateDisplayName {
    if (_isToday) {
      return '$_formattedReservationDate (今天)';
    }
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    if (_selectedReservationDate.year == tomorrow.year &&
        _selectedReservationDate.month == tomorrow.month &&
        _selectedReservationDate.day == tomorrow.day) {
      return '$_formattedReservationDate (明天)';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (_selectedReservationDate.year == yesterday.year &&
        _selectedReservationDate.month == yesterday.month &&
        _selectedReservationDate.day == yesterday.day) {
      return '$_formattedReservationDate (昨天)';
    }
    return _formattedReservationDate;
  }

  Future<void> _loadAllData({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _tableService.getTables(forceRefresh: forceRefresh),
        _tableService.getTodayReservations(date: _formattedReservationDate),
      ]);

      if (mounted) {
        setState(() {
          _tables = results[0] as List<DiningTable>;
          _todayReservationsData = results[1] as TodayReservationsData?;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadReservationsOnly() async {
    setState(() => _isReservationsLoading = true);
    try {
      final resData = await _tableService.getTodayReservations(
        date: _formattedReservationDate,
      );
      if (mounted) {
        setState(() {
          _todayReservationsData = resData;
          _isReservationsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isReservationsLoading = false);
      }
    }
  }

  void _changeReservationDate(int daysDelta) {
    setState(() {
      _selectedReservationDate =
          _selectedReservationDate.add(Duration(days: daysDelta));
    });
    _loadReservationsOnly();
  }

  Future<void> _pickReservationDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedReservationDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedReservationDate) {
      setState(() {
        _selectedReservationDate = picked;
      });
      _loadReservationsOnly();
    }
  }

  List<String> get _areas {
    final list = <String>{'ALL'};
    for (var t in _tables) {
      if (t.area != null && t.area!.isNotEmpty) {
        list.add(t.area!);
      }
    }
    return list.toList();
  }

  List<DiningTable> get _filteredTables {
    if (_selectedArea == null || _selectedArea == 'ALL') {
      return _tables;
    }
    return _tables.where((t) => t.area == _selectedArea).toList();
  }

  List<DiningTable> get _availableTables {
    return _tables.where((t) => t.isAvailable).toList();
  }

  List<DiningTableReservation> get _waitingReservations {
    return _todayReservationsData?.waitingReservations ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final waitingCount = _waitingReservations.length;

    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.08),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Theme.of(context).primaryColor,
                unselectedLabelColor: Colors.grey[700],
                indicatorColor: Theme.of(context).primaryColor,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.table_restaurant, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'select_table'.tr,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.event_seat, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          '待入座预约',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        if (waitingCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade700,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$waitingCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'refresh_tables'.tr,
              onPressed: () {
                UIHelper.showToast(
                  context,
                  '桌态与预约列表已刷新同步',
                  backgroundColor: Colors.green,
                );
                _tableService.clearAllTableCaches().then((_) {
                  _loadAllData(forceRefresh: true);
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: screenSize.width * 0.78,
        height: screenSize.height * 0.72,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: 桌态看板
                  _buildTablesBoardView(),
                  // Tab 2: 待入座预约接待列表
                  _buildWaitingReservationsView(),
                ],
              ),
      ),
    );
  }

  /// 视图1: 桌态看板网格
  Widget _buildTablesBoardView() {
    return Column(
      children: [
        const SizedBox(height: 8),
        // 区域筛选 Chips
        if (_areas.length > 1) ...[
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _areas.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final area = _areas[index];
                final isSelected = _selectedArea == area;
                final label = area == 'ALL' ? 'all_categories'.tr : area;
                return ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedArea = area);
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 桌台卡片 GridView
        Expanded(
          child: _filteredTables.isEmpty
              ? Center(child: Text('no_data'.tr))
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.25,
                  ),
                  itemCount: _filteredTables.length,
                  itemBuilder: (context, index) {
                    final table = _filteredTables[index];
                    return _buildTableCard(table);
                  },
                ),
        ),
      ],
    );
  }

  /// 视图2: 待入座预约接待列表（支持前一天/后一天/日期选择）
  Widget _buildWaitingReservationsView() {
    return Column(
      children: [
        const SizedBox(height: 8),
        // 日期切换控制栏
        _buildDateSelectorBar(),
        const SizedBox(height: 10),

        // 预约列表数据
        Expanded(
          child: _isReservationsLoading
              ? const Center(child: CircularProgressIndicator())
              : _waitingReservations.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_available,
                              size: 56, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            '$_dateDisplayName 暂无待入座预约',
                            style: TextStyle(
                                fontSize: 15, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: _waitingReservations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final res = _waitingReservations[index];
                        return _buildWaitingReservationCard(res);
                      },
                    ),
        ),
      ],
    );
  }

  /// 构建预约日期选择控制栏
  Widget _buildDateSelectorBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.purple.shade50.withOpacity(0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple.shade100),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 前一天
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '前一天',
            onPressed: () => _changeReservationDate(-1),
          ),

          // 日期按钮（支持点击打开 DatePicker）
          InkWell(
            onTap: _pickReservationDate,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_month,
                      size: 18, color: Colors.purple.shade700),
                  const SizedBox(width: 8),
                  Text(
                    _dateDisplayName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade900,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, color: Colors.purple.shade700),
                ],
              ),
            ),
          ),

          // 后一天与快捷“回到今天”
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isToday) ...[
                ActionChip(
                  label: const Text('回到今天', style: TextStyle(fontSize: 12)),
                  avatar: const Icon(Icons.today, size: 14),
                  backgroundColor: Colors.purple.shade100,
                  onPressed: () {
                    setState(() {
                      _selectedReservationDate = DateTime.now();
                    });
                    _loadReservationsOnly();
                  },
                ),
                const SizedBox(width: 6),
              ],
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: '后一天',
                onPressed: () => _changeReservationDate(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建单张待入座预约卡片
  Widget _buildWaitingReservationCard(DiningTableReservation res) {
    final hasPreorder = res.hasPreOrder ||
        (res.preorder != null && res.preorder!.items.isNotEmpty);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.purple.shade200, width: 1.2),
      ),
      color: Colors.purple.shade50.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 时间 Block
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.purple.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time, color: Colors.white, size: 18),
                  const SizedBox(height: 4),
                  Text(
                    res.reservationTime ?? '全天',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // 客人与预约详情
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        res.customerName ?? '预约顾客',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${res.guestCount ?? 2}人',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.purple.shade900,
                          ),
                        ),
                      ),
                      if (hasPreorder) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '含预点菜品',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (res.customerPhone != null &&
                      res.customerPhone!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '电话: ${res.customerPhone}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                    ),
                  ],
                  if (res.itemsOrderedSummary != null &&
                      res.itemsOrderedSummary!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '预点: ${res.itemsOrderedSummary}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // 入座开台 Action 按钮
            ElevatedButton.icon(
              icon: const Icon(Icons.restaurant, size: 18),
              label: const Text('指定桌台并入座'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => _handleSeatReservationFromList(res),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建桌台 Card
  Widget _buildTableCard(DiningTable table) {
    Color cardBgColor;
    Color borderColor;
    Color textColor;
    String statusLabel;

    if (table.isOccupied) {
      cardBgColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade300;
      textColor = Colors.orange.shade800;
      statusLabel = 'table_occupied'.tr;
    } else if (table.isDisabled) {
      cardBgColor = Colors.grey.shade100;
      borderColor = Colors.grey.shade400;
      textColor = Colors.grey.shade700;
      statusLabel = '禁用';
    } else {
      cardBgColor = Colors.green.shade50;
      borderColor = Colors.green.shade300;
      textColor = Colors.green.shade800;
      statusLabel = 'table_available'.tr;
    }

    return Card(
      elevation: 2,
      color: cardBgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _handleTableTap(table),
        onLongPress: () => _handleTableLongPress(table),
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 桌台名称 & 状态 Chip
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      table.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: borderColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              // 区域与容纳人数
              Row(
                children: [
                  if (table.area != null && table.area!.isNotEmpty)
                    Expanded(
                      child: Text(
                        table.area!,
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor.withOpacity(0.8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Icon(Icons.people_alt_outlined, size: 14, color: textColor),
                  const SizedBox(width: 4),
                  Text(
                    '${table.capacity}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),

              // 进行中订单提示
              if (table.isOccupied) ...[
                Text(
                  '单号: ${table.activeOrder?['order_no'] ?? table.activeOrder?['order_number'] ?? '进行中'}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 处理点击桌台
  void _handleTableTap(DiningTable table) {
    if (table.isOccupied) {
      _showOccupiedOrderDetailsDialog(table);
      return;
    }

    if (table.isDisabled) {
      UIHelper.showToast(context, '该桌台当前已被禁用', backgroundColor: Colors.orange);
      return;
    }

    // 处理空闲桌台 available
    _handleAvailableTableTap(table);
  }

  /// 点击空闲桌台：支持散客开台 或 选择待入座预约一键入座
  void _handleAvailableTableTap(DiningTable table) {
    if (_waitingReservations.isEmpty) {
      // 当前没有待入座预约，直接散客开台
      _selectAvailableTable(table);
      return;
    }

    // 存在待入座预约，跳出对话框供商家选择
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.table_restaurant, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Text('开台 - ${table.name}'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '请选择开台方式：',
                style: TextStyle(fontSize: 14, color: Colors.grey[800]),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.person_add),
                  label: const Text('散客直接开台'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    _selectAvailableTable(table);
                  },
                ),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                '选择待入座预约入座此桌 (${_waitingReservations.length}位待接待)：',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _waitingReservations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, idx) {
                    final res = _waitingReservations[idx];
                    return ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.purple.shade200),
                      ),
                      tileColor: Colors.purple.shade50,
                      title: Text(
                        '${res.customerName ?? "预订客户"} (${res.guestCount ?? table.capacity}人) - ${res.reservationTime ?? "今日"}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: res.hasPreOrder
                          ? Text(
                              '含预点菜品 ${res.itemsOrderedSummary != null ? "(${res.itemsOrderedSummary})" : ""}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.deepOrange.shade800,
                              ),
                            )
                          : null,
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () {
                        Navigator.pop(dialogCtx);
                        _seatReservationAndReturn(res, table);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('cancel'.tr),
          ),
        ],
      ),
    );
  }

  /// 从【待入座预约】列表点击【指定桌台并入座】
  void _handleSeatReservationFromList(DiningTableReservation res) {
    final available = _availableTables;

    if (available.isEmpty) {
      UIHelper.showToast(
        context,
        '当前没有空闲桌台可用，请先清理或释放桌台',
        backgroundColor: Colors.orange,
      );
      return;
    }

    int? selectedTableId = available.first.id;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.event_seat, color: Colors.purple.shade700),
                const SizedBox(width: 8),
                Text('安排入座 - ${res.customerName ?? "预约客户"}'),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '预约时间: ${res.reservationTime ?? "今日"} (${res.guestCount ?? 2}人)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (res.itemsOrderedSummary != null &&
                      res.itemsOrderedSummary!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '预点摘要: ${res.itemsOrderedSummary}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: selectedTableId,
                    decoration: const InputDecoration(
                      labelText: '选择空闲桌台',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.table_restaurant),
                    ),
                    items: available.map((t) {
                      return DropdownMenuItem<int>(
                        value: t.id,
                        child: Text(
                          '${t.name}${t.area != null && t.area!.isNotEmpty ? " (${t.area})" : ""} [${t.capacity}人位]',
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedTableId = val);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('cancel'.tr),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('确认入座开台'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  final targetTable = available
                      .firstWhere((t) => t.id == selectedTableId);
                  _seatReservationAndReturn(res, targetTable);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// 执行入座 API 并返回选定桌台及预点菜品
  Future<void> _seatReservationAndReturn(
    DiningTableReservation res,
    DiningTable table,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final success = await _tableService.seatReservation(
      reservationId: res.id,
      tableId: table.id,
    );

    if (mounted) {
      Navigator.pop(context); // 关闭 loading 弹窗
    }

    List<Map<String, dynamic>> rawPreorderItems = [];
    if (res.preorder != null) {
      rawPreorderItems = res.preorder!.items;
    }

    if (rawPreorderItems.isNotEmpty) {
      await _tableService.saveLocalTableItems(
        table.id,
        rawPreorderItems,
        reservationId: res.id,
      );
    }

    if (!mounted) return;

    UIHelper.showToast(
      context,
      success ? '入座成功！关联桌台 ${table.name}' : '入座提示: 已同步桌台开台',
      backgroundColor: success ? Colors.green : Colors.orange,
    );

    Navigator.pop(
      context,
      DiningTableSelectionResult(
        table: table.copyWith(status: 'occupied'),
        rawItems: rawPreorderItems,
        isExistingOrder: rawPreorderItems.isNotEmpty,
        guestCount: res.guestCount,
        reservationId: res.id,
        action: DiningTableAction.update,
      ),
    );
  }

  /// 处理已在用餐的桌台
  void _showOccupiedOrderDetailsDialog(DiningTable table) {
    final activeOrder = table.activeOrder;
    List<Map<String, dynamic>> rawItems =
        DiningTableService.extractItemsForReservation(table, null);

    if (rawItems.isEmpty && activeOrder != null) {
      dynamic itemsRaw = activeOrder['items'] ??
          activeOrder['order_items'] ??
          activeOrder['details'];
      if (itemsRaw is List) {
        rawItems = itemsRaw
            .map((i) => i is Map<String, dynamic>
                ? i
                : Map<String, dynamic>.from(i as Map))
            .toList();
      }
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('${table.name} - ${'active_order_info'.tr}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '单号: ${activeOrder?['order_no'] ?? activeOrder?['order_number'] ?? "进行中"}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (activeOrder?['total_amount'] != null)
                Text('金额: \$${activeOrder!['total_amount']}'),
              const SizedBox(height: 10),
              if (rawItems.isNotEmpty) ...[
                const Text('已下单菜品:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                SizedBox(
                  child: SingleChildScrollView(
                    child: Column(
                      children: rawItems.map((item) {
                        final title = item['name'] ?? item['title'] ?? '未知';
                        final qty = item['quantity'] ?? 1;
                        final price =
                            item['price'] ?? item['selling_price'] ?? 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '$title',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              Text('x$qty'),
                              const SizedBox(width: 8),
                              Text('\$$price'),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ] else ...[
                Text('暂无菜品明细数据',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('cancel'.tr),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.edit),
            label: Text('edit_items'.tr),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(dialogCtx);
              Navigator.pop(
                context,
                DiningTableSelectionResult(
                  table: table,
                  rawItems: rawItems,
                  isExistingOrder: true,
                  activeOrder: activeOrder,
                  action: DiningTableAction.update,
                ),
              );
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.shopping_cart),
            label: Text('checkout'.tr),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(dialogCtx);
              Navigator.pop(
                context,
                DiningTableSelectionResult(
                  table: table,
                  rawItems: rawItems,
                  isExistingOrder: true,
                  activeOrder: activeOrder,
                  action: DiningTableAction.checkout,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 选择空闲桌台（普通散客开台）
  void _selectAvailableTable(DiningTable table) {
    Navigator.pop(
      context,
      DiningTableSelectionResult(
        table: table,
        isExistingOrder: false,
      ),
    );
  }

  /// 长按桌台清空状态
  void _handleTableLongPress(DiningTable table) async {
    final bool isOccupiedOrHasOrder = table.isOccupied ||
        (table.activeOrder != null && table.activeOrder!.isNotEmpty);

    if (!isOccupiedOrHasOrder) {
      UIHelper.showToast(
        context,
        '桌台 ${table.name} 当前为空闲状态',
        backgroundColor: Colors.blueGrey,
      );
      return;
    }

    final confirmed = await UIHelper.showConfirmDialog(
      context,
      title: '清空桌台 - ${table.name}',
      content: '确定要清空桌台 ${table.name} 的已点菜品，并重置为空闲状态吗？',
      confirmText: '确认清空',
      cancelText: '取消',
    );

    if (confirmed == true) {
      await _tableService.clearLocalTableItems(table.id);
      await _loadAllData(forceRefresh: false);
      if (mounted) {
        UIHelper.showToast(
          context,
          '桌台 ${table.name} 菜品已清空，已重置为空闲状态',
          backgroundColor: Colors.green,
        );
      }
    }
  }
}
