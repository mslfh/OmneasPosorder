import 'package:flutter/material.dart';
import '../../common/services/language_service.dart';

class OrderActionBarWidget extends StatelessWidget {
  final VoidCallback onVoidOrder;
  final VoidCallback onClearOrder;
  final VoidCallback onShowQuantitySelector;
  final VoidCallback onCustomAction;
  final VoidCallback? onOrder;
  final VoidCallback? onSelectQuickInput;
  final bool showQuickSelectButton;
  final bool isQuickSearchActive;
  final int orderedCount;
  final bool orderEnabled;
  final String orderLabel;
  final IconData orderIcon;
  final Color orderColor;

  const OrderActionBarWidget({
    Key? key,
    required this.onVoidOrder,
    required this.onClearOrder,
    required this.onShowQuantitySelector,
    required this.onCustomAction,
    required this.onOrder,
    required this.orderedCount,
    required this.orderEnabled,
    this.orderLabel = 'ORDER',
    this.orderIcon = Icons.shopping_cart,
    this.orderColor = Colors.green,
    this.onSelectQuickInput,
    this.showQuickSelectButton = false,
    this.isQuickSearchActive = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60.0,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.grey[200]!, Colors.grey[300]!],
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      child: Row(
        children: [
          // VOID / 删除按钮
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3.0),
              child: ElevatedButton.icon(
                onPressed: onVoidOrder,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text('delete'.tr.toUpperCase(),
                    style:
                        const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[300],
                  foregroundColor: Colors.white,
                  elevation: 3,
                  shadowColor: Colors.red[200],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          // QTY 数量按钮
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3.0),
              child: ElevatedButton.icon(
                onPressed: onShowQuantitySelector,
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: Text('quantity'.tr.toUpperCase(),
                    style:
                        const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple[300],
                  foregroundColor: Colors.white,
                  elevation: 3,
                  shadowColor: Colors.purple[200],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          if (showQuickSelectButton)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3.0),
                child: ElevatedButton.icon(
                  onPressed: onSelectQuickInput,
                  icon: Icon(
                    isQuickSearchActive
                        ? Icons.check_circle_outline
                        : Icons.search,
                    size: 16,
                  ),
                  label: Text(
                    isQuickSearchActive ? 'confirm'.tr.toUpperCase() : 'quick_input'.tr.toUpperCase(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isQuickSearchActive
                        ? Colors.teal[400]
                        : Colors.indigo[400],
                    foregroundColor: Colors.white,
                    elevation: 3,
                    shadowColor: isQuickSearchActive
                        ? Colors.teal[200]
                        : Colors.indigo[200],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          // Order按钮 - 结账/下单
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3.0),
              child: ElevatedButton.icon(
                onPressed: orderEnabled ? onOrder : null,
                icon: Icon(orderIcon, size: 18),
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(orderLabel == 'ORDER' ? 'checkout'.tr.toUpperCase() : orderLabel,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                    if (orderedCount > 0)
                      Text('$orderedCount ${'quantity'.tr}',
                          style: const TextStyle(fontSize: 9)),
                  ],
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: orderEnabled ? orderColor : Colors.grey[400],
                  foregroundColor: Colors.white,
                  elevation: orderEnabled ? 6 : 1,
                  shadowColor: orderEnabled
                      ? orderColor.withOpacity(0.35)
                      : Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  animationDuration: const Duration(milliseconds: 200),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
