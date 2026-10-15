import 'package:flutter/material.dart';

import '../../common/services/order_match_service.dart';
import '../../common/services/language_service.dart';
import 'order_match_ui_builder.dart';

Future<void> showOrderMatchDetailsDialog({
  required BuildContext context,
  required OrderMatchResult result,
  VoidCallback? onNavigateToOrderList,
  Future<void> Function()? onRefresh,
}) async {
  final color = OrderMatchUIBuilder.getSeverityColor(result.severity);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        result.isMatched ? '✓ ${'matched'.tr}' : '✗ ${'mismatched'.tr}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OrderMatchUIBuilder.buildDetailsHeader(result),
            const SizedBox(height: 12),
            if (result.getMismatchedItems().isNotEmpty) ...[
              Text(
                'mismatched'.tr,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              ...result.getMismatchedItems().map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, size: 16, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item,
                          style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Text(
                'matched'.tr,
                style: TextStyle(fontSize: 12, color: Colors.green[700]),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('cancel'.tr),
        ),
        if (onNavigateToOrderList != null)
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              onNavigateToOrderList();
            },
            icon: const Icon(Icons.receipt_long, size: 16),
            label: const Text('前往订单管理'),
          ),
      ],
    ),
  );
}
