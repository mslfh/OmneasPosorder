import '../../common/models/menu_item.dart';
import '../../common/models/menu_option.dart';
import 'order_selected.dart';

class DiningTableMapper {
  /// 将后端返回的桌台/预点菜品数组映射为 SelectedProduct 列表
  static List<SelectedProduct> buildSelectedProductsFromTableItems(
    List rawItems,
    List<MenuItem> menuCatalog,
  ) {
    return rawItems.map((item) {
      final map = item is Map<String, dynamic>
          ? item
          : Map<String, dynamic>.from(item as Map);
      return _toSelectedProduct(map, menuCatalog);
    }).toList();
  }

  /// 将 SelectedProduct 列表转换为提交给后端桌台/订单 API 的 items 格式
  static List<Map<String, dynamic>> toTableApiItems(
    List<SelectedProduct> products,
  ) {
    return products.map((p) {
      final options = p.options.map((o) {
        return {
          'group_name': o.type,
          'option_name': o.option.name,
          'price': o.option.extraCost,
        };
      }).toList();

      return {
        'product_id': p.product.id,
        'name': p.product.title,
        'price': p.product.sellingPrice,
        'quantity': p.quantity,
        'notes': '',
        'options': options,
      };
    }).toList();
  }

  static SelectedProduct _toSelectedProduct(
    Map<String, dynamic> item,
    List<MenuItem> menuCatalog,
  ) {
    final productId = _toInt(item['product_id']) ?? _toInt(item['id']) ?? 0;
    final resolved =
        menuCatalog.where((product) => product.id == productId).toList();

    final product = resolved.isNotEmpty
        ? resolved.first
        : MenuItem(
            id: productId,
            code: item['code']?.toString() ?? 'TABLE-$productId',
            title: item['name']?.toString() ??
                item['title']?.toString() ??
                'Unknown',
            kitchenPrintName: item['kitchen_print_name']?.toString(),
            acronym: null,
            sellingPrice: _toDouble(item['price']) ??
                _toDouble(item['product_selling_price']) ??
                _toDouble(item['selling_price']) ??
                _toDouble(item['unit_price']) ??
                0.0,
            stock: 0,
            sort: 0,
            categoryIds: const [],
            isPrintable: item['is_printable'] == true,
          );

    final options = (item['options'] as List<dynamic>? ?? []).map((opt) {
      final optMap = opt is Map<String, dynamic>
          ? opt
          : Map<String, dynamic>.from(opt as Map);

      final groupName = optMap['group_name']?.toString() ??
          optMap['type']?.toString() ??
          '';
      final optionName = optMap['option_name']?.toString() ??
          optMap['name']?.toString() ??
          '';
      final price = _toDouble(optMap['price']) ??
          _toDouble(optMap['extra_price']) ??
          0.0;

      return SelectedOption(
        type: groupName,
        option: MenuOption(
          id: Object.hash(groupName, optionName, price),
          name: optionName,
          type: groupName,
          extraCost: price,
        ),
      );
    }).toList();

    return SelectedProduct(
      product: product,
      options: options,
      quantity: _toInt(item['quantity']) ?? 1,
    );
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
