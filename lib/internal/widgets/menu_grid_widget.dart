import 'package:flutter/material.dart';
import '../../common/models/menu_item.dart';
import '../../common/models/category.dart';
import '../utils/category_color_mapper.dart';

class MenuGridWidget extends StatelessWidget {
  final List<MenuItem> products;
  final List<Category> categories; // 新增
  final bool isLoading;
  final String? error;
  final void Function(MenuItem) onTap;
  final double Function(String, double) calculateTitleFontSize;
  final bool isCardPressed;
  final int? pressedCardIndex;

  const MenuGridWidget({
    Key? key,
    required this.products,
    required this.categories, // 新增
    required this.isLoading,
    required this.error,
    required this.onTap,
    required this.calculateTitleFontSize,
    required this.isCardPressed,
    required this.pressedCardIndex,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.blue[400]),
            SizedBox(height: 16),
            Text('Loading menu...', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            SizedBox(height: 16),
            Text('Error: ' + error!, style: TextStyle(color: Colors.red[600])),
          ],
        ),
      );
    }
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 1.1,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final item = products[index];
        // 获取分类背景色
        final backgroundColor = CategoryColorMapper.getCategoryBackgroundColor(item.categoryIds, categories);
        final borderColor = CategoryColorMapper.getCategoryBorderColor(item.categoryIds, categories);

        return LayoutBuilder(
          builder: (context, cardConstraints) {
            final isPressed = isCardPressed && pressedCardIndex == index;
            return AnimatedContainer(
              duration: Duration(milliseconds: 120),
              curve: Curves.easeOut,
              transform: isPressed ? Matrix4.translationValues(0, -6, 0) : Matrix4.identity(),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: isPressed
                    ? [BoxShadow(color: Colors.blue.withOpacity(0.18), blurRadius: 16, offset: Offset(0, 6))]
                    : [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: GestureDetector(
                onTapDown: (_) {}, // 交互由父组件处理
                onTapUp: (_) {},
                onTapCancel: () {},
                onTap: () => onTap(item),
                child: Card(
                  elevation: 2,
                  shadowColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: borderColor, width: 1),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [backgroundColor, backgroundColor.withOpacity(0.8)],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: Column(
                              children: [
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.only(right: 20.0),
                                    child: Center(
                                      child: Text(
                                        item.title,
                                        style: TextStyle(
                                          fontSize: calculateTitleFontSize(item.title, cardConstraints.maxWidth),
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                          height: 1.1,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: null,
                                        overflow: TextOverflow.visible,
                                      ),
                                    ),
                                  ),
                                ),
                                if (cardConstraints.maxHeight > 60)
                                  Container(
                                    margin: EdgeInsets.only(top: 2),
                                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[100],
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(color: Colors.blue[300]!, width: 0.5),
                                    ),
                                    child: Text(
                                      item.acronym ?? '', // 兼容null
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.blue[800],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Text(
                              item.code.length > 4 ? item.code.substring(0, 4) : item.code,
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
