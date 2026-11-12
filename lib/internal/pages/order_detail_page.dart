import 'package:flutter/material.dart';
import '../../common/models/order_model.dart';
import '../../common/models/server_order_model.dart';
import '../../common/services/order_service.dart';
import '../../common/services/order_match_service.dart';
import '../../common/services/print_service.dart';
import '../../common/services/language_service.dart';

class OrderDetailPage extends StatefulWidget {
  final String orderId;

  const OrderDetailPage({super.key, required this.orderId});

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  final OrderService _orderService = OrderService();
  OrderModel? _order;
  ServerOrderModel? _serverOrder;
  List<LogModel> _logs = [];
  bool _isLoading = false;
  int _selectedItemSourceIndex = 0; // 0: 本地菜品, 1: 服务器菜品

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

      ServerOrderModel? serverOrder;
      if (order != null) {
        try {
          final serverOrders =
              await _orderService.fetchServerOrders(date: order.orderTime);
          for (final s in serverOrders) {
            if ((order.remoteOrderId != null && order.remoteOrderId == s.id) ||
                (order.remoteOrderNumber != null &&
                    order.remoteOrderNumber!.isNotEmpty &&
                    order.remoteOrderNumber == s.orderNumber) ||
                (order.orderNo.isNotEmpty && order.orderNo == s.orderNo)) {
              serverOrder = s;
              break;
            }
          }
        } catch (e) {
          debugPrint('获取关联服务器订单失败: $e');
        }
      }

      setState(() {
        _order = order;
        _serverOrder = serverOrder;
        _logs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('${'conn_failed'.tr}: $e');
    }
  }

  Future<void> _retrySync() async {
    try {
      await _orderService.retrySyncOrderToRemote(widget.orderId);
      _showSuccessSnackBar('conn_success'.tr);
      await _loadOrderDetail();
    } catch (e) {
      _showErrorSnackBar('${'conn_failed'.tr}: $e');
    }
  }

  Future<void> _retryPrint() async {
    try {
      await _orderService.retryPrintOrder(widget.orderId);
      _showSuccessSnackBar('printer_success'.tr);
      await _loadOrderDetail();
    } catch (e) {
      _showErrorSnackBar('printer_failed'.tr + ': $e');
    }
  }

