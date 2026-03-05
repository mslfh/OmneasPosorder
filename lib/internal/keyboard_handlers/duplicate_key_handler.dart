import 'package:flutter/services.dart';
import '../../common/models/menu_item.dart';
import '../utils/order_selected.dart';

/// 处理 Ctrl 键：复制选中的菜品（不复制选项）
bool Function(KeyEvent, List<MenuItem>) duplicateKeyHandler({
  required List<SelectedProduct> orderedProducts,
  required SelectedProduct? Function() selectedOrderedProductGetter,
  required Function(SelectedProduct) duplicateProduct,
  required Function() playClickSound,
  required Function(SelectedProduct?) setSelectedOrderedProduct,
}) {
  return (KeyEvent event, List<MenuItem> products) {
    if (event is! KeyDownEvent) return false;

    // 检查是否按下 Ctrl 键（左或右）
    if (event.logicalKey == LogicalKeyboardKey.controlLeft || event.logicalKey == LogicalKeyboardKey.controlRight) {
      if (orderedProducts.isNotEmpty) {
        final selectedOrderedProduct = selectedOrderedProductGetter();
        if (selectedOrderedProduct != null) {
          playClickSound();
          duplicateProduct(selectedOrderedProduct);
        }
      }
      return true;
    }

    return false;
  };
}