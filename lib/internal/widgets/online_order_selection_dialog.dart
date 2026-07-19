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
    final orderNumberText = (order.remoteOrderNumber != null &&
            order.remoteOrderNumber!.isNotEmpty)
        ? '#Online ${order.orderNo}'
        : '#${order.orderNo}';

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
        // 中字体：下单时间 + xx ago，以及金额
        Row(
          children: [
            Expanded(
              child: Text(
                '${_timeAgo(order.orderTime)} · ${_formatOrderTime(order.orderTime)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '￥${order.totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
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
      title: const Text('选择在线订单'),
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
          child: const Text('取消'),
        ),
      ],
    );
  }
}
