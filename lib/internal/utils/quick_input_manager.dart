import 'package:flutter/services.dart';
import '../../common/models/menu_item.dart';
import '../../common/models/menu_option.dart';

class QuickInputManager {
  String _input = '';
  List<dynamic> _searchResults = []; // 可能是 MenuItem 或 MenuOption
  int _highlightedIndex = 0;
  bool _isSearchingOptions = false; // 标记当前是否在搜索选项
  bool? _forcedPreferOptions; // 手动强制优先选项：true 为优先选项，false 为优先菜品，null 为默认

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

    // 检查是否是字母或逗号、句号
    if (keyLabel.length == 1 && RegExp(r'^[a-zA-Z,\.，。]$').hasMatch(keyLabel)) {
      if (RegExp(r'^[,\.，。]$').hasMatch(keyLabel)) {
        // 更新强制优先模式，不拼接到输入框。二次输入相同符号则进行反转切换
        if (keyLabel == ',' || keyLabel == '，') {
          _forcedPreferOptions = _forcedPreferOptions == true ? false : true;
        } else if (keyLabel == '.' || keyLabel == '。') {
          _forcedPreferOptions = _forcedPreferOptions == false ? true : false;
        }
      } else {
        _input += keyLabel.toUpperCase();
      }
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

    // 检查是否是中文输入或标点
    if (event.character != null &&
        event.character!.length == 1 &&
        RegExp(r'[\u4e00-\u9fa5,\.，。]').hasMatch(event.character!)) {
      
      if (RegExp(r'^[,\.，。]$').hasMatch(event.character!)) {
        if (event.character == ',' || event.character == '，') {
          _forcedPreferOptions = _forcedPreferOptions == true ? false : true;
        } else if (event.character == '.' || event.character == '。') {
          _forcedPreferOptions = _forcedPreferOptions == false ? true : false;
        }
      } else {
        _input += event.character!;
      }
      
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

  // 公开搜索方法 - 供外部调用
  void performSearch(List<MenuItem> allProducts, {List<MenuOption>? allOptions, bool preferOptions = false}) {
    _performSearch(allProducts, allOptions: allOptions, preferOptions: preferOptions);
  }

  // 直接更新输入并刷新搜索结果（用于输入框变更）
  void updateInput(String value, List<MenuItem> allProducts, {List<MenuOption>? allOptions, bool preferOptions = false}) {
    _input = value;
    _performSearch(allProducts, allOptions: allOptions, preferOptions: preferOptions);
    _highlightedIndex = 0;
  }

  // 执行统一搜索 - 同时搜索商品和选项
  void _performSearch(List<MenuItem> allProducts, {List<MenuOption>? allOptions, bool preferOptions = false}) {
    final trimmedInput = _input.trim();
    if (trimmedInput.isEmpty) {
      _searchResults.clear();
      _isSearchingOptions = false;
      return;
    }

    // Determine priority mode based on the forced flag, fallback to default false (优先菜品)
    bool currentPreferOptions = _forcedPreferOptions ?? false;

    final lowerInput = trimmedInput.toLowerCase();

    List<MenuItem> matchedProducts = [];
    List<MenuOption> matchedOptions = [];

    if (currentPreferOptions && allOptions != null) {
      matchedOptions = _searchOptions(allOptions, lowerInput);
      matchedProducts = _searchProducts(allProducts, lowerInput);
    } else {
      matchedProducts = _searchProducts(allProducts, lowerInput);
      matchedOptions = (allOptions != null) ? _searchOptions(allOptions, lowerInput) : <MenuOption>[];
    }

    final manualOption = MenuOption(
      id: 0,
      name: trimmedInput, // 过滤掉,和.的输入词
      type: 'manual',
      extraCost: 0.0,
    );

    if (matchedProducts.isNotEmpty && matchedOptions.isNotEmpty) {
      if (currentPreferOptions) {
        _searchResults = [...matchedOptions, ...matchedProducts, manualOption];
        _isSearchingOptions = true;
      } else {
        _searchResults = [...matchedProducts, ...matchedOptions, manualOption];
        _isSearchingOptions = false;
      }
    } else if (matchedProducts.isNotEmpty) {
      _searchResults = [...matchedProducts, manualOption];
      _isSearchingOptions = false;
    } else if (matchedOptions.isNotEmpty) {
      _searchResults = [...matchedOptions, manualOption];
      _isSearchingOptions = true;
    } else {
      _searchResults = [manualOption];
      _isSearchingOptions = currentPreferOptions;
    }

    _highlightedIndex = 0;
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

  /// 计算字符匹配度分数（分数越高表示匹配度越高、字符占比越高）
  double _calculateMatchScore(String rawText, String rawInput) {
    if (rawText.isEmpty || rawInput.isEmpty) return 0.0;

    final text = rawText.toLowerCase();
    final input = rawInput.toLowerCase();

    // 1. 完全前缀匹配：给予最高基础分，字符占比越高（文本越短）得分越高
    if (text.startsWith(input)) {
      final ratio = input.length / text.length;
      return 300.0 + ratio * 100.0;
    }

    // 2. 连续包含匹配：字符占比越高得分越高
    if (text.contains(input)) {
      final ratio = input.length / text.length;
      return 200.0 + ratio * 100.0;
    }

    // 3. 字符顺序匹配：计算匹配跨度与字符占比
    int firstIndex = -1;
    int lastIndex = -1;
    int textIndex = 0;

    for (final char in input.split('')) {
      final foundIndex = text.indexOf(char, textIndex);
      if (foundIndex == -1) {
        return 0.0;
      }
      if (firstIndex == -1) firstIndex = foundIndex;
      lastIndex = foundIndex;
      textIndex = foundIndex + 1;
    }

    final span = lastIndex - firstIndex + 1;
    final lengthRatio = input.length / text.length;
    final spanRatio = input.length / span;
    final compositeRatio = lengthRatio * 0.6 + spanRatio * 0.4;

    return 100.0 + compositeRatio * 100.0;
  }

  // 搜索商品
  List<MenuItem> _searchProducts(List<MenuItem> allProducts, String lowerInput) {
    final List<MenuItem> codeMatches = [];
    final List<MenuItem> acronymMatches = [];
    final List<MenuItem> titleMatches = [];

    for (final product in allProducts) {
      final code = product.code;
      final acronym = product.acronym ?? '';
      final title = product.title;

      // 1. 优先匹配 code
      if (code.isNotEmpty && _matchesCharacterSequence(code, lowerInput)) {
        codeMatches.add(product);
      }
      // 2. 其次优先匹配 acronym
      else if (acronym.isNotEmpty && _matchesCharacterSequence(acronym, lowerInput)) {
        acronymMatches.add(product);
      }
      // 3. 最后按照 title 字符匹配
      else if (title.isNotEmpty && _matchesCharacterSequence(title, lowerInput)) {
        titleMatches.add(product);
      }
    }

    // 排序逻辑：优先使用 sort 字段排序，sort 相同时按字符匹配度（字符占比/跨度）降序排序
    int compareProducts(MenuItem a, MenuItem b, String Function(MenuItem) textGetter) {
      // 1. 优先使用 sort 字段升序
      final cmpSort = a.sort.compareTo(b.sort);
      if (cmpSort != 0) return cmpSort;

      // 2. sort 相同时，按字符匹配度降序（字符占比更高、更紧密的在前）
      final aText = textGetter(a);
      final bText = textGetter(b);
      final aScore = _calculateMatchScore(aText, lowerInput);
      final bScore = _calculateMatchScore(bText, lowerInput);
      final cmpScore = bScore.compareTo(aScore);
      if (cmpScore != 0) return cmpScore;

      // 3. 匹配度相同时，按文本字典序升序
      return aText.toLowerCase().compareTo(bText.toLowerCase());
    }

    codeMatches.sort((a, b) => compareProducts(a, b, (item) => item.code));
    acronymMatches.sort((a, b) => compareProducts(a, b, (item) => item.acronym ?? ''));
    titleMatches.sort((a, b) => compareProducts(a, b, (item) => item.title));

    return [...codeMatches, ...acronymMatches, ...titleMatches];
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
    _forcedPreferOptions = null;
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
