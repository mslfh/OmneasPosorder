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
      return {
        'id': item['product_id'],
        'name': item['product_title'],
        'price':
            double.tryParse(item['final_amount']?.toString() ?? '0') ?? 0.0,
        'quantity': item['quantity'] ?? 1,
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
