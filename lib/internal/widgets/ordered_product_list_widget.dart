import 'package:flutter/material.dart';
import '../utils/order_selected.dart';

class OrderedProductListWidget extends StatelessWidget {
  final List<SelectedProduct> orderedProducts;
  final SelectedProduct? selectedOrderedProduct;
  final void Function(SelectedProduct) onSelect;
  final void Function(SelectedProduct) onDoubleTap;
  final void Function(SelectedProduct) onIncrease;
  final void Function(SelectedProduct) onDecrease;
  final double minHeight;
  final double maxHeight;
  final double baseItemHeight;
  final double optionHeight;
  final int crossAxisCount;
  final double containerWidth;
  final double actualHeight;
  final double maxCardHeight;

  const OrderedProductListWidget({
    Key? key,
    required this.orderedProducts,
    required this.selectedOrderedProduct,
    required this.onSelect,
    required this.onDoubleTap,
    required this.onIncrease,
    required this.onDecrease,
    required this.minHeight,
    required this.maxHeight,
    required this.baseItemHeight,
    required this.optionHeight,
    required this.crossAxisCount,
    required this.containerWidth,
    required this.actualHeight,
    required this.maxCardHeight,
  }) : super(key: key);

  double _calculateTitleFontSize(String title, double containerWidth) {
    final baseSize = 16.0;
    final maxSize = 18.0;
    final minSize = 10.0;
    final estimatedCharWidth = baseSize * 0.6;
    final availableWidth = containerWidth - 40;
    final maxCharsPerLine = (availableWidth / estimatedCharWidth).floor();
    if (title.length <= maxCharsPerLine) {
      return baseSize;
    } else if (title.length <= maxCharsPerLine * 2) {
      return (baseSize - 1).clamp(minSize, maxSize);
    } else {
      return (baseSize - 3).clamp(minSize, maxSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: actualHeight,
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: orderedProducts.isEmpty
            ? Center(
                child: Text(
                  'No items ordered yet',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              )
            : ListView(
                physics: actualHeight >= maxHeight
                    ? AlwaysScrollableScrollPhysics()
                    : NeverScrollableScrollPhysics(),
                children: [
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: orderedProducts.map((ordered) {
                      final cardWidth = (containerWidth - 8) / crossAxisCount;
                      return SizedBox(
                        width: cardWidth,
                        child: GestureDetector(
                          onTap: () => onSelect(ordered),
                          onDoubleTap: () => onDoubleTap(ordered),
                          child: LayoutBuilder(
                            builder: (context, orderedCardConstraints) {
                              final isSelected = selectedOrderedProduct == ordered;
                              return Card(
                                margin: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isSelected ? Colors.blue[600]! : Colors.grey[300]!,
                                    width: 1.0,
                                  ),
                                ),
                                elevation: isSelected ? 8 : 2,
                                shadowColor: isSelected ? Colors.blue[200] : Colors.grey[300],
                                color: Colors.white,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              flex: 4,
                                              child: Text(
                                                ordered.product.title,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: _calculateTitleFontSize(ordered.product.title, orderedCardConstraints.maxWidth * 0.7),
                                                  height: 1.1,
                                                  color: isSelected ? Colors.blue[800] : Colors.black87,
                                                ),
                                                maxLines: null,
                                                overflow: TextOverflow.visible,
                                              ),
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                GestureDetector(
                                                  onTap: () => onDecrease(ordered),
                                                  child: Container(
                                                    width: 20,
                                                    height: 20,
                                                    margin: EdgeInsets.only(left: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red[100],
                                                      borderRadius: BorderRadius.circular(10),
                                                      border: Border.all(color: Colors.red[200]!, width: 0.5),
                                                    ),
                                                    child: Icon(
                                                      Icons.remove,
                                                      size: 12,
                                                      color: Colors.red[700],
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  width: 28,
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    '${ordered.quantity}',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                      color: Colors.blue[700],
                                                    ),
                                                  ),
                                                ),
                                                GestureDetector(
                                                  onTap: () => onIncrease(ordered),
                                                  child: Container(
                                                    width: 20,
                                                    height: 20,
                                                    decoration: BoxDecoration(
                                                      color: Colors.green[100],
                                                      borderRadius: BorderRadius.circular(10),
                                                      border: Border.all(color: Colors.green[200]!, width: 0.5),
                                                    ),
                                                    child: Icon(
                                                      Icons.add,
                                                      size: 12,
                                                      color: Colors.green[700],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Expanded(child: Container()),
                                            Text(
                                              '￥${ordered.product.sellingPrice.toStringAsFixed(2)}',
                                              style: TextStyle(fontSize: 9, color: Colors.green[700]),
                                            ),
                                          ],
                                        ),
                                        ...ordered.options.map((opt) {
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 1.0),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    ' - ${opt.option.name}',
                                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[600]),
                                                    overflow: TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  ),
                                                ),
                                                if (opt.option.extraCost > 0)
                                                  Text(
                                                    '+\$ ${opt.option.extraCost.toStringAsFixed(2)}',
                                                    style: TextStyle(fontSize: 8, color: Colors.red),
                                                  ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
      ),
    );
  }
}

