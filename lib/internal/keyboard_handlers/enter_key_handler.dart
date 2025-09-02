import 'package:flutter/services.dart';
import '../../common/models/menu_item.dart';
import '../utils/quick_input_manager.dart';

typedef KeyEventHandler = bool Function(KeyEvent event, List<MenuItem> products);

KeyEventHandler enterKeyHandler({
  required QuickInputManager quickInputManager,
  required void Function(MenuItem) addProductIntelligently,
  required Future<void> Function() playClickSound,
  required void Function() clearQuickInput,
  required void Function() removeQuickInputOverlay,
  required void Function() refreshUI,
}) {
  return (event, products) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        quickInputManager.hasResults) {
      final selectedProduct = quickInputManager.getSelectedProduct();
      if (selectedProduct != null) {
        addProductIntelligently(selectedProduct);
        playClickSound();
        clearQuickInput();
        removeQuickInputOverlay();
        refreshUI();
        return true;
      }
    }
    return false;
  };
}

