import '../../common/models/menu_item.dart';
import '../../common/models/menu_option.dart';
import '../../common/models/order_model.dart';
import 'order_selected.dart';

class OnlineOrderMapper {
  static List<SelectedProduct> buildSelectedProducts(
    OrderModel onlineOrder,
    List<MenuItem> menuCatalog,
  ) {
    final items = onlineOrder.getItemsList();
    return items.map((item) => _toSelectedProduct(item, menuCatalog)).toList();
  }

  static List<SelectedProduct> cloneSelectedProducts(
    List<SelectedProduct> source,
  ) {
    return source
        .map(
          (product) => SelectedProduct(
            product: product.product,
            options: product.options
                .map(
                    (opt) => SelectedOption(type: opt.type, option: opt.option))
                .toList(),
            quantity: product.quantity,
          ),
        )
        .toList();
  }

  static bool areSelectedProductsEqual(
    List<SelectedProduct> current,
    List<SelectedProduct> original,
  ) {
    return _serialize(current) == _serialize(original);
  }

  static List<Map<String, dynamic>> toCheckoutItems(
      List<SelectedProduct> products) {
    return products.map((p) {
      final options = p.options
          .map(
            (o) => {
              'type': o.type,
              'option_id': o.option.id,
              'option_name': o.option.name,
              'extra_price': o.option.extraCost,
            },
          )
          .toList();

      return {
        'id': p.product.id,
        'name': p.product.title,
        'price': p.product.sellingPrice,
        'quantity': p.quantity,
        'options': options,
        'is_printable': p.product.isPrintable,
      };
    }).toList();
  }

  static SelectedProduct _toSelectedProduct(
    Map<String, dynamic> item,
    List<MenuItem> menuCatalog,
  ) {
    final itemId = _toInt(item['id']) ?? 0;
    final resolved =
        menuCatalog.where((product) => product.id == itemId).toList();
    final product = resolved.isNotEmpty
        ? resolved.first
        : MenuItem(
            id: itemId,
            code: item['code']?.toString() ?? 'ONLINE-$itemId',
            title: item['name']?.toString() ?? 'Unknown',
            acronym: null,
            sellingPrice: _toDouble(item['price']) ?? 0.0,
            stock: 0,
            sort: 0,
            categoryIds: const [],
            isPrintable: item['is_printable'] == true,
          );

    final options = (item['options'] as List<dynamic>? ?? []).map((option) {
      final optionMap = option is Map<String, dynamic>
          ? option
          : Map<String, dynamic>.from(option as Map);
      final name = optionMap['option_name']?.toString() ?? '';
      final type = optionMap['type']?.toString() ?? '';
      final extraPrice = _toDouble(optionMap['extra_price']) ?? 0.0;
      return SelectedOption(
        type: type,
        option: MenuOption(
          id: Object.hash(type, name, extraPrice),
          name: name,
          type: type,
          extraCost: extraPrice,
        ),
      );
    }).toList();

    return SelectedProduct(
      product: product,
      options: options,
      quantity: _toInt(item['quantity']) ?? 1,
    );
  }

  static String _serialize(List<SelectedProduct> products) {
    final normalized = products
        .map(
          (product) => {
            'id': product.product.id,
            'quantity': product.quantity,
            'options': product.options
                .map((opt) => {
                      'type': opt.type,
                      'id': opt.option.id,
                      'name': opt.option.name,
                      'extra': opt.option.extraCost,
                    })
                .toList()
              ..sort((a, b) {
                final typeCompare =
                    (a['type'] as String).compareTo(b['type'] as String);
                if (typeCompare != 0) return typeCompare;
                return (a['name'] as String).compareTo(b['name'] as String);
              }),
          },
        )
        .toList();
    return normalized.toString();
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
