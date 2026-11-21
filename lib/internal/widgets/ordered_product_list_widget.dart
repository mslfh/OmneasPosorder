import 'package:flutter/material.dart';
import '../utils/order_selected.dart';
import '../../common/services/language_service.dart';

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
  final double? actualHeight;
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
    this.actualHeight,
    required this.maxCardHeight,
  }) : super(key: key);

  double _calculateTitleFontSize(String title, double containerWidth) {
    const baseSize = 16.0;
    const maxSize = 18.0;
    const minSize = 10.0;
    const estimatedCharWidth = baseSize * 0.6;
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
    final bool isScrollable = actualHeight == null || actualHeight! >= maxHeight;

    return Container(
      height: actualHeight,
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: orderedProducts.isEmpty
            ? Center(
                child: Text(
                  'empty_cart_msg'.tr,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              )
            : ListView(
                physics: isScrollable
                    ? const AlwaysScrollableScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
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
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                ordered.product.title,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: _calculateTitleFontSize(ordered.product.title, orderedCardConstraints.maxWidth * 0.55),
                                                  height: 1.1,
                                                  color: isSelected ? Colors.blue[800] : Colors.black87,
                                                ),
                                                maxLines: null,
                                                overflow: TextOverflow.visible,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                GestureDetector(
                                                  onTap: () => onDecrease(ordered),
                                                  child: Container(
                                                    width: 22,
                                                    height: 22,
                                                    decoration: BoxDecoration(
                                                      color: Colors.red[100],
                                                      borderRadius: BorderRadius.circular(11),
                                                      border: Border.all(color: Colors.red[200]!, width: 0.5),
                                                    ),
                                                    child: Icon(
                                                      Icons.remove,
                                                      size: 14,
                                                      color: Colors.red[700],
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  width: 30,
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    '${ordered.quantity}',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w900,
                                                      fontSize: 16,
                                                      color: Colors.blue[800],
                                                    ),
                                                  ),
                                                ),
                                                GestureDetector(
                                                  onTap: () => onIncrease(ordered),
                                                  child: Container(
                                                    width: 22,
                                                    height: 22,
                                                    decoration: BoxDecoration(
                                                      color: Colors.green[100],
                                                      borderRadius: BorderRadius.circular(11),
                                                      border: Border.all(color: Colors.green[200]!, width: 0.5),
                                                    ),
                                                    child: Icon(
                                                      Icons.add,
                                                      size: 14,
                                                      color: Colors.green[700],
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Container(
                                                  width: 58,
                                                  alignment: Alignment.centerRight,
                                                  child: Text(
                                                    '\$${ordered.product.sellingPrice.toStringAsFixed(2)}',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w900,
                                                      color: Color(0xFF1B4D3E),
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        ...ordered.options.map((opt) {
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 2.0),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    ' - ${opt.option.name}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.grey[700],
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  ),
                                                ),
                                                if (opt.option.extraCost > 0)
                                                  Text(
                                                    '+\$${opt.option.extraCost.toStringAsFixed(2)}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.red[700],
                                                    ),
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
