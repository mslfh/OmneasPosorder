import 'package:flutter/material.dart';
import 'dart:convert';
import '../../common/models/order_model.dart';
import '../../common/services/order_service.dart';

class OrderDetailPage extends StatefulWidget {
  final String orderId;

  const OrderDetailPage({Key? key, required this.orderId}) : super(key: key);

  @override
  _OrderDetailPageState createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  final OrderService _orderService = OrderService();
  OrderModel? _order;
  List<LogModel> _logs = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadOrderDetail();
  }

  Future<void> _loadOrderDetail() async {
    setState(() => _isLoading = true);

    try {
      final order = await _orderService.getOrderById(widget.orderId);
      final logs = await _orderService.getOrderLogs(widget.orderId);

      setState(() {
        _order = order;
        _logs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('加载订单详情失败: $e');
    }
  }

  Future<void> _retrySync() async {
    try {
      await _orderService.retrySyncOrder(widget.orderId);
      _showSuccessSnackBar('重新提交同步成功');
      await _loadOrderDetail();
    } catch (e) {
      _showErrorSnackBar('重新同步失败: $e');
    }
  }

  Future<void> _retryPrint() async {
    try {
      await _orderService.retryPrintOrder(widget.orderId);
      _showSuccessSnackBar('重新提交打印成功');
      await _loadOrderDetail();
    } catch (e) {
      _showErrorSnackBar('重新打印失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('订单详情'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadOrderDetail,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _order == null
              ? _buildNotFoundState()
              : SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildOrderInfoCard(),
                      SizedBox(height: 16),
                      _buildItemsCard(),
                      SizedBox(height: 16),
                      _buildStatusCard(),
                      SizedBox(height: 16),
                      _buildActionsCard(),
                      SizedBox(height: 16),
                      _buildLogsCard(),
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
            Text(
              '订单信息',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            _buildInfoRow('订单号', _order!.id),
            _buildInfoRow('下单时间', _formatDateTime(_order!.orderTime)),
            _buildInfoRow('总金额', '￥${_order!.totalAmount.toStringAsFixed(2)}'),
            if (_order!.syncedTime != null)
              _buildInfoRow('同步时间', _formatDateTime(_order!.syncedTime!)),
            if (_order!.printedTime != null)
              _buildInfoRow('打印时间', _formatDateTime(_order!.printedTime!)),
            if (_order!.retryCount > 0)
              _buildInfoRow('重试次数', '${_order!.retryCount}'),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsCard() {
    final items = jsonDecode(_order!.items) as List;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '菜品明细',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            ...items.map((item) => _buildItemRow(item)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '状态信息',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Text('订单状态: '),
                _buildStatusChip(
                  _getOrderStatusText(_order!.orderStatus),
                  _getOrderStatusColor(_order!.orderStatus),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Text('打印状态: '),
                _buildStatusChip(
                  _getPrintStatusText(_order!.printStatus),
                  _getPrintStatusColor(_order!.printStatus),
                ),
              ],
            ),
            if (_order!.errorMessage != null) ...[
              SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '错误信息:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      _order!.errorMessage!,
                      style: TextStyle(color: Colors.red[600]),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    final needsSyncRetry = _order!.orderStatus != OrderStatus.synced;
    final needsPrintRetry = _order!.printStatus != PrintStatus.printed;

    if (!needsSyncRetry && !needsPrintRetry) {
      return SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '操作',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                if (needsSyncRetry) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _retrySync,
                      icon: Icon(Icons.sync),
                      label: Text('重新同步'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  if (needsPrintRetry) SizedBox(width: 12),
                ],
                if (needsPrintRetry) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _retryPrint,
                      icon: Icon(Icons.print),
                      label: Text('重新打印'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '操作日志',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            if (_logs.isEmpty)
              Text('暂无日志记录', style: TextStyle(color: Colors.grey))
            else
              ..._logs.map((log) => _buildLogItem(log)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(dynamic item) {
    final name = item['name'] ?? '';
    final quantity = item['quantity'] ?? 1;
    final price = (item['price'] ?? 0).toDouble();
    final subtotal = quantity * price;
    final note = item['note'];

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Text('x$quantity'),
              SizedBox(width: 12),
              Text('￥${subtotal.toStringAsFixed(2)}'),
            ],
          ),
          if (note != null && note.toString().isNotEmpty) ...[
            SizedBox(height: 2),
            Text(
              '备注: $note',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildLogItem(LogModel log) {
    IconData icon;
    Color color;

    switch (log.action) {
      case 'order':
        icon = Icons.receipt;
        color = Colors.blue;
        break;
      case 'sync':
        icon = Icons.sync;
        color = log.status == 'success' ? Colors.green : Colors.orange;
        break;
      case 'print':
        icon = Icons.print;
        color = log.status == 'success' ? Colors.green : Colors.red;
        break;
      default:
        icon = Icons.info;
        color = Colors.grey;
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.message ?? '${log.action} - ${log.status}',
                  style: TextStyle(fontSize: 14),
                ),
                Text(
                  _formatDateTime(log.timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFoundState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            '订单不存在',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  String _getOrderStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return '待处理';
      case OrderStatus.pendingSync:
        return '待同步';
      case OrderStatus.confirmed:
        return '已确认';
      case OrderStatus.completed:
        return '已完成';
      case OrderStatus.cancelled:
        return '已取消';
      case OrderStatus.synced:
        return '已同步';
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
        return '待打印';
      case PrintStatus.printed:
        return '已打印';
      case PrintStatus.printFailed:
        return '打印失败';
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
