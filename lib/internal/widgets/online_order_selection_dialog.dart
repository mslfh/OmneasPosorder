import 'package:flutter/material.dart';
import '../../common/models/order_model.dart';
import '../../common/services/order_service.dart';
import '../utils/online_order_mapper.dart';

enum OnlineOrderSortType {
  orderTimeAsc('预计时间 (最早)', 'orderTime', true),
  orderTimeDesc('预计时间 (最晚)', 'orderTime', false),
  createdAtDesc('下单时间 (最新)', 'createdAt', false),
  orderNoAsc('订单号 (升序)', 'orderNo', true);

  final String label;
  final String criteria;
  final bool ascending;
  const OnlineOrderSortType(this.label, this.criteria, this.ascending);
}

class OnlineOrderSelectionDialog extends StatefulWidget {
  const OnlineOrderSelectionDialog({super.key});

  static Future<OrderModel?> show(BuildContext context) {
    return showDialog<OrderModel>(
      context: context,
      builder: (context) => const OnlineOrderSelectionDialog(),
    );
  }

  @override
  State<OnlineOrderSelectionDialog> createState() =>
      _OnlineOrderSelectionDialogState();
}

class _OnlineOrderSelectionDialogState
    extends State<OnlineOrderSelectionDialog> {
  final OrderService _orderService = OrderService();
  late Future<List<OrderModel>> _ordersFuture;
  final DateTime _today = DateTime.now();
  OnlineOrderSortType _currentSort = OnlineOrderSortType.orderTimeAsc;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _orderService.getPendingOnlineOrders(date: _today);
  }

  String _formatOrderTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}mins ago';
    if (diff.inHours < 24) return '${diff.inHours}hours ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildStatusChip(OrderStatus status) {
    final isPending = status == OrderStatus.pending;
    final color = isPending ? Colors.orange : Colors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        isPending ? 'pending' : 'confirmed',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildOrderSummary(OrderModel order) {
    final items = order.getItemsList();
    final itemNames = items
        .map((item) => item['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .take(3)
        .toList();
    final extra = items.length > itemNames.length
        ? ' +${items.length - itemNames.length} more'
        : '';
    final orderNumberText = '#${order.orderNo}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 大字体：订单号 + 状态
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                orderNumberText,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _buildStatusChip(order.orderStatus),
          ],
        ),
        const SizedBox(height: 4),
        // 中字体：下单时间/取餐时间以及金额
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.orange[800]),
                      const SizedBox(width: 4),
                      Text(
                        'Time：${_formatOrderTime(order.orderTime)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_timeAgo(order.createdAt)}~',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '￥${order.totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // 小字体：商品明细
        if (itemNames.isNotEmpty)
          Text(
            'Items: ${itemNames.join(', ')}$extra',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        if (order.note != null && order.note!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Note: ${order.note}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Choose Order')),
          PopupMenuButton<OnlineOrderSortType>(
            icon: const Icon(Icons.sort, size: 22),
            tooltip: 'Sort by',
            onSelected: (type) {
              setState(() {
                _currentSort = type;
              });
            },
            itemBuilder: (context) => OnlineOrderSortType.values
                .map((type) => PopupMenuItem(
                      value: type,
                      child: Row(
                        children: [
                          if (_currentSort == type)
                            const Icon(Icons.check, size: 18, color: Colors.orange)
                          else
                            const SizedBox(width: 18),
                          const SizedBox(width: 8),
                          Text(type.label, style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
      content: SizedBox(
        width: 450,
        height: 450,
        child: FutureBuilder<List<OrderModel>>(
          future: _ordersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Load failed: ${snapshot.error}'));
            }

            final rawOrders = snapshot.data ?? const <OrderModel>[];
            final ordersFiltered = rawOrders
                .where((o) => o.orderStatus != OrderStatus.confirmed)
                .toList();

            if (ordersFiltered.isEmpty) {
              return const Center(child: Text('No pending online orders'));
            }

            final orders = OnlineOrderMapper.sortOrders(
              ordersFiltered,
              _currentSort.criteria,
              ascending: _currentSort.ascending,
            );

            return ListView.separated(
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final order = orders[index];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Colors.orange.withOpacity(0.18)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(context).pop(order),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.cloud_done,
                              color: Colors.orange[700],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: _buildOrderSummary(order)),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, color: Colors.grey[500]),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
