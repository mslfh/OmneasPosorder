import 'package:flutter/material.dart';
import '../../common/models/order_model.dart';
import '../../common/services/order_service.dart';

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

  @override
  void initState() {
    super.initState();
    _ordersFuture = _orderService.getPendingOnlineOrders(date: _today);
  }

  String _formatOrderTime(DateTime time) {
    return '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Remote: ${order.remoteOrderNumber ?? '-'}',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
            const Spacer(),
            Text(
              _formatOrderTime(order.orderTime),
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'Amount ￥${order.totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            _buildStatusChip(order.orderStatus),
          ],
        ),
        const SizedBox(height: 6),
        if (itemNames.isNotEmpty)
          Text(
            'Items: ${itemNames.join(', ')}$extra',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (order.note != null && order.note!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Note: ${order.note}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey[700]),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择在线订单（今天）'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: FutureBuilder<List<OrderModel>>(
          future: _ordersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('加载失败: ${snapshot.error}'));
            }

            final orders = snapshot.data ?? const <OrderModel>[];
            if (orders.isEmpty) {
              return const Center(child: Text('暂无可结账的在线订单'));
            }

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
                      padding: const EdgeInsets.all(14),
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
          child: const Text('取消'),
        ),
      ],
    );
  }
}
