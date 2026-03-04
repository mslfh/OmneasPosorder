import 'package:flutter/material.dart';
import '../../common/models/menu_item.dart';
import '../../common/models/menu_option.dart';

class QuickInputOverlay extends StatelessWidget {
  final String input;
  final List<dynamic> searchResults; // 可能是 MenuItem 或 MenuOption
  final int highlightedIndex;
  final bool isSearchingOptions;
  final VoidCallback? onClose;
  final Function(MenuItem)? onItemTap;
  final Function(MenuOption)? onOptionTap;

  const QuickInputOverlay({
    Key? key,
    required this.input,
    required this.searchResults,
    required this.highlightedIndex,
    this.isSearchingOptions = false,
    this.onClose,
    this.onItemTap,
    this.onOptionTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 不要重新过滤，直接使用原始顺序（QuickInputManager 中已保证商品在前）
    final bool hasAnyResults = searchResults.isNotEmpty;

    // Debug: 打印搜索结果和高亮索引
    try {
      print('[DEBUG OVERLAY] searchResults.length=${searchResults.length}, highlightedIndex=$highlightedIndex');
      for (int i = 0; i < searchResults.length; i++) {
        final item = searchResults[i];
        if (item is MenuItem) {
          print('[DEBUG OVERLAY] [$i] MenuItem: ${item.title}');
        } else if (item is MenuOption) {
          print('[DEBUG OVERLAY] [$i] MenuOption: ${item.name}');
        }
      }
    } catch (e) {}

    return Positioned(
      left: 120,
      top: 80,
      child: Material(
        elevation: 8,
        color: Colors.transparent,
        child: Container(
          width: 400,
          constraints: BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 输入显示区域
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isSearchingOptions ? Colors.purple.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSearchingOptions ? Icons.tune : Icons.search,
                      size: 18,
                      color: isSearchingOptions ? Colors.purple.shade600 : Colors.blue.shade600,
                    ),
                    SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '快捷输入: "$input"',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isSearchingOptions ? Colors.purple.shade700 : Colors.blue.shade700,
                          ),
                        ),
                        if (isSearchingOptions)
                          Text(
                            '(搜索菜品选项)',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.purple.shade600,
                            ),
                          ),
                      ],
                    ),
                    Spacer(),
                    if (onClose != null)
                      InkWell(
                        onTap: onClose,
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),

              // 搜索结果区域
              if (!hasAnyResults)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 18),
                      SizedBox(width: 8),
                      Text(
                        '无匹配结果',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...List.generate(searchResults.length, (index) {
                          final item = searchResults[index];
                          final isHighlighted = index == highlightedIndex;

                          if (item is MenuItem) {
                            // 只在第一个 MenuItem 时显示"菜品"标题
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (index == 0 || (index > 0 && searchResults[index - 1] is! MenuItem))
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                                    child: Text('菜品', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                                  ),
                                _buildProductItem(item, isHighlighted),
                              ],
                            );
                          } else if (item is MenuOption) {
                            // 只在第一个 MenuOption 时显示"选项"标题
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (index == 0 || (index > 0 && searchResults[index - 1] is! MenuOption))
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                                    child: Text('选项', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.purple.shade700)),
                                  ),
                                _buildOptionItem(item, isHighlighted),
                              ],
                            );
                          }
                          return SizedBox.shrink();
                        }),
                      ],
                    ),
                  ),
                ),

              // 操作提示
              if (hasAnyResults)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: Text(
                    '↑↓ 切换选择  Enter 确认  ESC 取消',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductItem(MenuItem item, bool isHighlighted) {
    return InkWell(
      onTap: () => onItemTap?.call(item),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: isHighlighted ? Colors.blue.shade100 : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isHighlighted ? Border.all(color: Colors.blue.shade300) : null,
        ),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Acronym标签
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                item.acronym ?? '',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(width: 12),

            // 产品信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isHighlighted ? Colors.blue.shade800 : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.code.isNotEmpty)
                    Text(
                      'Code: ${item.code}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),

            // 价格
            Text(
              '\$${item.sellingPrice.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isHighlighted ? Colors.blue.shade700 : Colors.green.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionItem(MenuOption option, bool isHighlighted) {
    return InkWell(
      onTap: () => onOptionTap?.call(option),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: isHighlighted ? Colors.purple.shade100 : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isHighlighted ? Border.all(color: Colors.purple.shade300) : null,
        ),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // 选项类型标签
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purple.shade600,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                option.type,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(width: 12),

            // 选项信息
            Expanded(
              child: Text(
                option.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isHighlighted ? Colors.purple.shade800 : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 额外费用
            if (option.extraCost > 0)
              Text(
                '+\$${option.extraCost.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isHighlighted ? Colors.purple.shade700 : Colors.red.shade600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