  Future<void> _showEditStatusDialog() async {
    if (_order == null) return;
    OrderStatus selectedOrderStatus = _order!.orderStatus;
    PrintStatus selectedPrintStatus = _order!.printStatus;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('edit'.tr + ' ' + 'order_status'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('order_status'.tr + ':',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<OrderStatus>(
                value: selectedOrderStatus,
                isExpanded: true,
                items: OrderStatus.values.map((status) {
                  return DropdownMenuItem(
                    value: status,
                    child: Text(_getOrderStatusText(status)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedOrderStatus = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              Text('print_status'.tr + ':',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<PrintStatus>(
                value: selectedPrintStatus,
                isExpanded: true,
                items: PrintStatus.values.map((status) {
                  return DropdownMenuItem(
                    value: status,
                    child: Text(_getPrintStatusText(status)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedPrintStatus = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel'.tr),
            ),
            ElevatedButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                try {
                  await _orderService.updateStatus(
                    widget.orderId,
                    orderStatus: selectedOrderStatus,
                    printStatus: selectedPrintStatus,
                  );
                  if (!mounted) return;
                  nav.pop();
                  _showSuccessSnackBar('confirm'.tr);
                  _loadOrderDetail();
                } catch (e) {
                  _showErrorSnackBar('${'conn_failed'.tr}: $e');
                }
              },
              child: Text('save'.tr),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('order_detail'.tr),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrderDetail,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _order == null
              ? _buildNotFoundState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 0. 堂食坐台单 Banner
                      _buildTableOrderBanner(),

                      // 1. 数据核对状态 Banner
                      _buildHeaderMatchBanner(),
                      const SizedBox(height: 16),

                      // 2. 本地与服务器基本信息对比卡片
                      _buildOrderInfoComparisonCard(),
                      const SizedBox(height: 16),

                      // 3. 服务器订单扩展详情卡片
                      if (_serverOrder != null) ...[
                        _buildServerDetailsCard(),
                        const SizedBox(height: 16),
                      ],

                      // 4. 本地与服务器菜品对比卡片
                      _buildItemsComparisonCard(),
                      const SizedBox(height: 16),

                      // 4. 状态卡片
                      _buildStatusCard(),
                      const SizedBox(height: 16),

                      // 5. 操作卡片
                      _buildActionsCard(),
                      const SizedBox(height: 16),

                      // 6. 日志卡片
                      _buildLogsCard(),
                    ],
                  ),
                ),
    );
  }

  // 0. 堂食坐台单 Banner
  Widget _buildTableOrderBanner() {
    final local = _order!;
    final tableName = local.tableName ?? (local.isTableOrder ? '堂食坐台' : null);
    if (tableName == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade400, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(Icons.table_restaurant, color: Colors.amber[900], size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '堂食坐台订单：$tableName',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.amber[900],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber[800],
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              '坐台单',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 1. 数据核对状态提示 Banner
  Widget _buildHeaderMatchBanner() {
    final local = _order!;
    final server = _serverOrder;

    if (server == null) {
      if (local.syncStatus == SyncStatus.synced) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '已标记同步，但当前离线或暂未查询到关联服务器记录',
                  style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
        );
      } else {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange[300]!),
          ),
          child: Row(
            children: [
              const Icon(Icons.sync_problem, color: Colors.orange),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '【未同步】该订单仅存在于本地，尚未推送到服务器',
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              ElevatedButton(
                onPressed: _retrySync,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('立刻同步', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        );
      }
    }

    final mismatches = OrderMatchService.compareOrderData(local, server);

    if (mismatches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green[300]!),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '✓ 本地数据与服务器数据完全一致',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber[400]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber[900]),
                const SizedBox(width: 8),
                Text(
                  '⚠️ 本地与服务器数据存在差异 (${mismatches.length}项)',
                  style: TextStyle(color: Colors.amber[900], fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...mismatches.map((msg) => Padding(
                  padding: const EdgeInsets.only(left: 28, top: 2),
                  child: Text('• $msg',
                      style: TextStyle(color: Colors.red[800], fontSize: 12)),
                )),
          ],
        ),
      );
    }
  }

  // 2. 本地与服务器基本信息对比卡片
  Widget _buildOrderInfoComparisonCard() {
    final local = _order!;
    final server = _serverOrder;

    final serverAmount = server != null ? double.tryParse(server.finalAmount) ?? 0.0 : null;
    final isAmountMismatch = serverAmount != null && (local.totalAmount - serverAmount).abs() > 0.01;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '订单数据对比 (Order Contrast)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (server != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Text(
                      '来源: ${server.placeIn.toUpperCase()}',
                      style: TextStyle(fontSize: 10, color: Colors.blue[800], fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _buildComparisonHeaderRow(),
            const Divider(height: 16),
            _buildComparisonRow(
              '订单编号',
              local.orderNo,
              server?.orderNo ?? '-',
            ),
            _buildComparisonRow(
              '服务器单号',
              local.remoteOrderNumber ?? '-',
              server?.orderNumber ?? '-',
            ),
            _buildComparisonRow(
              '总金额',
              '￥${local.totalAmount.toStringAsFixed(2)}',
              serverAmount != null ? '￥${serverAmount.toStringAsFixed(2)}' : '-',
              isDiff: isAmountMismatch,
            ),
            _buildComparisonRow(
              '订单来源/场景',
              local.displayOrderSource,
              server != null
                  ? '${server.placeIn.toUpperCase()} / ${server.type.toUpperCase()}'
                  : '-',
              ignoreDiff: true,
            ),
            _buildComparisonRow(
              '下单时间',
              _formatDateTime(local.orderTime),
              server?.orderTime != null ? _formatDateTime(server!.orderTime!) : (server?.createdAt ?? '-'),
            ),
            if (local.note != null || server?.note != null || server?.remark != null)
              _buildComparisonRow(
                '备注说明',
                local.note ?? '-',
                '${server?.note ?? ''} ${server?.remark ?? ''}'.trim().isEmpty
                    ? '-'
                    : '${server?.note ?? ''} ${server?.remark ?? ''}'.trim(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonHeaderRow() {
    return Row(
      children: [
        const Expanded(
          flex: 3,
          child: Text('字段名', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
        ),
        Expanded(
          flex: 4,
          child: Text('本地数据库 (Local)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue[800])),
        ),
        Expanded(
          flex: 4,
          child: Text('服务器数据 (Server)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green[800])),
        ),
      ],
    );
  }

  Widget _buildComparisonRow(String label, String localVal, String serverVal,
      {bool isDiff = false, bool ignoreDiff = false}) {
    final bool textDiff = !ignoreDiff &&
        (isDiff ||
            (serverVal != '-' &&
                localVal.toLowerCase() != serverVal.toLowerCase()));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: textDiff ? Colors.red[50] : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: textDiff ? Colors.red[900] : Colors.grey[700],
                fontWeight: textDiff ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              localVal,
              style: TextStyle(
                fontSize: 12,
                fontWeight: textDiff ? FontWeight.bold : FontWeight.w500,
                color: textDiff ? Colors.red[900] : Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              serverVal,
              style: TextStyle(
                fontSize: 12,
                fontWeight: textDiff ? FontWeight.bold : FontWeight.w500,
                color: textDiff ? Colors.red[900] : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 3. 菜品项对比卡片
  Widget _buildItemsComparisonCard() {
    final localItems = _order?.getItemsList() ?? [];
    final serverItems = _serverOrder?.items ?? [];

    final isSameCount = localItems.length == serverItems.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '菜品明细对比',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (_serverOrder != null)
                  Text(
                    isSameCount
                        ? '菜品项数一致 (${localItems.length}项)'
                        : '项数不符 (本地${localItems.length}项 / 服务器${serverItems.length}项)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSameCount ? Colors.green[700] : Colors.red,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (_serverOrder != null) ...[
              // 标签切换展示本地菜品或服务器菜品
              Row(
                children: [
                  ChoiceChip(
                    label: Text('本地菜品 (${localItems.length})', style: const TextStyle(fontSize: 12)),
                    selected: _selectedItemSourceIndex == 0,
                    onSelected: (_) => setState(() => _selectedItemSourceIndex = 0),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('服务器菜品 (${serverItems.length})', style: const TextStyle(fontSize: 12)),
                    selected: _selectedItemSourceIndex == 1,
                    onSelected: (_) => setState(() => _selectedItemSourceIndex = 1),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            if (_selectedItemSourceIndex == 0) ...[
              if (localItems.isEmpty)
                Text('no_data'.tr, style: const TextStyle(color: Colors.grey))
              else
                ...localItems.map((item) => _buildLocalItemRow(item)),
            ] else ...[
              if (serverItems.isEmpty)
                Text('no_data'.tr, style: const TextStyle(color: Colors.grey))
              else
                ...serverItems.map((item) => _buildServerItemRow(item)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _printSingleItem(Map<String, dynamic> itemMap) async {
    if (_order == null) return;
    final name = (itemMap['name'] ?? itemMap['product_title'] ?? itemMap['product_name'] ?? '菜品').toString();
    final quantity = _toInt(itemMap['quantity'] ?? itemMap['count']) ?? 1;

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.print, color: Colors.blue),
              SizedBox(width: 8),
              Text('单品补打小票'),
            ],
          ),
          content: Text('是否打印单品小票 [$name x$quantity] 并发送至后厨/收银打单站？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text('cancel'.tr),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.print, size: 16),
              label: const Text('确认打单'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('正在补打单品 [$name] 小票...'),
          duration: const Duration(seconds: 1),
        ),
      );

      final printService = PrintService();
      await printService.printSingleItem(order: _order!, targetItem: itemMap);

      if (!mounted) return;
      _showSuccessSnackBar('单品 [$name] 小票已成功发送至打印机！');
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('打印单品失败: $e');
    }
  }

  List<Map<String, dynamic>> _extractItemOptions(Map<String, dynamic> itemMap) {
    final rawOptions = itemMap['options'] ??
        itemMap['customization'] ??
        itemMap['option_items'] ??
        itemMap['options_list'] ??
        itemMap['customizations'];
    if (rawOptions is! List || rawOptions.isEmpty) return [];

    final List<Map<String, dynamic>> result = [];
    for (final opt in rawOptions) {
      if (opt is Map) {
        final mapObj = opt['option'] is Map
            ? Map<String, dynamic>.from(opt['option'] as Map)
            : Map<String, dynamic>.from(opt);
        final name = (mapObj['option_name'] ??
                mapObj['ingredientName'] ??
                mapObj['replacementName'] ??
                mapObj['name'] ??
                mapObj['title'] ??
                '')
            .toString();
        final extraPrice = _toDouble(
              mapObj['extra_price'] ??
                  mapObj['priceChange'] ??
                  mapObj['extra_cost'] ??
                  mapObj['extraCost'] ??
                  mapObj['extra'] ??
                  mapObj['price'],
            ) ??
            0.0;
        if (name.isNotEmpty) {
          result.add({
            'name': name,
            'price': extraPrice,
          });
        }
      } else if (opt != null) {
        final str = opt.toString().trim();
        if (str.isNotEmpty) {
          result.add({
            'name': str,
            'price': 0.0,
          });
        }
      }
    }
    return result;
  }

  Widget _buildLocalItemRow(Map<String, dynamic> itemMap) {
    final name = (itemMap['name'] ?? itemMap['product_title'] ?? itemMap['product_name'] ?? '').toString();
    final quantity = _toInt(itemMap['quantity']) ?? 1;
    final price = _toDouble(itemMap['price'] ?? itemMap['product_selling_price'] ?? itemMap['unit_price']) ?? 0.0;
    final finalAmount = _toDouble(itemMap['final_amount']);
    final subtotal = finalAmount ?? (quantity * price);
    final options = _extractItemOptions(itemMap);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '$name (\$$price)',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Text('x$quantity'),
              const SizedBox(width: 12),
              Text('\$${subtotal.toStringAsFixed(2)}'),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.print_outlined, size: 18, color: Colors.blue),
                tooltip: '单品打 / 补打小票',
                onPressed: () => _printSingleItem(itemMap),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          if (options.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: options.map((opt) {
                  final optName = opt['name'] as String;
                  final optPrice = opt['price'] as double;
                  return Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Row(
                      children: [
                        Text(
                          '• $optName',
                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                        if (optPrice > 0) ...[
                          const SizedBox(width: 4),
                          Text(
                            '(+￥${optPrice.toStringAsFixed(2)})',
                            style: TextStyle(fontSize: 11, color: Colors.orange[800]),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildServerItemRow(dynamic item) {
    if (item is! Map) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(item.toString()),
      );
    }
    final itemMap = Map<String, dynamic>.from(item);
    final name = (itemMap['product_title'] ?? itemMap['name'] ?? itemMap['product_name'] ?? '').toString();
    final quantity = _toInt(itemMap['quantity'] ?? itemMap['count']) ?? 1;
    final price = _toDouble(itemMap['product_selling_price'] ?? itemMap['unit_price'] ?? itemMap['price'] ?? itemMap['selling_price']) ?? 0.0;
    final finalAmount = _toDouble(itemMap['final_amount']);
    final subtotal = finalAmount ?? (quantity * price);
    final options = _extractItemOptions(itemMap);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Text('x$quantity'),
              const SizedBox(width: 12),
              Text('￥${subtotal.toStringAsFixed(2)}'),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.print_outlined, size: 18, color: Colors.blue),
                tooltip: '单品打 / 补打小票',
                onPressed: () => _printSingleItem(itemMap),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          if (options.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: options.map((opt) {
                  final optName = opt['name'] as String;
                  final optPrice = opt['price'] as double;
                  return Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Row(
                      children: [
                        Text(
                          '• $optName',
                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                        if (optPrice > 0) ...[
                          const SizedBox(width: 4),
                          Text(
                            '(+￥${optPrice.toStringAsFixed(2)})',
                            style: TextStyle(fontSize: 11, color: Colors.orange[800]),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // 4. 状态与快捷编辑卡片
  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '订单与同步状态概览',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                  onPressed: _showEditStatusDialog,
                  tooltip: 'edit'.tr,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 本地订单状态与支付标识
            Row(
              children: [
                const Text('本地订单状态: ', style: TextStyle(fontWeight: FontWeight.w600)),
                _buildStatusChip(
                  _getOrderStatusText(_order!.orderStatus),
                  _getOrderStatusColor(_order!.orderStatus),
                ),
                const SizedBox(width: 8),
                _buildStatusChip(
                  _order!.isPaid ? '已支付' : '未支付 (到店付)',
                  _order!.isPaid ? Colors.green : Colors.deepOrange,
                ),
              ],
            ),
            // 服务器订单状态与支付标识
            if (_serverOrder != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('服务器订单状态: ', style: TextStyle(fontWeight: FontWeight.w600)),
                  _buildStatusChip(
                    '${_serverOrder!.status.toUpperCase()} (${_getOrderStatusText(_serverOrder!.orderStatusEnum)})',
                    _serverOrder!.status.toLowerCase() == 'completed'
                        ? Colors.green
                        : (_serverOrder!.status.toLowerCase() == 'cancelled' ? Colors.red : Colors.blue),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusChip(
                    _serverOrder!.isPaid ? '已支付' : '未支付 (到店付)',
                    _serverOrder!.isPaid ? Colors.green : Colors.deepOrange,
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('服务器订单状态: ', style: TextStyle(fontWeight: FontWeight.w600)),
                  _buildStatusChip('未连接/离线单', Colors.grey),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Text('${'sync_status'.tr}: '),
                _buildStatusChip(
                  _getSyncStatusText(_order!.syncStatus),
                  _getSyncStatusColor(_order!.syncStatus),
                ),
                const SizedBox(width: 16),
                Text('${'print_status'.tr}: '),
                _buildStatusChip(
                  _getPrintStatusText(_order!.printStatus),
                  _getPrintStatusColor(_order!.printStatus),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _editAndAddItemsForOnlineOrder() {
    if (_order == null) return;
    Navigator.of(context).pop(_order);
  }

  // 5. 操作卡片
  Widget _buildActionsCard() {
    final isOnline = _order?.isOnlineOrder ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('订单操作', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (isOnline) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _editAndAddItemsForOnlineOrder,
                  icon: const Icon(Icons.edit_note, size: 20),
                  label: const Text('修改订单 / 加菜 (载入点餐页)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _retrySync,
                    icon: const Icon(Icons.sync),
                    label: Text('resync'.tr),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _retryPrint,
                    icon: const Icon(Icons.print),
                    label: Text('reprint'.tr),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
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

  // 6. 操作日志卡片
  Widget _buildLogsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('操作日志记录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_logs.isEmpty)
              Text('no_data'.tr, style: const TextStyle(color: Colors.grey))
            else
              ..._logs.map((log) => _buildLogItem(log)),
          ],
        ),
      ),
    );
  }

  // 服务器订单扩展详情卡片
  Widget _buildServerDetailsCard() {
    final server = _serverOrder;
    if (server == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_outlined, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  '服务器订单扩展数据 (Server Details)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    'ID: ${server.id}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // 仅当 additions 不为空时，解析并显示 additions 字段中的顾客及扩展元数据
            if (server.additions.isNotEmpty) ...[
              _buildAdditionsCardSection(server.additions),
            ],

            _buildGridDetailRows([
              _DetailItem('服务器 ID', '#${server.id}'),
              _DetailItem(
                  '服务器完整单号',
                  server.orderNumber.isNotEmpty
                      ? server.orderNumber
                      : '-'),
              _DetailItem('下单渠道 / 场景', server.placeIn.toUpperCase()),
              _DetailItem('订单标签', server.tag ?? '-'),
              _DetailItem(
                  '下单/预约时间',
                  server.orderTime != null
                      ? _formatDateTime(server.orderTime!)
                      : (server.createdAt ?? '-')),
              _DetailItem('服务端同步时间', server.syncedAt ?? '-'),
            ]),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '服务器财务与计费明细',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  _buildGridDetailRows([
                    _DetailItem('商品原价', '￥${server.totalAmount}'),
                    _DetailItem('折扣金额', '￥${server.discountAmount}'),
                    _DetailItem('税率 / 税额',
                        '${server.taxRate}% (￥${server.taxAmount})'),
                    _DetailItem('应收金额', '￥${server.finalAmount}',
                        isBold: true),
                    _DetailItem('实付金额', '￥${server.paidAmount}'),
                    _DetailItem('支付方式', server.paymentMethod ?? '-'),
                  ]),
                ],
              ),
            ),

            if ((server.note != null && server.note!.trim().isNotEmpty) ||
                (server.remark != null &&
                    server.remark!.trim().isNotEmpty)) ...[
              const SizedBox(height: 12),
              if (server.note != null && server.note!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('顾客备注: ${server.note}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black87)),
                ),
              if (server.remark != null && server.remark!.trim().isNotEmpty)
                Text('系统/内部备注: ${server.remark}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade700)),
            ],

            if (server.payments.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('支付记录明细:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              ...server.payments.map((p) => _buildPaymentRow(p)),
            ],
          ],
        ),
      ),
    );
  }

  /// 解析并展示 additions 字段中的顾客元数据及附加字段
  Widget _buildAdditionsCardSection(List<dynamic> additions) {
    if (additions.isEmpty) return const SizedBox.shrink();

    final additionItems = <_DetailItem>[];
    final customAdditions = <Widget>[];

    for (final item in additions) {
      if (item is Map) {
        item.forEach((key, value) {
          if (value == null || value.toString().trim().isEmpty) return;

          final keyStr = key.toString();
          final valStr = value.toString().trim();

          switch (keyStr) {
            case 'customer_name':
              additionItems.add(_DetailItem('顾客姓名', valStr));
              break;
            case 'customer_phone':
              additionItems.add(_DetailItem('联系电话', valStr));
              break;
            case 'pickup_time':
              additionItems.add(_DetailItem('取餐/预约时间', valStr));
              break;
            case 'extend_info':
              additionItems.add(_DetailItem('扩展/座位信息', valStr));
              break;
            default:
              final label = keyStr
                  .replaceAll('_', ' ')
                  .split(' ')
                  .map((w) => w.isNotEmpty
                      ? '${w[0].toUpperCase()}${w.substring(1)}'
                      : '')
                  .join(' ');
              additionItems.add(_DetailItem(label, valStr));
          }
        });
      } else {
        customAdditions.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('• ${item.toString()}',
                style: const TextStyle(fontSize: 12)),
          ),
        );
      }
    }

    if (additionItems.isEmpty && customAdditions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, size: 16, color: Colors.blue.shade800),
              const SizedBox(width: 6),
              Text(
                '顾客及附加信息 (Additions)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.blue.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (additionItems.isNotEmpty) _buildGridDetailRows(additionItems),
          if (customAdditions.isNotEmpty) ...[
            if (additionItems.isNotEmpty) const SizedBox(height: 6),
            ...customAdditions,
          ],
        ],
      ),
    );
  }

  Widget _buildGridDetailRows(List<_DetailItem> items) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: items.map((item) {
        return SizedBox(
          width: 160,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 2),
              Text(
                item.value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: item.isBold ? FontWeight.bold : FontWeight.w500,
                  color: item.isBold ? Colors.blue.shade900 : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPaymentRow(dynamic p) {
    if (p is! Map) {
      return Text('• ${p.toString()}', style: const TextStyle(fontSize: 12));
    }
    final method = p['method'] ?? p['payment_method'] ?? '支付';
    final amount = p['amount'] ?? p['paid_amount'] ?? '0.00';
    final status = p['status'] ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.payment, size: 14, color: Colors.green.shade700),
          const SizedBox(width: 6),
          Text('$method: ￥$amount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          if (status.toString().isNotEmpty) ...[
            const SizedBox(width: 8),
            Text('($status)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ],
      ),
    );
  }

  Widget _buildAdditionRow(dynamic a) {
    if (a is! Map) {
      return Text('• ${a.toString()}', style: const TextStyle(fontSize: 12));
    }
    final title = a['title'] ?? a['name'] ?? '附加费用';
    final amount = a['amount'] ?? a['price'] ?? '0.00';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.add_circle_outline, size: 14, color: Colors.orange),
          const SizedBox(width: 6),
          Text('$title: ￥$amount', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildLogItem(LogModel log) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              log.message ?? '${log.action} - ${log.status}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            _formatDateTime(log.timestamp),
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  Widget _buildNotFoundState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'no_data'.tr,
            style: const TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _getOrderStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'status_pending'.tr;
      case OrderStatus.confirmed:
        return 'status_confirmed'.tr;
      case OrderStatus.preparing:
        return 'status_preparing'.tr;
      case OrderStatus.readyForPickup:
        return 'status_ready_for_pickup'.tr;
      case OrderStatus.completed:
        return 'status_completed'.tr;
      case OrderStatus.cancelled:
        return 'status_cancelled'.tr;
      case OrderStatus.refunded:
        return 'status_refunded'.tr;
    }
  }

  Color _getOrderStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.blue;
      case OrderStatus.preparing:
        return Colors.purple;
      case OrderStatus.readyForPickup:
        return Colors.teal;
      case OrderStatus.completed:
        return Colors.green;
      case OrderStatus.cancelled:
        return Colors.red;
      case OrderStatus.refunded:
        return Colors.brown;
    }
  }

  String _getSyncStatusText(SyncStatus status) {
    switch (status) {
      case SyncStatus.pending:
        return 'status_pending'.tr;
      case SyncStatus.synced:
        return 'status_active'.tr;
      case SyncStatus.syncFailed:
        return 'conn_failed'.tr;
      case SyncStatus.skipped:
        return 'status_inactive'.tr;
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
    if (status == PrintStatus.pending) return 'status_pending'.tr;
    if (status == PrintStatus.printed) return 'status_active'.tr;
    if (status == PrintStatus.printFailed) return 'printer_failed'.tr;
    return 'status_inactive'.tr;
  }

  Color _getPrintStatusColor(PrintStatus status) {
    if (status == PrintStatus.pending) return Colors.grey;
    if (status == PrintStatus.printed) return Colors.green;
    if (status == PrintStatus.printFailed) return Colors.red;
    return Colors.grey;
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

class _DetailItem {
  final String label;
  final String value;
  final bool isBold;

  const _DetailItem(this.label, this.value, {this.isBold = false});
}
