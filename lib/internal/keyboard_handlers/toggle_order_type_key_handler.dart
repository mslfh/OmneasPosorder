import 'package:flutter/services.dart';
import '../../common/models/menu_item.dart';

/// 处理 Ctrl 键：切换订单类型（Takeaway / Dine in）
bool Function(KeyEvent, List<MenuItem>) toggleOrderTypeKeyHandler({
  required Function() onToggleOrderType,
  required Function() playClickSound,
}) {
  return (KeyEvent event, List<MenuItem> products) {
    if (event is! KeyDownEvent) return false;

    // 检查是否按下 Ctrl 键（左或右）
    if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight) {
      playClickSound();
      onToggleOrderType();
      return true;
    }

    return false;
  };
}
