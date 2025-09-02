import '../../common/models/menu_option.dart';

class OptionQuickInputManager {
  String input = '';
  List<MenuOption> searchResults = [];
  int highlightedIndex = 0;

  void updateInput(String value, List<MenuOption> allOptions) {
    input = value;
    _updateResults(allOptions);
  }

  void addChar(String char, List<MenuOption> allOptions) {
    input += char;
    _updateResults(allOptions);
  }

  void removeChar(List<MenuOption> allOptions) {
    if (input.isNotEmpty) {
      input = input.substring(0, input.length - 1);
      _updateResults(allOptions);
    }
  }

  void clear(List<MenuOption> allOptions) {
    input = '';
    _updateResults(allOptions);
  }

  void _updateResults(List<MenuOption> allOptions) {
    if (input.isEmpty) {
      searchResults = allOptions.take(10).toList();
    } else {
      final inputChars = input.toLowerCase().split('');
      searchResults = allOptions.where((o) {
        final name = o.name.toLowerCase();
        int lastIndex = -1;
        for (final ch in inputChars) {
          lastIndex = name.indexOf(ch, lastIndex + 1);
          if (lastIndex == -1) return false;
        }
        return true;
      }).take(10).toList();
    }
    highlightedIndex = 0;
  }

  void moveHighlightUp() {
    if (searchResults.isEmpty) return;
    highlightedIndex = (highlightedIndex - 1 + searchResults.length) % searchResults.length;
  }

  void moveHighlightDown() {
    if (searchResults.isEmpty) return;
    highlightedIndex = (highlightedIndex + 1) % searchResults.length;
  }

  MenuOption? get highlightedOption =>
      searchResults.isNotEmpty ? searchResults[highlightedIndex] : null;

  bool get hasInput => input.isNotEmpty;
  bool get hasResults => searchResults.isNotEmpty;
}
