import 'package:flutter/services.dart';
import '../../common/models/menu_item.dart';
import '../utils/quick_input_manager.dart';
import '../utils/order_selected.dart';

typedef KeyEventHandler = bool Function(KeyEvent event, List<MenuItem> products);

KeyEventHandler digitKeyHandler({
  required QuickInputManager quickInputManager,
  required List<SelectedProduct> orderedProducts,
  required void Function(int) setProductQuantity,
  required Future<void> Function() playClickSound,
}) {
  return (event, products) {
    if (QuickInputManager.isDigitKey(event) && orderedProducts.isNotEmpty) {
      final digit = QuickInputManager.getDigitValue(event);
      if (digit != null) {
        setProductQuantity(digit);
        playClickSound();
        return true;
      }
    }
    return false;
  };
}

