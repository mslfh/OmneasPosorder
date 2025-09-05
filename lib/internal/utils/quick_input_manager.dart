import 'package:flutter/services.dart';
import '../../common/models/menu_item.dart';

class QuickInputManager {
  String _input = '';
  List<MenuItem> _searchResults = [];
  int _highlightedIndex = 0;

  String get input => _input;
  List<MenuItem> get searchResults => _searchResults;
  int get highlightedIndex => _highlightedIndex;

  // 处理键盘输入
  bool handleKeyEvent(KeyEvent event, List<MenuItem> allProducts) {
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;
    final keyLabel = key.keyLabel;

    // 检查是否是数字键 - 返回特殊值表示需要处理数量
    if (keyLabel.length == 1 && RegExp(r'^[0-9]$').hasMatch(keyLabel)) {
      return false; // 返回false让调用者处理数量设置
    }

    // 检查是否是字母
    if (keyLabel.length == 1 && RegExp(r'^[a-zA-Z]$').hasMatch(keyLabel)) {
      _input += keyLabel.toUpperCase();
      _performSearch(allProducts);
      _highlightedIndex = 0;
      return true;
    }

    // Backspace - 删除最后一个字符
    if (key == LogicalKeyboardKey.backspace && _input.isNotEmpty) {
      _input = _input.substring(0, _input.length - 1);
      if (_input.isEmpty) {
        _searchResults.clear();
      } else {
        _performSearch(allProducts);
      }
      _highlightedIndex = 0;
      return true;
    }

    // ESC - 清空输入
    if (key == LogicalKeyboardKey.escape) {
      clear();
      return true;
    }

    // 上下箭头 - 切换高亮
    if (key == LogicalKeyboardKey.arrowDown && _searchResults.isNotEmpty) {
      _highlightedIndex = (_highlightedIndex + 1) % _searchResults.length;
      return true;
    }

    if (key == LogicalKeyboardKey.arrowUp && _searchResults.isNotEmpty) {
      _highlightedIndex = (_highlightedIndex - 1 + _searchResults.length) % _searchResults.length;
      return true;
    }

    // Enter - 选择当前高亮项
    if (key == LogicalKeyboardKey.enter && _searchResults.isNotEmpty) {
      return false; // 返回false让调用者处理选择逻辑
    }

    return false;
  }

  // 检查是否是数字键输入
  static bool isDigitKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keyLabel = event.logicalKey.keyLabel;
    return keyLabel.length == 1 && RegExp(r'^[0-9]$').hasMatch(keyLabel);
  }

  // 获取数字键的值
  static int? getDigitValue(KeyEvent event) {
    if (!isDigitKey(event)) return null;
    return int.tryParse(event.logicalKey.keyLabel);
  }

  // 执行搜索
  void _performSearch(List<MenuItem> allProducts) {
    if (_input.isEmpty) {
      _searchResults.clear();
      return;
    }

    final lowerInput = _input.toLowerCase();

    // 优先匹配acronym前缀，兼容acronym为null
    final acronymMatches = allProducts.where((product) =>
      (product.acronym ?? '').toLowerCase().startsWith(lowerInput)
    ).toList();

    if (acronymMatches.isNotEmpty) {
      _searchResults = acronymMatches;
      return;
    }

    // 如果没有acronym匹配，则进行title模糊匹配
    final titleMatches = allProducts.where((product) =>
      product.title.toLowerCase().contains(lowerInput)
    ).toList();

    _searchResults = titleMatches;
  }

  // 获取当前选中的产品
  MenuItem? getSelectedProduct() {
    if (_searchResults.isEmpty || _highlightedIndex >= _searchResults.length) {
      return null;
    }
    return _searchResults[_highlightedIndex];
  }

  // 清空输入和结果
  void clear() {
    _input = '';
    _searchResults.clear();
    _highlightedIndex = 0;
  }

  // 检查是否有输入
  bool get hasInput => _input.isNotEmpty;

  // 检查是否有搜索结果
  bool get hasResults => _searchResults.isNotEmpty;
}
