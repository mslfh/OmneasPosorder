import 'package:flutter/services.dart';
import '../../common/models/menu_item.dart';
import '../utils/order_selected.dart';

/// 处理操作键（Backspace: VOID, Delete: CLEAR, =: 增加数量, -: 减少数量）
bool Function(KeyEvent, List<MenuItem>) actionKeyHandler({
  required List<SelectedProduct> orderedProducts,
  required SelectedProduct? selectedOrderedProduct,
  required Function() voidOrder,
  required Function() clearOrder,
  required Function() playClickSound,
  required Function(SelectedProduct?) setSelectedOrderedProduct,
  required Function() refreshUI,
}) {
  return (KeyEvent event, List<MenuItem> products) {
    if (event is! KeyDownEvent) return false;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.backspace:
        // Backspace键 - VOID操作：删除选中的菜品，如果没有选中则删除最后一个
        if (orderedProducts.isNotEmpty) {
          playClickSound();
          if (selectedOrderedProduct != null) {
            // 删除选中的菜品
            orderedProducts.remove(selectedOrderedProduct);
            setSelectedOrderedProduct(null);
          } else {
            // 删除最后一个菜品
            orderedProducts.removeLast();
          }
          refreshUI();
        }
        return true;

      case LogicalKeyboardKey.delete:
        // Delete键 - CLEAR操作：清空所有已点菜品
        if (orderedProducts.isNotEmpty) {
          playClickSound();
          clearOrder();
        }
        return true;

      case LogicalKeyboardKey.equal:
        // '='键 - 增加数量
        if (orderedProducts.isNotEmpty) {
          playClickSound();
          SelectedProduct? targetProduct;

          if (selectedOrderedProduct != null) {
            targetProduct = selectedOrderedProduct;
          } else {
            targetProduct = orderedProducts.last;
          }

          targetProduct!.quantity++;
          refreshUI();
        }
        return true;

      case LogicalKeyboardKey.minus:
        // '-'键 - 减少数量（不可减为0）
        if (orderedProducts.isNotEmpty) {
          SelectedProduct? targetProduct;

          if (selectedOrderedProduct != null) {
            targetProduct = selectedOrderedProduct;
          } else {
            targetProduct = orderedProducts.last;
          }

          if (targetProduct!.quantity > 1) {
            playClickSound();
            targetProduct.quantity--;
            refreshUI();
          }
        }
        return true;

      default:
        return false;
    }
  };
}
