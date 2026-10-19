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
    extends State<DiningTableSelectionDialog> {
  final DiningTableService _tableService = DiningTableService();
  List<DiningTable> _tables = [];
  bool _isLoading = true;
  String? _selectedArea = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadTables(forceRefresh: true);
  }

  Future<void> _loadTables({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    final tables = await _tableService.getTables(forceRefresh: forceRefresh);
    if (mounted) {
      setState(() {
        _tables = tables;
        _isLoading = false;
      });
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

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.08),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(
          children: [
            Icon(Icons.table_restaurant, color: Theme.of(context).primaryColor),
            const SizedBox(width: 10),
            Text(
              'select_table'.tr,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'refresh_tables'.tr,
              onPressed: () async {
                await _tableService.clearAllTableCaches();
                await _loadTables(forceRefresh: true);
                if (mounted) {
                  UIHelper.showToast(
                    context,
                    '桌台本地菜品缓存已重置，已同步最新 API 数据',
                    backgroundColor: Colors.green,
                  );
                }
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
        width: screenSize.width * 0.75,
        height: screenSize.height * 0.7,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // 区域筛选 Tabs / Chips
                  if (_areas.length > 1) ...[
                    SizedBox(
                      height: 40,
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
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1.2,
                            ),
                            itemCount: _filteredTables.length,
                            itemBuilder: (context, index) {
                              final table = _filteredTables[index];
                              return _buildTableCard(table);
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

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
    } else if (table.hasReservation) {
      cardBgColor = Colors.purple.shade50;
      borderColor = Colors.purple.shade300;
      textColor = Colors.purple.shade800;
      statusLabel = 'table_reserved'.tr;
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
                  Flexible(
                    child: Container(
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

              // 预点/进行中订单提示
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
              ] else if (table.hasReservation || table.currentReservation != null) ...[
                Builder(builder: (_) {
                  final curRes = table.currentReservation ??
                      (table.reservations != null && table.reservations!.isNotEmpty
                          ? table.reservations!.first
                          : null);
                  final name = curRes?.customerName ?? '';
                  final time = curRes?.reservationTime ?? '';
                  final hasPre = curRes?.hasPreOrder == true;

                  return Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      Text(
                        '预订: $name $time'.trim(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (hasPre)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '含预点',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange.shade900,
                            ),
                          ),
                        ),
                    ],
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleTableTap(DiningTable table) async {
    // 1. 优先判断：若桌台为就座/使用中 (occupied)，无论今天有多少个预约，点击该桌台直接展现已落地的 active table order！
    if (table.isOccupied) {
      _showOccupiedOrderDetailsDialog(table);
      return;
    }

    final reservations = table.todayReservations ??
        (table.currentReservation != null
            ? [table.currentReservation!]
            : (table.reservations ?? []));

    // 2. 桌台尚未就座：如果有多个预约 (length > 1)，优先展示按时间排序的预约列表
    if (reservations.length > 1) {
      _showTodayReservationsListDialog(table, reservations);
    } else if (reservations.length == 1) {
      _showReservationDetailsDialog(table, reservations.first);
    } else if (table.currentReservation != null) {
      _showReservationDetailsDialog(table, table.currentReservation!);
    } else {
      _selectAvailableTable(table);
    }
  }

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
      await _loadTables(forceRefresh: false);
      if (mounted) {
        UIHelper.showToast(
          context,
          '桌台 ${table.name} 菜品已清空，已重置为空闲状态',
          backgroundColor: Colors.green,
        );
      }
    }
  }

  /// 当桌台今日有多个预约时，展现按时间排序的预约列表
  void _showTodayReservationsListDialog(
    DiningTable table,
    List<DiningTableReservation> reservations,
  ) {
    final sortedList = List<DiningTableReservation>.from(reservations);
    sortedList.sort((a, b) {
      final tA = a.reservationTime ?? '';
      final tB = b.reservationTime ?? '';
      return tA.compareTo(tB);
    });

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.event_note, color: Colors.purple.shade700),
            const SizedBox(width: 8),
            Text('${table.name} - 今日预约列表 (${sortedList.length}个)'),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '请选择要查看或开台的预约订单：',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sortedList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, idx) {
                    final res = sortedList[idx];
                    final isSeated = res.status?.toLowerCase() == 'seated' ||
                        res.status?.toLowerCase() == 'completed' ||
                        table.isReservationSeated(res.id);

                    return InkWell(
                      onTap: () {
                        Navigator.pop(dialogCtx);
                        if (isSeated) {
                          _showOccupiedOrderDetailsDialog(table, res);
                        } else {
                          _showReservationDetailsDialog(table, res);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSeated
                              ? Colors.orange.shade50
                              : Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSeated
                                ? Colors.orange.shade300
                                : Colors.purple.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSeated
                                    ? Colors.orange.shade800
                                    : Colors.purple.shade700,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                res.reservationTime ?? '全天',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        '${res.customerName ?? "预订客户"} (${res.guestCount ?? table.capacity}人)',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14),
                                      ),
                                      if (isSeated) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.shade200,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '已服务/就座',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orange.shade900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (res.customerPhone != null &&
                                      res.customerPhone!.isNotEmpty)
                                    Text(
                                      res.customerPhone!,
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.grey[700]),
                                    ),
                                ],
                              ),
                            ),
                            if (res.hasPreOrder)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.deepOrange.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '含预点',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.deepOrange.shade900,
                                  ),
                                ),
                              ),
                            Icon(
                              Icons.chevron_right,
                              color: isSeated
                                  ? Colors.orange.shade800
                                  : Colors.purple.shade700,
                            ),
                          ],
                        ),
                      ),
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

  /// 处理已预约的桌台
  void _showReservationDetailsDialog(
    DiningTable table, [
    DiningTableReservation? targetRes,
  ]) async {
    DiningTableReservation? reservation =
        targetRes ?? table.currentReservation;
    List<Map<String, dynamic>> rawPreorderItems = [];

    if (reservation == null &&
        table.reservations != null &&
        table.reservations!.isNotEmpty) {
      reservation = table.reservations!.first;
    }

    if (reservation?.preorder != null) {
      rawPreorderItems = reservation!.preorder!.items;
    } else if (reservation == null) {
      // 调 API 获取最新预约及预点菜品
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final resData = await _tableService.getReservationAndPreorder(table.id);
      if (mounted) Navigator.pop(context); // close loading

      if (resData != null && resData['reservations'] is List) {
        final list = (resData['reservations'] as List)
            .map((r) => DiningTableReservation.fromJson(
                  r is Map<String, dynamic> ? r : Map<String, dynamic>.from(r),
                ))
            .toList();
        if (list.isNotEmpty) {
          reservation = list.first;
          if (reservation.preorder != null) {
            rawPreorderItems = reservation.preorder!.items;
          }
        }
      }
    }

    if (!mounted) return;

    final curRes = reservation;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.event_seat, color: Colors.purple.shade700),
              const SizedBox(width: 8),
              Text('${table.name} - 预约详情'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: curRes == null
                ? Text('no_data'.tr)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.purple.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '客户: ${curRes.customerName ?? "未名"}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                if (curRes.customerPhone != null &&
                                    curRes.customerPhone!.isNotEmpty)
                                  Text(
                                    curRes.customerPhone!,
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.access_time,
                                    size: 16, color: Colors.purple.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  '时间: ${curRes.reservationTime ?? "当天"}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const SizedBox(width: 16),
                                Icon(Icons.people,
                                    size: 16, color: Colors.purple.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  '人数: ${curRes.guestCount ?? table.capacity} 人',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (rawPreorderItems.isNotEmpty) ...[
                        const Text(
                          '预约菜品 (Preorder Items):',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                for (var item in rawPreorderItems) ...[
                                  Builder(
                                    builder: (_) {
                                      final title = item['name'] ??
                                          item['product_title'] ??
                                          item['title'] ??
                                          '菜品';
                                      final qty = item['quantity'] ?? 1;
                                      final price = item['price'] ??
                                          item['unit_price'] ??
                                          0.0;
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[100],
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '$title',
                                                style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500),
                                              ),
                                            ),
                                            Text('x$qty',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold)),
                                            const SizedBox(width: 12),
                                            Text('\$$price'),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        Text(
                          '该预约暂无预点菜品',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text('cancel'.tr),
            ),
            if (curRes != null) ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.edit_calendar, size: 16),
                label: const Text('修改预约'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[800],
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _showEditReservationDialog(table, curRes);
                },
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('取消预约'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final confirm = await UIHelper.showConfirmDialog(
                    context,
                    title: '取消预约 - ${table.name}',
                    content:
                        '确定要取消顾客 [${curRes.customerName ?? "该客户"}] 在 ${curRes.reservationTime ?? "今日"} 的预约吗？',
                    confirmText: '确认取消',
                    cancelText: '暂不取消',
                  );

                  if (confirm == true) {
                    Navigator.pop(dialogCtx);
                    final success = await _tableService.cancelReservation(
                      curRes.id,
                      reason: '顾客取消',
                    );
                    await _loadTables(forceRefresh: true);
                    if (mounted) {
                      UIHelper.showToast(
                        context,
                        success ? '预约已成功取消' : '取消预约操作已完成',
                        backgroundColor:
                            success ? Colors.green : Colors.orange,
                      );
                    }
                  }
                },
              ),
            ],
            ElevatedButton.icon(
              icon: const Icon(Icons.restaurant),
              label: const Text('SERVE / 入座开台'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(dialogCtx);

                // 1. 设置预约状态为 seated (服务中/已就座)
                await _tableService.occupyTable(table.id,
                    reservationId: curRes?.id);

                // 2. 将预约预点菜品落地暂存到本地桌台（按 reservationId 独立存储），并置桌台状态为 occupied
                if (rawPreorderItems.isNotEmpty) {
                  await _tableService.saveLocalTableItems(
                    table.id,
                    rawPreorderItems,
                    reservationId: curRes?.id,
                  );
                }

                if (!mounted) return;
                Navigator.pop(
                  context,
                  DiningTableSelectionResult(
                    table: table.copyWith(status: 'occupied'),
                    rawItems: rawPreorderItems,
                    isExistingOrder: true,
                    guestCount: curRes?.guestCount,
                    reservationId: curRes?.id,
                    action: DiningTableAction.update,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// 显示修改预约信息弹窗 (包含换桌、改时间、改人数、改姓名电话)
  void _showEditReservationDialog(
    DiningTable table,
    DiningTableReservation res,
  ) {
    final nameCtrl = TextEditingController(text: res.customerName ?? '');
    final phoneCtrl = TextEditingController(text: res.customerPhone ?? '');
    final timeCtrl =
        TextEditingController(text: res.reservationTime ?? '18:00');
    final guestCtrl = TextEditingController(
        text: (res.guestCount ?? table.capacity).toString());
    int selectedTableId = table.id;

    showDialog(
      context: context,
      builder: (editCtx) => StatefulBuilder(
        builder: (ctx, setEditState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.edit_calendar, color: Colors.blue[800]),
                const SizedBox(width: 8),
                Text('修改预约信息 - ${table.name}'),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selectedTableId,
                      decoration: const InputDecoration(
                        labelText: '分配桌台 (换桌)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.table_restaurant),
                      ),
                      items: _tables.map((t) {
                        return DropdownMenuItem<int>(
                          value: t.id,
                          child: Text(
                            '${t.name}${t.area != null && t.area!.isNotEmpty ? " (${t.area})" : ""} [${t.capacity}人]',
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setEditState(() {
                            selectedTableId = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '客户姓名',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: '联系电话',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: timeCtrl,
                            decoration: const InputDecoration(
                              labelText: '预约时间',
                              border: OutlineInputBorder(),
                              hintText: '如 18:30',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: guestCtrl,
                            decoration: const InputDecoration(
                              labelText: '就餐人数',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(editCtx),
                child: Text('cancel'.tr),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('保存修改'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[800],
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final newName = nameCtrl.text.trim();
                  final newPhone = phoneCtrl.text.trim();
                  final newTime = timeCtrl.text.trim();
                  final newGuests =
                      int.tryParse(guestCtrl.text) ?? res.guestCount;

                  Navigator.pop(editCtx);

                  final success = await _tableService.updateReservation(
                    res.id,
                    tableId: selectedTableId,
                    customerName: newName,
                    customerPhone: newPhone,
                    reservationTime: newTime,
                    guestCount: newGuests,
                  );

                  await _loadTables(forceRefresh: true);

                  if (mounted) {
                    UIHelper.showToast(
                      context,
                      success ? '预约信息及桌台已成功更新！' : '预约信息已提交更新',
                      backgroundColor: success ? Colors.green : Colors.orange,
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// 处理已在用餐的桌台
  void _showOccupiedOrderDetailsDialog(
    DiningTable table, [
    DiningTableReservation? targetRes,
  ]) {
    final activeOrder = table.activeOrder;
    final resId = targetRes?.id;

    List<Map<String, dynamic>> rawItems =
        DiningTableService.extractItemsForReservation(table, resId);

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

    final List<DiningTableReservation> otherReservations = [];
    if (table.todayReservations != null && table.todayReservations!.isNotEmpty) {
      otherReservations.addAll(table.todayReservations!);
    }
    if (table.reservations != null) {
      for (var r in table.reservations!) {
        if (!otherReservations.any((existing) => existing.id == r.id)) {
          otherReservations.add(r);
        }
      }
    }
    if (table.currentReservation != null) {
      if (!otherReservations.any((existing) => existing.id == table.currentReservation!.id)) {
        otherReservations.add(table.currentReservation!);
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
                        final price = item['price'] ?? item['selling_price'] ?? 0;
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
                Text('暂无菜品明细数据', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
              if (otherReservations.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_note, size: 16),
                    label: Text('查看该桌预约排期 (${otherReservations.length}个)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.purple.shade800,
                      side: BorderSide(color: Colors.purple.shade300),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      _showTodayReservationsListDialog(table, otherReservations);
                    },
                  ),
                ),
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
                  reservationId: resId,
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
                  reservationId: resId,
                  action: DiningTableAction.checkout,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 选择空闲桌台
  void _selectAvailableTable(DiningTable table) {
    Navigator.pop(
      context,
      DiningTableSelectionResult(
        table: table,
        isExistingOrder: false,
      ),
    );
  }
}
