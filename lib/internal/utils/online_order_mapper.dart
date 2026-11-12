import '../../common/models/menu_item.dart';
import '../../common/models/menu_option.dart';
import '../../common/models/order_model.dart';
import 'order_selected.dart';

class OnlineOrderDiffItem {
  final String name;
  final int count;
  final int originalQty;
  final int currentQty;

  OnlineOrderDiffItem({
    required this.name,
    required this.count,
    required this.originalQty,
    required this.currentQty,
  });

  bool get isNew => originalQty == 0;
  bool get isCompletelyRemoved => currentQty == 0;
}

class OnlineOrderDiffResult {
  final List<OnlineOrderDiffItem> added;
  final List<OnlineOrderDiffItem> removed;

  OnlineOrderDiffResult({
    required this.added,
    required this.removed,
  });

  bool get hasChanges => added.isNotEmpty || removed.isNotEmpty;
}

class _ItemAggregate {
  final String displayName;
  int originalQty = 0;
  int currentQty = 0;

  _ItemAggregate({required this.displayName});
}

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

  static OnlineOrderDiffResult calculateDiff(
    List<SelectedProduct> original,
    List<SelectedProduct> current,
  ) {
    final Map<String, _ItemAggregate> map = {};

    for (var p in original) {
      final key = getProductKey(p);
      final entry = map.putIfAbsent(
        key,
        () => _ItemAggregate(displayName: _getDiffItemDisplayName(p)),
      );
      entry.originalQty += p.quantity;
    }

    for (var p in current) {
      final key = getProductKey(p);
      final entry = map.putIfAbsent(
        key,
        () => _ItemAggregate(displayName: _getDiffItemDisplayName(p)),
      );
      entry.currentQty += p.quantity;
    }

    final List<OnlineOrderDiffItem> added = [];
    final List<OnlineOrderDiffItem> removed = [];

    for (var entry in map.values) {
      if (entry.currentQty > entry.originalQty) {
        added.add(OnlineOrderDiffItem(
          name: entry.displayName,
          count: entry.currentQty - entry.originalQty,
          originalQty: entry.originalQty,
          currentQty: entry.currentQty,
        ));
      } else if (entry.currentQty < entry.originalQty) {
        removed.add(OnlineOrderDiffItem(
          name: entry.displayName,
          count: entry.originalQty - entry.currentQty,
          originalQty: entry.originalQty,
          currentQty: entry.currentQty,
        ));
      }
    }

    return OnlineOrderDiffResult(added: added, removed: removed);
  }

  static String getProductKey(SelectedProduct p) {
    final optionKeys = p.options
        .map((o) => '${o.type}:${o.option.name}:${o.option.extraCost}')
        .toList()
      ..sort();
    return '${p.product.id}_${p.product.title}_${optionKeys.join('|')}';
  }

  static String _getDiffItemDisplayName(SelectedProduct p) {
    if (p.options.isEmpty) {
      return p.product.title;
    }
    final optStr = p.options.map((o) => o.option.name).join(', ');
    return '${p.product.title} ($optStr)';
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

      final double price = p.product.sellingPrice;
      final int quantity = p.quantity;
      final double optionsTotal =
          p.options.fold(0.0, (s, o) => s + o.option.extraCost);
      final double finalAmount =
          double.parse(((price + optionsTotal) * quantity).toStringAsFixed(2));

      return {
        'id': p.product.id,
        'name': p.product.title,
        'quantity': quantity,
        'price': price,
        'final_amount': finalAmount,
        'options': options,
        if (p.product.kitchenPrintName != null)
          'kitchen_print_name': p.product.kitchenPrintName,
        'is_printable': p.product.isPrintable,
      };
    }).toList();
  }

  static SelectedProduct _toSelectedProduct(
    Map<String, dynamic> item,
    List<MenuItem> menuCatalog,
  ) {
    final itemId = _toInt(item['product_id']) ?? _toInt(item['id']) ?? 0;
    final resolved =
        menuCatalog.where((product) => product.id == itemId).toList();
    final product = resolved.isNotEmpty
        ? resolved.first
        : MenuItem(
            id: itemId,
            code: item['code']?.toString() ?? 'ONLINE-$itemId',
            title: item['name']?.toString() ??
                item['product_title']?.toString() ??
                'Unknown',
            kitchenPrintName: item['kitchen_print_name']?.toString() ??
                item['kitchenPrintName']?.toString(),
            acronym: null,
            sellingPrice: _toDouble(item['price']) ??
                _toDouble(item['product_selling_price']) ??
                _toDouble(item['unit_price']) ??
                0.0,
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

  /// 订单排序逻辑
  static List<OrderModel> sortOrders(
    List<OrderModel> orders,
    String criteria, {
    bool ascending = true,
  }) {
    final sorted = List<OrderModel>.from(orders);
    sorted.sort((a, b) {
      int cmp;
      switch (criteria) {
        case 'orderTime':
          cmp = a.orderTime.compareTo(b.orderTime);
          break;
        case 'createdAt':
          cmp = a.createdAt.compareTo(b.createdAt);
          break;
        case 'orderNo':
          cmp = a.orderNo.compareTo(b.orderNo);
          break;
        default:
          cmp = 0;
      }
      return ascending ? cmp : -cmp;
    });
    return sorted;
  }
}
