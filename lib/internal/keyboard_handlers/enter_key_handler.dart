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
  required void Function()? onOrder, // 新增下单回调
  required bool Function() hasOrderedProducts, // 检查是否有已点菜品
}) {
  return (event, products) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      print('[DEBUG] Enter键被按下');
      print('[DEBUG] hasInput: ${quickInputManager.hasInput}');
      print('[DEBUG] hasResults: ${quickInputManager.hasResults}');
      print('[DEBUG] hasOrderedProducts: ${hasOrderedProducts()}');
      print('[DEBUG] onOrder is null: ${onOrder == null}');

      // 优先处理快捷输入
      if (quickInputManager.hasResults) {
        print('[DEBUG] 处理快捷输入选择');
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
      // 如果没有快捷输入且有已点菜品，则触发下单
      else if (!quickInputManager.hasInput && hasOrderedProducts() && onOrder != null) {
        print('[DEBUG] 触发下单操作');
        playClickSound();
        onOrder();
        return true;
      }

      print('[DEBUG] Enter键处理条件不满足，返回false');
    }
    return false;
  };
}
