import 'type_utils.dart';

extension OrderItemNormalizer on Map<String, dynamic> {
  int get itemId => NumberFormatUtils.toInt(this['product_id'] ?? this['id']);

  String get itemName => (this['name'] ?? '').toString();

  int get itemQuantity => NumberFormatUtils.toInt(this['quantity'], 1);

  double get itemPrice => NumberFormatUtils.toDouble(this['price']);

  List<dynamic> get itemOptions =>
      (this['options'] as List<dynamic>?) ??
      (this['customization'] as List<dynamic>?) ??
      [];

  double get optionsExtraTotal {
    double sum = 0.0;
    for (final opt in itemOptions) {
      if (opt is Map) {
        sum += NumberFormatUtils.toDouble(
          opt['extra_price'] ?? opt['extra_cost'] ?? opt['extra'] ?? opt['priceChange'],
        );
      }
    }
    return sum;
  }

  double get itemFinalAmount {
    final double calculated = (itemPrice + optionsExtraTotal) * itemQuantity;
    return NumberFormatUtils.toDouble(
      this['final_amount'],
      calculated,
    );
  }

  List<Map<String, dynamic>> get formattedCustomizationPayload {
    return itemOptions.map((opt) {
      if (opt is Map) {
        final String name = (
                opt['option_name'] ??
                opt['name'] ??
                '')
            .toString();
        final double priceChange = NumberFormatUtils.toDouble(
              opt['extra_price'] ??
              opt['price'] ??
              opt['extra_cost'] ??
              opt['extra'],
        );
        final String rawType =
            (opt['type'] ?? opt['group_name'] ?? '').toString();
        final String typeUpper = rawType.toUpperCase();

        if (typeUpper.contains('NO') ) {
          return {
            'ingredientName': name,
            'priceChange': priceChange,
            'type': 'quantity',
            'currentQuantity': 0,
            'change': -1,
          };
        } else if (typeUpper.contains('CHANGE') ) {
          return {
            'priceChange': priceChange,
            'type': 'replacement',
            'change': 1,
            'replacementName': name,
          };
        }else if (typeUpper.contains('ONLY') ) {
          return {
            'replacementName': name,
            'priceChange': priceChange,
            'type': 'replacement',
            'change': 1,
          };
        }
        else {
          // extra, chill, chilli 或其他情况
          return {
            'ingredientName': name,
            'priceChange': priceChange,
            'type': 'quantity',
            'change': 1,
          };
        }
      }
      return <String, dynamic>{};
    }).where((map) => map.isNotEmpty).toList();
  }

  /// 转换为发往云端服务器的标准菜品 Payload 结构
  Map<String, dynamic> toStandardTerminalPayload() {
    final double optionsSum = optionsExtraTotal;
    final double calculatedFinalAmount =
        double.parse(((itemPrice + optionsSum) * itemQuantity).toStringAsFixed(2));

    return {
      'id': itemId,
      'name': itemName,
      'quantity': itemQuantity,
      'price': itemPrice,
      'final_amount': calculatedFinalAmount,
      'customization': formattedCustomizationPayload,
    };
  }
}

class OrderItemMapper {
  static List<Map<String, dynamic>> mapServerItemsToLocalItems(
    List<dynamic> serverItems,
  ) {
    return serverItems.map((item) {
      final mapItem = Map<String, dynamic>.from(item as Map);
      final customizations = mapItem['customization'] as List<dynamic>? ?? [];
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

      final int id =
          NumberFormatUtils.toInt(mapItem['product_id'] ?? mapItem['id']);
      final String name = (mapItem['name'] ??
              mapItem['product_title'] ??
              mapItem['title'] ??
              '')
          .toString();
      final int quantity =
          NumberFormatUtils.toInt(mapItem['quantity'] ?? mapItem['count'], 1);
      final double price = NumberFormatUtils.toDouble(
        mapItem['price'] ?? mapItem['product_selling_price'] ?? mapItem['unit_price'],
      );
      final double optionsTotal = options.fold(
        0.0,
        (sum, opt) => sum + NumberFormatUtils.toDouble(opt['extra_price']),
      );
      final double calculatedFinalAmount =
          double.parse(((price + optionsTotal) * quantity).toStringAsFixed(2));

      final double finalAmount = NumberFormatUtils.toDouble(
        mapItem['final_amount'],
        calculatedFinalAmount,
      );

      final kitchenPrintName = mapItem['kitchen_print_name'] ??
          mapItem['kitchenPrintName'] ??
          mapItem['product']?['kitchen_print_name'] ??
          mapItem['product']?['kitchenPrintName'];
      final isPrintable = mapItem['product']?['is_printable'] ?? true;

      return {
        'id': id,
        'name': name,
        'quantity': quantity,
        'price': price,
        'final_amount': finalAmount,
        'options': options,
        if (kitchenPrintName != null) 'kitchen_print_name': kitchenPrintName,
        'is_printable': isPrintable,
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
