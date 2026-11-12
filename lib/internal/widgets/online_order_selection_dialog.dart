import 'package:flutter/material.dart';
import '../../common/models/order_model.dart';
import '../../common/services/order_service.dart';
import '../../common/services/language_service.dart';
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
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildPaymentStatusChip(bool isPaid) {
    final color = isPaid ? Colors.green : Colors.deepOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        isPaid ? '已支付' : '未支付',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildStatusChip(OrderStatus status) {
    final String label;
    final Color color;
    switch (status) {
      case OrderStatus.pending:
        label = 'status_pending'.tr;
        color = Colors.orange;
        break;
      case OrderStatus.confirmed:
        label = 'status_confirmed'.tr;
        color = Colors.blue;
        break;
      case OrderStatus.preparing:
        label = 'status_preparing'.tr;
        color = Colors.purple;
        break;
      case OrderStatus.readyForPickup:
        label = 'status_ready_for_pickup'.tr;
        color = Colors.teal;
        break;
      case OrderStatus.completed:
        label = 'status_completed'.tr;
        color = Colors.green;
        break;
      case OrderStatus.cancelled:
        label = 'status_cancelled'.tr;
        color = Colors.red;
        break;
      case OrderStatus.refunded:
        label = 'status_refunded'.tr;
        color = Colors.brown;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _handleNotifyOrderReady(OrderModel order) async {
    try {
      await _orderService.notifyOrderReadyForPickup(order);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('订单 #${order.orderNo} 菜品已做好，已通知顾客取餐！'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _ordersFuture = _orderService.getPendingOnlineOrders(date: _today);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('通知取餐失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _onOrderCardTap(OrderModel order) {
    if (order.isPaid) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('订单 #${order.orderNo} 已完成支付'),
          content: const Text('该订单已完成支付。您可选择直接通知顾客取餐，或将其载入点餐页进行加菜与修改。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('cancel'.tr),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(order);
              },
              icon: const Icon(Icons.edit_note, color: Colors.blue),
              label: const Text('修改/加菜'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _handleNotifyOrderReady(order);
              },
              icon: const Icon(Icons.notifications_active),
              label: const Text('通知取餐'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber[800],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    } else {
      Navigator.of(context).pop(order);
    }
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
            const SizedBox(width: 4),
            _buildPaymentStatusChip(order.isPaid),
            _buildStatusChip(order.orderStatus),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 14, color: Colors.orange[800]),
                      const SizedBox(width: 4),
                      Text(
                        '${'order_time'.tr}: ${_formatOrderTime(order.orderTime)}',
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
        if (itemNames.isNotEmpty)
          Text(
            '${'items'.tr}: ${itemNames.join(', ')}$extra',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        if (order.note != null && order.note!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '${'note'.tr}: ${order.note}',
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
          Expanded(child: Text('choose_order'.tr)),
          PopupMenuButton<OnlineOrderSortType>(
            icon: const Icon(Icons.sort, size: 22),
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
                            const Icon(Icons.check,
                                size: 18, color: Colors.orange)
                          else
                            const SizedBox(width: 18),
                          const SizedBox(width: 8),
                          Text(type.label,
                              style: const TextStyle(fontSize: 14)),
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
              return Center(
                  child: Text('${'conn_failed'.tr}: ${snapshot.error}'));
            }

            final rawOrders = snapshot.data ?? const <OrderModel>[];
            final ordersFiltered = rawOrders
                .where((o) => o.orderStatus != OrderStatus.cancelled)
                .toList();

            if (ordersFiltered.isEmpty) {
              return Center(child: Text('no_orders'.tr));
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
                    side: BorderSide(
                      color: order.isPaid
                          ? Colors.green.withOpacity(0.3)
                          : Colors.orange.withOpacity(0.18),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _onOrderCardTap(order),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: order.isPaid
                                  ? Colors.green.withOpacity(0.12)
                                  : Colors.orange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              order.isPaid
                                  ? Icons.check_circle_outline
                                  : Icons.cloud_done,
                              color: order.isPaid
                                  ? Colors.green[700]
                                  : Colors.orange[700],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: _buildOrderSummary(order)),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              Icons.notifications_active,
                              color: Colors.amber[800],
                              size: 26,
                            ),
                            tooltip: '菜品做好，通知取餐',
                            onPressed: () => _handleNotifyOrderReady(order),
                          ),
                          if (!order.isPaid)
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
          child: Text('cancel'.tr),
        ),
      ],
    );
  }
}
