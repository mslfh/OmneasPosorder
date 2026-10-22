import 'package:flutter/material.dart';
import '../../common/models/menu_item.dart';
import '../../common/models/category.dart';
import '../../common/services/api_service.dart';
import '../utils/ui_helper.dart';

class EditProductDialog {
  static Future<void> show({
    required BuildContext context,
    required MenuItem product,
    required List<Category> categories,
    required VoidCallback onProductUpdated,
    required void Function(MenuItem) onShowSoldOut,
  }) {
    final codeController = TextEditingController(text: product.code);
    final titleController = TextEditingController(text: product.title);
    final kitchenPrintNameController =
        TextEditingController(text: product.kitchenPrintName ?? '');
    final acronymController =
        TextEditingController(text: product.acronym ?? '');
    final priceController =
        TextEditingController(text: product.sellingPrice.toString());
    final stockController =
        TextEditingController(text: product.stock.toString());

    bool isPrintable = product.isPrintable;
    String? selectedCategoryId = product.categoryIds.isNotEmpty
        ? product.categoryIds.first.toString()
        : null;

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.edit, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '编辑菜品 - ${product.title}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 沽清快捷操作条
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: product.isSoldOut ? Colors.red[50] : Colors.amber[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: product.isSoldOut ? Colors.red[200]! : Colors.amber[300]!,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            product.isSoldOut ? Icons.no_meals : Icons.check_circle,
                            color: product.isSoldOut ? Colors.red : Colors.green[700],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              product.isSoldOut ? '当前状态：已沽清 (Sold Out)' : '当前状态：正常在售',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: product.isSoldOut ? Colors.red[800] : Colors.green[800],
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(dialogContext);
                              onShowSoldOut(product);
                            },
                            icon: const Icon(Icons.edit_attributes, size: 16),
                            label: const Text('设置沽清', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeController,
                      decoration: const InputDecoration(
                        labelText: '菜品代码 (code)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: '菜品名称 (title)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: kitchenPrintNameController,
                      decoration: const InputDecoration(
                        labelText: '后厨打印名 (kitchen_print_name)',
                        hintText: '留空则默认使用菜品名称',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: acronymController,
                      decoration: const InputDecoration(
                        labelText: '快捷键 / 缩写 (acronym)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: priceController,
                            decoration: const InputDecoration(
                              labelText: '售价 (sellingPrice)',
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixText: '\$ ',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: stockController,
                            decoration: const InputDecoration(
                              labelText: '库存 (stock)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCategoryId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '所属类别',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      hint: const Text('选择分类'),
                      items: categories.map((cat) {
                        return DropdownMenuItem(
                          value: cat.id.toString(),
                          child: Text(cat.title),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedCategoryId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('是否可打印 (后厨打单)'),
                      subtitle: Text(
                        isPrintable ? '下单时会发送至后厨打印机' : '下单时不打印后厨小票',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: isPrintable,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (bool val) {
                        setDialogState(() {
                          isPrintable = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final newPrice = double.tryParse(priceController.text);
                  final newStock = int.tryParse(stockController.text);

                  if (newPrice == null) {
                    UIHelper.showSnackBar(context, '价格格式错误', backgroundColor: Colors.red);
                    return;
                  }

                  if (newStock == null) {
                    UIHelper.showSnackBar(context, '库存格式错误', backgroundColor: Colors.red);
                    return;
                  }

                  try {
                    final List<int> categoryIds = [];
                    if (selectedCategoryId != null &&
                        selectedCategoryId!.isNotEmpty) {
                      final catId = int.tryParse(selectedCategoryId!);
                      if (catId != null) {
                        categoryIds.add(catId);
                      }
                    } else {
                      categoryIds.addAll(product.categoryIds);
                    }

                    final kitchenPrintNameVal = kitchenPrintNameController.text.trim().isEmpty
                        ? null
                        : kitchenPrintNameController.text.trim();
                    final acronymVal = acronymController.text.trim().isEmpty
                        ? null
                        : acronymController.text.trim();

                    final updateData = {
                      'code': codeController.text,
                      'title': titleController.text,
                      'kitchen_print_name': kitchenPrintNameVal,
                      'kitchenPrintName': kitchenPrintNameVal,
                      'acronym': acronymVal,
                      'sellingPrice': newPrice,
                      'selling_price': newPrice,
                      'stock': newStock,
                      'is_printable': isPrintable,
                      'isPrintable': isPrintable,
                      'categoryIds': categoryIds,
                      'category_ids': categoryIds,
                    };

                    final api = ApiService();
                    await api.put('products/${product.id}', data: updateData);

                    if (!ctx.mounted) return;
                    Navigator.pop(dialogContext);

                    onProductUpdated();

                    UIHelper.showSnackBar(context, '菜品已更新',
                        backgroundColor: Colors.green);
                  } catch (e) {
                    if (!ctx.mounted) return;
                    UIHelper.showSnackBar(context, '更新失败: $e',
                        backgroundColor: Colors.red);
                  }
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }
}
