import 'package:flutter/services.dart';
import '../../common/models/menu_item.dart';

typedef KeyEventHandler = bool Function(KeyEvent event, List<MenuItem> products);

class KeyboardEventHandler {
  final List<KeyEventHandler> _handlers = [];

  void addHandler(KeyEventHandler handler) {
    _handlers.add(handler);
  }

  void handle(KeyEvent event, List<MenuItem> products) {
    for (final handler in _handlers) {
      if (handler(event, products)) {
        break;
      }
    }
  }
}

