import 'package:flutter/material.dart';
import '../../common/models/menu_item.dart';
import '../../common/services/api_service.dart';
import '../utils/ui_helper.dart';

class SoldOutDialog {
  static Future<void> show({
    required BuildContext context,
    required MenuItem product,
    required VoidCallback onProductUpdated,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.no_meals, color: Colors.orange[800]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${product.title} - 沽清设置',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: product.isSoldOut ? Colors.red[50] : Colors.green[50],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: product.isSoldOut ? Colors.red[200]! : Colors.green[200]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    product.isSoldOut ? Icons.cancel : Icons.check_circle,
                    color: product.isSoldOut ? Colors.red : Colors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '当前状态：${product.isSoldOut ? "已沽清 (Sold Out)" : "正常在售"}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: product.isSoldOut ? Colors.red[800] : Colors.green[800],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('请选择沽清时长或恢复在售：',
                style: TextStyle(fontSize: 14, color: Colors.black87)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildSoldOutOptionTile(
                  context,
                  dialogContext,
                  product,
                  type: 'available',
                  label: '恢复在售',
                  icon: Icons.refresh,
                  color: Colors.green,
                  onProductUpdated: onProductUpdated,
                ),
                _buildSoldOutOptionTile(
                  context,
                  dialogContext,
                  product,
                  type: '4h',
                  label: '沽清 4 小时',
                  icon: Icons.timer,
                  color: Colors.orange,
                  onProductUpdated: onProductUpdated,
                ),
                _buildSoldOutOptionTile(
                  context,
                  dialogContext,
                  product,
                  type: 'today',
                  label: '今日沽清',
                  icon: Icons.today,
                  color: Colors.deepOrange,
                  onProductUpdated: onProductUpdated,
                ),
                _buildSoldOutOptionTile(
                  context,
                  dialogContext,
                  product,
                  type: 'this_week',
                  label: '本周沽清',
                  icon: Icons.date_range,
                  color: Colors.brown,
                  onProductUpdated: onProductUpdated,
                ),
                _buildSoldOutOptionTile(
                  context,
                  dialogContext,
                  product,
                  type: 'indefinite',
                  label: '永久沽清',
                  icon: Icons.block,
                  color: Colors.red,
                  onProductUpdated: onProductUpdated,
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  static Widget _buildSoldOutOptionTile(
    BuildContext context,
    BuildContext dialogContext,
    MenuItem product, {
    required String type,
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onProductUpdated,
  }) {
    return InkWell(
      onTap: () async {
        Navigator.pop(dialogContext);
        await _setProductSoldOut(context, product, type, onProductUpdated);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _setProductSoldOut(
    BuildContext context,
    MenuItem product,
    String type,
    VoidCallback onProductUpdated,
  ) async {
    try {
      final api = ApiService();
      await api.post('products/${product.id}/sold-out', data: {
        'type': type,
      });

      onProductUpdated();

      String msg;
      switch (type) {
        case 'available':
          msg = '${product.title} 已恢复在售';
          break;
        case '4h':
          msg = '${product.title} 已设置沽清 4 小时';
          break;
        case 'today':
          msg = '${product.title} 已设置今日沽清';
          break;
        case 'this_week':
          msg = '${product.title} 已设置本周沽清';
          break;
        case 'indefinite':
          msg = '${product.title} 已设置永久沽清';
          break;
        default:
          msg = '沽清状态已更新';
      }

      if (!context.mounted) return;
      UIHelper.showSnackBar(context, msg, backgroundColor: Colors.green);
    } catch (e) {
      if (!context.mounted) return;
      UIHelper.showSnackBar(context, '设置沽清失败: $e', backgroundColor: Colors.red);
    }
  }
}
