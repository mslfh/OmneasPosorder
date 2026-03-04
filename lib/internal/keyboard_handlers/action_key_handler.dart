import 'package:flutter/services.dart';
import '../../common/models/menu_item.dart';
import '../utils/order_selected.dart';

/// 处理操作键（Backspace: 顺序删除（先删选项后删菜品）, Delete: VOID, =: 增加数量, -: 减少数量）
bool Function(KeyEvent, List<MenuItem>) actionKeyHandler({
  required List<SelectedProduct> orderedProducts,
  required SelectedProduct? Function() selectedOrderedProductGetter,
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
        // Backspace键 - 顺序删除：先删除最新添加的菜品选项（如果有），如果没有则删除菜品
        if (orderedProducts.isNotEmpty) {
          playClickSound();
          final selectedOrderedProduct = selectedOrderedProductGetter();

          // 确定目标菜品（优先选中的，否则最后一个）
          SelectedProduct targetProduct = selectedOrderedProduct ?? orderedProducts.last;

          // 首先检查是否有选项，如果有则删除最后一个选项
          if (targetProduct.options.isNotEmpty) {
            targetProduct.options.removeLast();
          } else {
            // 如果没有选项，则删除该菜品
            orderedProducts.remove(targetProduct);

            // 删除后自动选中最后一个菜品
            if (orderedProducts.isNotEmpty) {
              setSelectedOrderedProduct(orderedProducts.last);
            } else {
              setSelectedOrderedProduct(null);
            }
          }
          refreshUI();
        }
        return true;

      case LogicalKeyboardKey.delete:
        // Delete键 - VOID操作：删除选中的菜品，如果没有选中则删除最后一个
        if (orderedProducts.isNotEmpty) {
          playClickSound();
          final selectedOrderedProduct = selectedOrderedProductGetter();
          if (selectedOrderedProduct != null) {
            // 删除选中的菜品
            orderedProducts.remove(selectedOrderedProduct);
          } else {
            // 删除最后一个菜品
            orderedProducts.removeLast();
          }
          // 删除后自动选中最后一个菜品
          if (orderedProducts.isNotEmpty) {
            setSelectedOrderedProduct(orderedProducts.last);
          } else {
            setSelectedOrderedProduct(null);
          }
          refreshUI();
        }
        return true;

      case LogicalKeyboardKey.equal:
        // '='键 - 增加数量
        if (orderedProducts.isNotEmpty) {
          playClickSound();
          SelectedProduct targetProduct;

          // Use getter to obtain current selected ordered product
          final currentSelected = selectedOrderedProductGetter();
          if (currentSelected != null) {
            targetProduct = currentSelected;
          } else {
            targetProduct = orderedProducts.last;
          }

          targetProduct.quantity++;
          refreshUI();
        }
        return true;

      case LogicalKeyboardKey.minus:
        // '-'键 - 减少数量（不可减为0）
        if (orderedProducts.isNotEmpty) {
          SelectedProduct targetProduct;

          // Use getter to obtain current selected ordered product
          final currentSelected = selectedOrderedProductGetter();
          if (currentSelected != null) {
            targetProduct = currentSelected;
          } else {
            targetProduct = orderedProducts.last;
          }

          if (targetProduct.quantity > 1) {
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
