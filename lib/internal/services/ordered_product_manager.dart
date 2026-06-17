import '../utils/order_selected.dart';

/// 已点菜品管理器
class OrderedProductManager {
  /// 选中产品项
  void selectOrderedProduct(
    List<SelectedProduct> orderedProducts,
    SelectedProduct? selectedOrderedProduct,
    SelectedProduct ordered,
    Function(SelectedProduct?) onUpdate,
  ) {
    final newSelected = selectedOrderedProduct == ordered ? null : ordered;
    onUpdate(newSelected);
  }

  /// 复制菜品
  void duplicateOrderedProduct(
    SelectedProduct ordered,
    List<SelectedProduct> orderedProducts,
    Function(List<SelectedProduct>, SelectedProduct?) onUpdate,
  ) {
    final duplicatedProduct = SelectedProduct(
      product: ordered.product,
      options: [],
      quantity: ordered.quantity,
    );
    orderedProducts.add(duplicatedProduct);
    onUpdate(orderedProducts, duplicatedProduct);
  }

  /// 增加数量
  void increaseQuantity(SelectedProduct ordered) {
    ordered.quantity++;
  }

  /// 减少数量
  bool decreaseQuantity(
    SelectedProduct ordered,
    List<SelectedProduct> orderedProducts,
    Function(List<SelectedProduct>, SelectedProduct?) onUpdate,
  ) {
    if (ordered.quantity > 1) {
      ordered.quantity--;
      return false;
    } else {
      // 删除该菜品
      orderedProducts.remove(ordered);
      onUpdate(orderedProducts, null);
      return true;
    }
  }

  /// VOID操作 - 删除当前已点菜品（优先删除选中项）
  void voidOrder(
    List<SelectedProduct> orderedProducts,
    SelectedProduct? selectedOrderedProduct,
    Function(List<SelectedProduct>, SelectedProduct?) onUpdate,
  ) {
    if (orderedProducts.isEmpty) return;

    if (selectedOrderedProduct != null && orderedProducts.contains(selectedOrderedProduct)) {
      orderedProducts.remove(selectedOrderedProduct);
    } else {
      orderedProducts.removeLast();
    }

    // 删除后自动选中最后一个菜品
    final newSelected = orderedProducts.isNotEmpty ? orderedProducts.last : null;
    onUpdate(orderedProducts, newSelected);
  }

  /// CLEAR操作 - 清空订单
  void clearOrder(
    List<SelectedProduct> orderedProducts,
    Function(List<SelectedProduct>, SelectedProduct?) onUpdate,
  ) {
    orderedProducts.clear();
    onUpdate(orderedProducts, null);
  }

  /// 设置菜品数量
  void setProductQuantity(
    int quantity,
    List<SelectedProduct> orderedProducts,
    SelectedProduct? selectedOrderedProduct,
    Function(List<SelectedProduct>, SelectedProduct?) onUpdate,
  ) {
    if (orderedProducts.isEmpty) return;

    SelectedProduct? targetProduct;
    if (selectedOrderedProduct != null) {
      targetProduct = selectedOrderedProduct;
    } else {
      targetProduct = orderedProducts.last;
    }

    if (quantity == 0) {
      orderedProducts.remove(targetProduct);
      onUpdate(orderedProducts, null);
    } else {
      targetProduct.quantity = quantity;
      onUpdate(orderedProducts, selectedOrderedProduct);
    }
  }

  /// 导航已点菜品
  void navigateOrderedProducts(
    orderedProducts,
    selectedOrderedProduct,
    key,
    Function(SelectedProduct?) onUpdate,
  ) {
    if (orderedProducts.isEmpty) return;
    int currentIndex = selectedOrderedProduct != null
        ? orderedProducts.indexOf(selectedOrderedProduct)
        : -1;
    int newIndex;

    // 假设 key 参数通过某种方式指示方向
    // 这里需要导入 LogicalKeyboardKey 来完整判断
    // 为了简化，假设传入的是字符串
    switch (key) {
      case 'prev':
        newIndex = currentIndex <= 0 ? orderedProducts.length - 1 : currentIndex - 1;
        break;
      case 'next':
        newIndex = currentIndex >= orderedProducts.length - 1 || currentIndex == -1
            ? 0
            : currentIndex + 1;
        break;
      default:
        return;
    }

    onUpdate(orderedProducts[newIndex]);
  }
}


