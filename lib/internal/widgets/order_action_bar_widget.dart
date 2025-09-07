import 'package:flutter/material.dart';
import '../utils/order_selected.dart';

class OrderActionBarWidget extends StatelessWidget {
  final VoidCallback onVoidOrder;
  final VoidCallback onClearOrder;
  final VoidCallback onShowQuantitySelector;
  final VoidCallback onCustomAction;
  final VoidCallback? onOrder;
  final VoidCallback onSyncRemoteOrders;
  final int orderedCount;
  final bool orderEnabled;

  const OrderActionBarWidget({
    Key? key,
    required this.onVoidOrder,
    required this.onClearOrder,
    required this.onShowQuantitySelector,
    required this.onCustomAction,
    required this.onOrder,
    required this.orderedCount,
    required this.orderEnabled,
    required this.onSyncRemoteOrders,
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
        boxShadow: [
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
          // VOID按钮
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3.0),
              child: ElevatedButton.icon(
                onPressed: onVoidOrder,
                icon: Icon(Icons.delete_outline, size: 16),
                label: Text('VOID', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[300],
                  foregroundColor: Colors.white,
                  elevation: 3,
                  shadowColor: Colors.red[200],
                  padding: EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          // CLEAR按钮
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3.0),
              child: ElevatedButton.icon(
                onPressed: onClearOrder,
                icon: Icon(Icons.clear_all, size: 16),
                label: Text('CLEAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[300],
                  foregroundColor: Colors.white,
                  elevation: 3,
                  shadowColor: Colors.orange[200],
                  padding: EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          // X按钮 - 数量设置
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3.0),
              child: ElevatedButton.icon(
                onPressed: onShowQuantitySelector,
                icon: Icon(Icons.add_circle_outline, size: 16),
                label: Text('QTY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple[300],
                  foregroundColor: Colors.white,
                  elevation: 3,
                  shadowColor: Colors.purple[200],
                  padding: EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          // Custom按钮
          // Expanded(
          //   child: Padding(
          //     padding: const EdgeInsets.symmetric(horizontal: 3.0),
          //     child: ElevatedButton.icon(
          //       onPressed: onCustomAction,
          //       icon: Icon(Icons.settings, size: 16),
          //       label: Text('CUSTOM', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600)),
          //       style: ElevatedButton.styleFrom(
          //         backgroundColor: Colors.blue[300],
          //         foregroundColor: Colors.white,
          //         elevation: 3,
          //         shadowColor: Colors.blue[200],
          //         padding: EdgeInsets.symmetric(vertical: 12),
          //         shape: RoundedRectangleBorder(
          //           borderRadius: BorderRadius.circular(8),
          //         ),
          //       ),
          //     ),
          //   ),
          // ),

          // 拉单按钮
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3.0),
              child: ElevatedButton.icon(
                onPressed: onSyncRemoteOrders,
                icon: Icon(Icons.cloud_download, size: 16),
                label: Text('SYNC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  elevation: 3,
                  shadowColor: Colors.blue,
                  padding: EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          // Order按钮 - 突出显示
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3.0),
              child: ElevatedButton.icon(
                onPressed: orderEnabled ? onOrder : null,
                icon: Icon(Icons.shopping_cart, size: 18),
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('ORDER', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    if (orderedCount > 0)
                      Text('$orderedCount items', style: TextStyle(fontSize: 9)),
                  ],
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: orderEnabled ? Colors.green[500] : Colors.grey[400],
                  foregroundColor: Colors.white,
                  elevation: orderEnabled ? 6 : 1,
                  shadowColor: orderEnabled ? Colors.green[300] : Colors.grey[300],
                  padding: EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  animationDuration: Duration(milliseconds: 200),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
