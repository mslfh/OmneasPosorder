class OrderItemMapper {
  static List<Map<String, dynamic>> mapServerItemsToLocalItems(
    List<dynamic> serverItems,
  ) {
    return serverItems.map((item) {
      final customizations = item['customization'] as List<dynamic>? ?? [];
      final List<Map<String, dynamic>> options = [];
      for (final c in customizations) {
        if (c['type'] == 'replacement') {
          final originalName = c['originalName']?.toString() ?? '';
          final replacementName = c['replacementName']?.toString() ?? '';
          final priceChange =
              double.tryParse(c['priceChange']?.toString() ?? '0') ?? 0.0;
          final isNoodleOrSourceReplacement =
              _isNoodleOrSourceReplacement(originalName, replacementName);

          if (isNoodleOrSourceReplacement) {
            options.add({
              'type': 'CHANGE',
              'option_id': null,
              'option_name': replacementName,
              'extra_price': priceChange,
            });
          } else {
            options.add({
              'type': 'NO',
              'option_id': null,
              'option_name': 'No $originalName',
              'extra_price': 0.0,
            });
            options.add({
              'type': 'ONLY',
              'option_id': null,
              'option_name': '$replacementName Only',
              'extra_price': priceChange,
            });
          }
        } else if (c['type'] == 'quantity') {
          final int original =
              int.tryParse(c['originalQuantity']?.toString() ?? '0') ?? 0;
          final int current =
              int.tryParse(c['currentQuantity']?.toString() ?? '0') ?? 0;
          final int diff = current - original;
          final double priceChange =
              double.tryParse(c['priceChange']?.toString() ?? '0') ?? 0.0;
          if (diff > 0) {
            final double singlePrice =
                diff > 0 ? priceChange / diff : priceChange;
            for (int i = 0; i < diff; i++) {
              final ingredientName = c['ingredientName']?.toString() ?? '';
              final hasExtra = ingredientName.toLowerCase().contains('extra');
              final normalizedName = hasExtra
                  ? ingredientName.replaceAll(
                      RegExp(r'extra|Extra|EXTRA', caseSensitive: false),
                      'EXTRA')
                  : 'EXTRA $ingredientName';
              options.add({
                'type': 'EXTRA',
                'option_id': null,
                'option_name': normalizedName,
                'extra_price': singlePrice,
              });
            }
          } else if (diff < 0 && current == 0) {
            final ingredientName = c['ingredientName']?.toString() ?? '';
            final hasNo = ingredientName.toLowerCase().contains('no');
            final normalizedName = hasNo
                ? ingredientName.replaceAll(
                    RegExp(r'no|No|NO', caseSensitive: false), 'No')
                : 'No $ingredientName';
            options.add({
              'type': 'NO',
              'option_id': null,
              'option_name': normalizedName,
              'extra_price': priceChange,
            });
          } else if (diff < 0 && current > 0) {
            options.add({
              'type': 'CHANGE',
              'option_id': null,
              'option_name': '${c['ingredientName']} ： ${current.abs()}',
              'extra_price': priceChange,
            });
          }
        }
      }
      final int quantity =
          int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;

      // product_selling_price 字段为菜品单价
      final double? unitPriceRaw = double.tryParse(
        item['product_selling_price']?.toString() ??
            item['unit_price']?.toString() ??
            item['price']?.toString() ??
            item['selling_price']?.toString() ??
            '',
      );

      // final_amount 字段为该 item 的最终总价（单价 * 数量 - 折扣）
      final double? finalAmountRaw =
          double.tryParse(item['final_amount']?.toString() ?? '');

      final double unitPrice = unitPriceRaw ??
          (finalAmountRaw != null && quantity > 0
              ? finalAmountRaw / quantity
              : 0.0);

      final double finalAmount = finalAmountRaw ?? (unitPrice * quantity);

      return {
        'id': item['product_id'] ?? item['id'],
        'name': item['product_title'] ?? item['name'] ?? '',
        'kitchen_print_name': item['kitchen_print_name'] ??
            item['kitchenPrintName'] ??
            item['product']?['kitchen_print_name'] ??
            item['product']?['kitchenPrintName'],
        'price': unitPrice, // 本地统一使用的菜品单价
        'product_selling_price': unitPrice, // 显式记录菜品单价
        'final_amount': finalAmount, // 显式记录 item 最终总价
        'quantity': quantity,
        'options': options,
        'is_printable': item['product']?['is_printable'] ?? true,
      };
    }).toList();
  }

  static bool _isNoodleOrSourceReplacement(
    String originalName,
    String replacementName,
  ) {
    bool containsKeyword(String value) {
      final normalized = value.toLowerCase();
      return normalized.contains('noodle') || normalized.contains('source');
    }

    return containsKeyword(originalName) && containsKeyword(replacementName);
  }
}
