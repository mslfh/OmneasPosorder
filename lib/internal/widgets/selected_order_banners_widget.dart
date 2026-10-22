import 'package:flutter/material.dart';
import '../../common/models/dining_table.dart';
import '../../common/models/order_model.dart';
import '../utils/order_selected.dart';

class SelectedTableBannerWidget extends StatelessWidget {
  final DiningTable? table;
  final bool isTableOrderExisting;
  final VoidCallback onChangeTable;
  final VoidCallback onClearTable;

  const SelectedTableBannerWidget({
    super.key,
    required this.table,
    required this.isTableOrderExisting,
    required this.onChangeTable,
    required this.onClearTable,
  });

  @override
  Widget build(BuildContext context) {
    final currentTable = table;
    if (currentTable == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade400, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(Icons.table_restaurant, color: Colors.amber[900]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '已关联桌台：${currentTable.name}${currentTable.area != null && currentTable.area!.isNotEmpty ? ' (${currentTable.area})' : ''}  ${isTableOrderExisting ? "[堂食坐台单]" : "[开台点餐]"}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.amber[900],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          OutlinedButton(
            onPressed: onChangeTable,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('换桌', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: Colors.amber[900],
            onPressed: onClearTable,
          ),
        ],
      ),
    );
  }
}

class SelectedOnlineOrderBannerWidget extends StatelessWidget {
  final OrderModel? order;
  final List<SelectedProduct> originalProducts;

  const SelectedOnlineOrderBannerWidget({
    super.key,
    required this.order,
    required this.originalProducts,
  });

  @override
  Widget build(BuildContext context) {
    final currentOrder = order;
    if (currentOrder == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_done, color: Colors.orange[700]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '已添加在线订单：${currentOrder.orderNo}${currentOrder.remoteOrderNumber != null ? ' / ${currentOrder.remoteOrderNumber}' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '${originalProducts.length} items',
            style: TextStyle(color: Colors.orange[800]),
          ),
        ],
      ),
    );
  }
}
