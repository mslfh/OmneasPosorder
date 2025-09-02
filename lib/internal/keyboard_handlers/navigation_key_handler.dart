import 'package:flutter/services.dart';
import '../../common/models/menu_item.dart';

typedef KeyEventHandler = bool Function(KeyEvent event, List<MenuItem> products);

typedef NavigateOrderedProducts = void Function(LogicalKeyboardKey key);

typedef HasQuickInput = bool Function();

typedef PlayClickSound = Future<void> Function();

KeyEventHandler navigationKeyHandler({
  required HasQuickInput hasQuickInput,
  required NavigateOrderedProducts onNavigate,
  required PlayClickSound playClickSound,
}) {
  return (event, products) {
    if (event is! KeyDownEvent) return false;
    if (!hasQuickInput() &&
        (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
         event.logicalKey == LogicalKeyboardKey.arrowRight ||
         event.logicalKey == LogicalKeyboardKey.arrowUp ||
         event.logicalKey == LogicalKeyboardKey.arrowDown)) {
      onNavigate(event.logicalKey);
      playClickSound();
      return true;
    }
    return false;
  };
}
