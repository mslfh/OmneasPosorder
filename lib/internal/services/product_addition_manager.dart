import '../../common/models/menu_item.dart';
import '../../common/models/menu_option.dart';
import '../utils/order_selected.dart';

/// 菜品添加和选项管理器
class ProductAdditionManager {
  /// 智能添加菜品方法
  void addProductIntelligently(
    MenuItem item,
    List<SelectedProduct> orderedProducts,
    Function(List<SelectedProduct>, SelectedProduct?) onUpdate,
  ) {
    // 检查已点菜品中是否有相同菜品且没有选项的
    final existingProductIndex = orderedProducts.indexWhere(
      (product) => product.product.id == item.id && product.options.isEmpty,
    );

    if (existingProductIndex != -1) {
      // 如果找到相同菜品且没有选项，直接增加该菜品的数量
      orderedProducts[existingProductIndex].quantity++;
      onUpdate(orderedProducts, orderedProducts[existingProductIndex]);
      return;
    }

    // 否则添加新的菜品项
    final newProduct = SelectedProduct(product: item, options: []);
    orderedProducts.add(newProduct);
    onUpdate(orderedProducts, newProduct);
  }

  /// 为菜品添加选项
  void addOptionToLastProduct(
    String type,
    MenuOption option,
    List<SelectedProduct> orderedProducts,
    SelectedProduct? selectedOrderedProduct,
    Function(List<SelectedProduct>) onUpdate,
  ) {
    SelectedProduct? targetProduct;

    if (selectedOrderedProduct != null) {
      targetProduct = selectedOrderedProduct;
    } else if (orderedProducts.isNotEmpty) {
      targetProduct = orderedProducts.last;
    } else {
      return;
    }

    // 检查是否已存在相同类型和选项的组合
    final existingOptionIndex = targetProduct.options.indexWhere(
      (opt) => opt.type == type && opt.option.id == option.id,
    );

    if (existingOptionIndex == -1) {
      // 支持同类型多选，直接添加新选项
      targetProduct.options.add(SelectedOption(type: type, option: option));
      onUpdate(orderedProducts);
    }
  }

  /// 编辑菜品选项
  void editProductOptions(
    SelectedProduct ordered,
    Map<String, String?> editingOptions,
    Map<String, List<MenuOption>> optionGroups,
    Function(List<SelectedProduct>) onUpdate,
  ) {
    ordered.options.clear();
    editingOptions.forEach((type, optionName) {
      if (optionName != null) {
        final option = optionGroups[type]!.firstWhere((o) => o.name == optionName);
        ordered.options.add(SelectedOption(type: type, option: option));
      }
    });
    onUpdate([]);
  }

  /// 复制并修改菜品
  void copyAndEditProduct(
    SelectedProduct ordered,
    List<SelectedProduct> orderedProducts,
    Function(List<SelectedProduct>, SelectedProduct?) onUpdate,
  ) {
    final newProduct = SelectedProduct(
      product: ordered.product,
      options: ordered.options.map((opt) => SelectedOption(
        type: opt.type,
        option: opt.option,
      )).toList(),
    );
    orderedProducts.add(newProduct);
    onUpdate(orderedProducts, newProduct);
  }

  /// 获取所有选项的平面列表（用于快捷搜索）
  List<MenuOption> getAllOptionsFlatList(
    Map<String, List<MenuOption>> optionGroups,
  ) {
    final allOptions = <MenuOption>[];
    optionGroups.forEach((type, options) {
      allOptions.addAll(options);
    });
    return allOptions;
  }
}

