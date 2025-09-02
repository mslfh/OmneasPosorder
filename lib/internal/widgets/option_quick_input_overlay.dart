import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../common/models/menu_option.dart';

class OptionQuickInputOverlay extends StatefulWidget {
  final String input;
  final List<MenuOption> searchResults;
  final int highlightedIndex;
  final void Function() onClose;
  final void Function(MenuOption) onItemTap;
  final void Function() onMoveHighlightUp;
  final void Function() onMoveHighlightDown;
  final void Function(String char) onInputChar;
  final void Function() onBackspace;
  final void Function() onEnter;
  final void Function() onCtrl;
  final void Function() onEsc;

  const OptionQuickInputOverlay({
    Key? key,
    required this.input,
    required this.searchResults,
    required this.highlightedIndex,
    required this.onClose,
    required this.onItemTap,
    required this.onMoveHighlightUp,
    required this.onMoveHighlightDown,
    required this.onInputChar,
    required this.onBackspace,
    required this.onEnter,
    required this.onCtrl,
    required this.onEsc,
  }) : super(key: key);

  @override
  State<OptionQuickInputOverlay> createState() => _OptionQuickInputOverlayState();
}

class _OptionQuickInputOverlayState extends State<OptionQuickInputOverlay> {
  late FocusNode _focusNode;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _controller = TextEditingController(text: widget.input);
    // 弹窗显示时自动请求焦点
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant OptionQuickInputOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.input != _controller.text) {
      _controller.text = widget.input;
    }
    // 每次 widget 更新都确保焦点在弹窗
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            widget.onMoveHighlightUp();
            return;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            widget.onMoveHighlightDown();
            return;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onEnter();
            return;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onEsc();
            return;
          }
          if (event.logicalKey == LogicalKeyboardKey.controlLeft || event.logicalKey == LogicalKeyboardKey.controlRight) {
            widget.onCtrl();
            return;
          }
          if (event.logicalKey == LogicalKeyboardKey.backspace) {
            widget.onBackspace();
            return;
          }
          // 字母/数字/中文输入
          if (event.character != null && event.character!.isNotEmpty && RegExp(r'[a-zA-Z0-9\u4e00-\u9fa5]').hasMatch(event.character!)) {
            widget.onInputChar(event.character!);
            return;
          }
        }
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onClose,
              child: Container(color: Colors.black.withOpacity(0.1)),
            ),
          ),
          Center(
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 400,
                constraints: BoxConstraints(maxHeight: 420),
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('选项快速选择', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    SizedBox(height: 8),
                    TextField(
                      controller: _controller,
                      enabled: false,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '输入字母匹配选项',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 12),
                    if (widget.searchResults.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('无匹配选项', style: TextStyle(color: Colors.grey)),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: widget.searchResults.length,
                          itemBuilder: (context, idx) {
                            final option = widget.searchResults[idx];
                            return InkWell(
                              onTap: () => widget.onItemTap(option),
                              child: Container(
                                color: idx == widget.highlightedIndex ? Colors.blue.withOpacity(0.15) : null,
                                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(option.name, style: TextStyle(fontSize: 16))),
                                    if (option.extraCost > 0)
                                      Text('+${option.extraCost}', style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
