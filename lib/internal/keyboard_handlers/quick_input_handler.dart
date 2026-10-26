import 'package:flutter/services.dart';
import '../../common/models/menu_item.dart';
import '../../common/models/menu_option.dart';
import '../utils/quick_input_manager.dart';

typedef KeyEventHandler = bool Function(KeyEvent event, List<MenuItem> products);

KeyEventHandler quickInputHandler({
  required QuickInputManager quickInputManager,
  required void Function() updateQuickInputOverlay,
  required void Function(void Function()) setState,
  List<MenuOption> Function()? getAllOptions,
  bool Function()? getPreferOptions,
}) {
  return (event, products) {
    if (quickInputManager.handleKeyEvent(event, products, allOptions: getAllOptions?.call(), preferOptions: getPreferOptions?.call() ?? false)) {
      setState(() {
        updateQuickInputOverlay();
      });
      return true;
    }
    return false;
  };
}
