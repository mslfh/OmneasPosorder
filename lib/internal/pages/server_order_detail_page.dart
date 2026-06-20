import 'package:flutter/material.dart';
import 'dart:convert';
import '../../common/models/server_order_model.dart';
import '../../common/services/order_service.dart';

class ServerOrderDetailPage extends StatefulWidget {
  final ServerOrderModel order;

  const ServerOrderDetailPage({Key? key, required this.order}) : super(key: key);

  @override
  _ServerOrderDetailPageState createState() => _ServerOrderDetailPageState();
}

class _ServerOrderDetailPageState extends State<ServerOrderDetailPage> {
  final OrderService _orderService = OrderService();
  late ServerOrderModel _order;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  Future<void> _pullOrder() async {
    setState(() => _isLoading = true);
    try {
      await _orderService.pullServerOrderToLocal(_order);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('订单拉取成功'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('拉取失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _reprint() async {
    try {
      await _orderService.reprintServerOrder(_order);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打印指令已发送'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打印失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('服务器订单详情'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOrderInfoCard(),
                  SizedBox(height: 16),
                  _buildItemsCard(),
                  SizedBox(height: 16),
                  _buildCustomerInfoCard(),
                  SizedBox(height: 16),
                  _buildActionsCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildOrderInfoCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('基本信息', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Divider(),
            _buildInfoRow('订单全号', _order.orderNumber),
            _buildInfoRow('订单短号', _order.orderNo),
            _buildInfoRow('来源', _order.placeIn.toUpperCase()),
            _buildInfoRow('类型', _order.type.toUpperCase()),
            _buildInfoRow('状态', _order.status.toUpperCase()),
            _buildInfoRow('下单时间', _order.orderTime?.toString() ?? '-'),
            _buildInfoRow('总金额', '\$${_order.finalAmount}'),
            _buildInfoRow('同步状态', _order.syncStatus),
            _buildInfoRow('打印状态', _order.printStatus),
            if (_order.note != null && _order.note!.isNotEmpty)
              _buildInfoRow('备注', _order.note!),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('菜品清单', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Divider(),
            ..._order.items.map((item) {
              final title = item['product_title'] ?? 'Unknown';
              final qty = item['quantity'] ?? 1;
              final price = item['final_amount'] ?? '0.00';
              final customizations = item['customization'] as List? ?? [];

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w600))),
                        Text('x$qty'),
                        SizedBox(width: 16),
                        Text('\$$price'),
                      ],
                    ),
                    if (customizations.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 12.0, top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: customizations.map((c) {
                            String desc = '';
                            if (c['type'] == 'replacement') {
                              desc = '${c['originalName']} -> ${c['replacementName']}';
                            } else if (c['type'] == 'quantity') {
                              desc = '${c['ingredientName']} (Qty: ${c['currentQuantity']})';
                            }
                            return Text('• $desc', style: TextStyle(fontSize: 12, color: Colors.grey[600]));
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerInfoCard() {
    if (_order.additions.isEmpty) return SizedBox.shrink();
    final addition = _order.additions.first;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('客户信息', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Divider(),
            _buildInfoRow('姓名', addition['customer_name'] ?? '-'),
            _buildInfoRow('电话', addition['customer_phone'] ?? '-'),
            _buildInfoRow('取餐时间', addition['pickup_time'] ?? '-'),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _pullOrder,
                icon: Icon(Icons.download),
                label: Text('拉取到本地'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _reprint,
                icon: Icon(Icons.print),
                label: Text('重新打印'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text('$label:', style: TextStyle(color: Colors.grey[600]))),
          Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
