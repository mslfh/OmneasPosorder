import 'package:flutter/material.dart';

import '../../common/services/order_match_service.dart';
import '../services/order_match_manager.dart';

Future<void> showOrderMatchDetailsDialog({
  required BuildContext context,
  required OrderMatchResult result,
  Future<void> Function()? onRefresh,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        result.isMatched ? '✓ 订单匹配成功' : '✗ 订单不匹配',
        style: TextStyle(
          color: result.isMatched ? Colors.green : Colors.red,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OrderMatchUIBuilder.buildDetailsHeader(result),
            const SizedBox(height: 12),
            if (result.serverData != null) ...[
              OrderMatchUIBuilder.buildDataCard(
                title: '服务器数据',
                data: result.serverData!,
                accentColor: Colors.blue,
              ),
              const SizedBox(height: 12),
            ],
            if (result.localData != null) ...[
              OrderMatchUIBuilder.buildDataCard(
                title: '本地数据',
                data: result.localData!,
                accentColor: Colors.orange,
              ),
              const SizedBox(height: 12),
            ],
            if (result.getMismatchedItems().isNotEmpty) ...[
              const Text(
                '不匹配项',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              ...result.getMismatchedItems().map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item,
                          style: TextStyle(fontSize: 12, color: Colors.red[700]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Text(
                '所有字段均一致，无需修正。',
                style: TextStyle(fontSize: 12, color: Colors.green[700]),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
        if (onRefresh != null)
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await onRefresh();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('刷新'),
          ),
      ],
    ),
  );
}

