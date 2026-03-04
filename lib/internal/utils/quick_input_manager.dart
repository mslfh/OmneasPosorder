import 'package:flutter/services.dart';
import '../../common/models/menu_item.dart';
import '../../common/models/menu_option.dart';

class QuickInputManager {
  String _input = '';
  List<dynamic> _searchResults = []; // 可能是 MenuItem 或 MenuOption
  int _highlightedIndex = 0;
  bool _isSearchingOptions = false; // 标记当前是否在搜索选项

  String get input => _input;
  List<dynamic> get searchResults => _searchResults;
  int get highlightedIndex => _highlightedIndex;
  bool get isSearchingOptions => _isSearchingOptions;

  // 处理键盘输入
  bool handleKeyEvent(KeyEvent event, List<MenuItem> allProducts, {List<MenuOption>? allOptions, bool preferOptions = false}) {
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;
    final keyLabel = key.keyLabel;

    // 检查是否是数字键 - 返回特殊值表示需要处理数量
    if (keyLabel.length == 1 && RegExp(r'^[0-9]$').hasMatch(keyLabel)) {
      // 如果当前已有输入（例如输入了字母前缀），将数字视为输入的一部分（用于匹配 code，如 M015）
      if (_input.isNotEmpty) {
        _input += keyLabel;
        _performSearch(allProducts, allOptions: allOptions, preferOptions: preferOptions);
        _highlightedIndex = 0;
        return true;
      }
      // 否则返回 false，让调用者（数字键处理器）处理数量设置
      return false;
    }

    // 检查是否是字母
    if (keyLabel.length == 1 && RegExp(r'^[a-zA-Z]$').hasMatch(keyLabel)) {
      _input += keyLabel.toUpperCase();
      _performSearch(allProducts, allOptions: allOptions, preferOptions: preferOptions);
      _highlightedIndex = 0;
      return true;
    }

    // 处理空格，允许匹配多词名称（如 "extra chill"）
    if (key == LogicalKeyboardKey.space) {
      _input += ' ';
      _performSearch(allProducts, allOptions: allOptions, preferOptions: preferOptions);
      _highlightedIndex = 0;
      return true;
    }

    // 检查是否是中文输入
    if (event.character != null &&
        event.character!.length == 1 &&
        RegExp(r'[\u4e00-\u9fa5]').hasMatch(event.character!)) {
      _input += event.character!;
      _performSearch(allProducts, allOptions: allOptions, preferOptions: preferOptions);
      _highlightedIndex = 0;
      return true;
    }

    // Backspace - 删除最后一个字符
    if (key == LogicalKeyboardKey.backspace && _input.isNotEmpty) {
      _input = _input.substring(0, _input.length - 1);
      if (_input.isEmpty) {
        _searchResults.clear();
      } else {
        _performSearch(allProducts, allOptions: allOptions, preferOptions: preferOptions);
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
      print('[DEBUG QI_MGR] arrowDown: _highlightedIndex $_highlightedIndex -> ${(_highlightedIndex + 1) % _searchResults.length}');
      _highlightedIndex = (_highlightedIndex + 1) % _searchResults.length;
      print('[DEBUG QI_MGR] after arrowDown: _highlightedIndex=$_highlightedIndex');
      return true;
    }

    if (key == LogicalKeyboardKey.arrowUp && _searchResults.isNotEmpty) {
      print('[DEBUG QI_MGR] arrowUp: _highlightedIndex $_highlightedIndex -> ${(_highlightedIndex - 1 + _searchResults.length) % _searchResults.length}');
      _highlightedIndex = (_highlightedIndex - 1 + _searchResults.length) % _searchResults.length;
      print('[DEBUG QI_MGR] after arrowUp: _highlightedIndex=$_highlightedIndex');
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

  // 公开搜索方法 - 供外部调用
  void performSearch(List<MenuItem> allProducts, {List<MenuOption>? allOptions, bool preferOptions = false}) {
    _performSearch(allProducts, allOptions: allOptions, preferOptions: preferOptions);
  }

  // 执行统一搜索 - 同时搜索商品和选项
  void _performSearch(List<MenuItem> allProducts, {List<MenuOption>? allOptions, bool preferOptions = false}) {
    if (_input.isEmpty) {
      _searchResults.clear();
      _isSearchingOptions = false;
      return;
    }

    final lowerInput = _input.toLowerCase();

    // Debug 日志，记录输入和待搜索集合大小
    try {
      print('[DEBUG] QuickInputManager._performSearch input="$_input" lower="$lowerInput" products=${allProducts.length} options=${allOptions?.length ?? 0}');
    } catch (e) {
      // ignore
    }

    // 根据 preferOptions 决定搜索优先级
    if (preferOptions && allOptions != null) {
      // 优先搜索选项
      final matchedOptions = _searchOptions(allOptions, lowerInput);
      try {
        print('[DEBUG] matchedOptions=${matchedOptions.length} (preferOptions=true)');
        if (matchedOptions.isNotEmpty) {
          final optionNames = matchedOptions.take(5).map((o) => o.name).toList();
          print('[DEBUG] matched option names sample: $optionNames');
        }
      } catch (e) {}

      final matchedProducts = _searchProducts(allProducts, lowerInput);
      try {
        print('[DEBUG] matchedProducts=${matchedProducts.length} (after option search)');
        if (matchedProducts.isNotEmpty) {
          final titles = matchedProducts.take(5).map((p) => p.title).toList();
          print('[DEBUG] matched product titles sample: $titles');
        }
      } catch (e) {}

      // 当两边都有匹配时，合并结果（选项优先）
      if (matchedOptions.isNotEmpty && matchedProducts.isNotEmpty) {
        // 为了同时展示商品和选项，并让用户能直接选择商品，始终将商品放在前面
        _searchResults = [...matchedProducts, ...matchedOptions];
        _isSearchingOptions = false; // 混合模式以商品为主色
        _highlightedIndex = 0;
        return;
      }

      if (matchedOptions.isNotEmpty) {
        _searchResults = matchedOptions;
        _highlightedIndex = 0;
        _isSearchingOptions = true;
        return;
      }

      if (matchedProducts.isNotEmpty) {
        _searchResults = matchedProducts;
        _highlightedIndex = 0;
        _isSearchingOptions = false;
        return;
      }

    } else {
      // 默认：先搜索商品，再搜索选项
      final matchedProducts = _searchProducts(allProducts, lowerInput);
      try {
        print('[DEBUG] matchedProducts=${matchedProducts.length}');
        if (matchedProducts.isNotEmpty) {
          final titles = matchedProducts.take(5).map((p) => p.title).toList();
          print('[DEBUG] matched product titles sample: $titles');
        }
      } catch (e) {}

      final matchedOptions = (allOptions != null) ? _searchOptions(allOptions, lowerInput) : <MenuOption>[];
      try {
        print('[DEBUG] matchedOptions=${matchedOptions.length}');
        if (matchedOptions.isNotEmpty) {
          final optionNames = matchedOptions.take(5).map((o) => o.name).toList();
          print('[DEBUG] matched option names sample: $optionNames');
        }
      } catch (e) {}

      // 当两边都有匹配时，合并结果（商品优先）
      if (matchedProducts.isNotEmpty && matchedOptions.isNotEmpty) {
        _searchResults = [...matchedProducts, ...matchedOptions];
        _isSearchingOptions = false; // 混合模式以商品为主色
        _highlightedIndex = 0;
        return;
      }

      if (matchedProducts.isNotEmpty) {
        _searchResults = matchedProducts;
        _highlightedIndex = 0;
        _isSearchingOptions = false;
        return;
      }

      if (matchedOptions.isNotEmpty) {
        _searchResults = matchedOptions;
        _highlightedIndex = 0;
        _isSearchingOptions = true;
        return;
      }
    }

    _searchResults.clear();
    _isSearchingOptions = false;
  }

  // 字符顺序匹配 - 检查input中的字符是否按顺序出现在text中
  bool _matchesCharacterSequence(String text, String input) {
    text = text.toLowerCase();
    input = input.toLowerCase();

    int textIndex = 0;
    for (final char in input.split('')) {
      final foundIndex = text.indexOf(char, textIndex);
      if (foundIndex == -1) {
        return false;
      }
      textIndex = foundIndex + 1;
    }
    return true;
  }

  // 搜索商品
  List<MenuItem> _searchProducts(List<MenuItem> allProducts, String lowerInput) {
    // 优先匹配acronym前缀，兼容acronym为null
    final acronymMatches = allProducts.where((product) =>
      (product.acronym ?? '').toLowerCase().startsWith(lowerInput)
    ).toList();

    if (acronymMatches.isNotEmpty) {
      return acronymMatches;
    }

    // 使用字符顺序匹配 - 对title和code进行匹配
    final charSequenceMatches = allProducts.where((product) =>
      _matchesCharacterSequence(product.title, lowerInput) ||
      _matchesCharacterSequence(product.code, lowerInput)
    ).toList();

    return charSequenceMatches;
  }

  // 搜索选项
  List<MenuOption> _searchOptions(List<MenuOption> allOptions, String lowerInput) {
    return allOptions.where((option) {
      return _matchesCharacterSequence(option.name, lowerInput) ||
             _matchesCharacterSequence(option.type, lowerInput);
    }).toList();
  }

  // 获取当前选中的产品或选项
  dynamic getSelectedItem() {
    if (_searchResults.isEmpty || _highlightedIndex >= _searchResults.length) {
      return null;
    }
    return _searchResults[_highlightedIndex];
  }

  // 获取当前选中的产品
  MenuItem? getSelectedProduct() {
    final item = getSelectedItem();
    return item is MenuItem ? item : null;
  }

  // 获取当前选中的选项
  MenuOption? getSelectedOption() {
    final item = getSelectedItem();
    return item is MenuOption ? item : null;
  }

  // 清空输入和结果
  void clear() {
    _input = '';
    _searchResults.clear();
    _highlightedIndex = 0;
    _isSearchingOptions = false;
  }

  // 添加字符（用于外部调用）
  void addChar(String char) {
    _input += char;
  }

  // 删除最后一个字符（用于外部调用）
  void removeLastChar() {
    if (_input.isNotEmpty) {
      _input = _input.substring(0, _input.length - 1);
    }
  }

  // 检查是否有输入
  bool get hasInput => _input.isNotEmpty;

  // 检查是否有搜索结果
  bool get hasResults => _searchResults.isNotEmpty;
}
