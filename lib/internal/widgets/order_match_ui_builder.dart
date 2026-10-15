import 'package:flutter/material.dart';
import '../../common/services/order_match_service.dart';

/// 订单匹配UI渲染器
class OrderMatchUIBuilder {
  /// 获取匹配状态对应的图标颜色
  static Color getSeverityColor(OrderMatchSeverity severity) {
    switch (severity) {
      case OrderMatchSeverity.green:
        return Colors.green;
      case OrderMatchSeverity.orange:
        return Colors.orange[800]!;
      case OrderMatchSeverity.red:
        return Colors.red;
    }
  }

  /// 获取匹配状态对应的图标
  static IconData getSeverityIcon(OrderMatchSeverity severity) {
    switch (severity) {
      case OrderMatchSeverity.green:
        return Icons.verified;
      case OrderMatchSeverity.orange:
        return Icons.warning_amber_rounded;
      case OrderMatchSeverity.red:
        return Icons.error_outline;
    }
  }

  /// 构建数据行
  static Widget buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建详情头部
  static Widget buildDetailsHeader(OrderMatchResult result) {
    final color = getSeverityColor(result.severity);
    final icon = getSeverityIcon(result.severity);

    String statusText = '当天订单数据完全匹配';
    if (result.severity == OrderMatchSeverity.red) {
      statusText = '当天订单存在未落单或数据异常';
    } else if (result.severity == OrderMatchSeverity.orange) {
      statusText = '当天订单存在未同步到服务器的数据';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          buildDataRow('匹配总数', result.totalCount.toString()),
          buildDataRow('正常一致', result.normalCount.toString()),
          buildDataRow('未拉本地 (重大失误)', result.missingInLocalCount.toString()),
          buildDataRow('未同步服务器', result.missingInServerCount.toString()),
          buildDataRow('数据对比异常', result.dataMismatchCount.toString()),
          const SizedBox(height: 4),
          Text(
            '检查时间: ${result.lastCheckTime.toString().split('.')[0]}',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          if (result.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              result.errorMessage!,
              style: const TextStyle(fontSize: 11, color: Colors.red),
            ),
          ],
        ],
      ),
    );
  }
}
