import 'package:flutter/material.dart';
import '../../common/models/menu_item.dart';
import '../../common/models/category.dart';
import '../../common/models/menu_option.dart';
import '../../common/services/api_service.dart';
import '../../common/services/cache_service.dart';

/// 管理员相关对话框和菜品编辑管理
class AdminDialogManager {
  final BuildContext context;

  AdminDialogManager(this.context);

  /// 显示编辑菜品对话框
  void showEditProductDialog(
    MenuItem product,
    List<Category> categories,
    Function() onSaved,
  ) {
    final codeController = TextEditingController(text: product.code);
    final titleController = TextEditingController(text: product.title);
    final acronymController = TextEditingController(text: product.acronym);
    final priceController = TextEditingController(text: product.sellingPrice.toString());
    final stockController = TextEditingController(text: product.stock.toString());
    String? selectedCategoryId = product.categoryIds.isNotEmpty ? product.categoryIds.first.toString() : null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('编辑菜品'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                decoration: InputDecoration(labelText: '菜品代码', border: OutlineInputBorder()),
              ),
              SizedBox(height: 12),
              TextField(
                controller: titleController,
                decoration: InputDecoration(labelText: '菜品名称', border: OutlineInputBorder()),
              ),
              SizedBox(height: 12),
              TextField(
                controller: acronymController,
                decoration: InputDecoration(labelText: '快捷键', border: OutlineInputBorder()),
              ),
              SizedBox(height: 12),
              TextField(
                controller: priceController,
                decoration: InputDecoration(labelText: '售价', border: OutlineInputBorder()),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
              SizedBox(height: 12),
              TextField(
                controller: stockController,
                decoration: InputDecoration(labelText: '库存', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 12),
              DropdownButton<String>(
                value: selectedCategoryId,
                isExpanded: true,
                hint: Text('选择分类'),
                items: categories
                    .map((cat) => DropdownMenuItem(
                          value: cat.id.toString(),
                          child: Text(cat.title),
                        ))
                    .toList(),
                onChanged: (value) {
                  selectedCategoryId = value;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _saveProductChanges(
                product,
                codeController,
                titleController,
                acronymController,
                priceController,
                stockController,
                selectedCategoryId,
                onSaved,
              );
              Navigator.pop(context);
            },
            child: Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 保存菜品修改
  Future<void> _saveProductChanges(
    MenuItem product,
    TextEditingController codeController,
    TextEditingController titleController,
    TextEditingController acronymController,
    TextEditingController priceController,
    TextEditingController stockController,
    String? selectedCategoryId,
    Function() onSaved,
  ) async {
    final newPrice = double.tryParse(priceController.text);
    final newStock = int.tryParse(stockController.text);

    if (newPrice == null) {
      _showSnackBar('价格格式错误', Colors.red);
      return;
    }

    if (newStock == null) {
      _showSnackBar('库存格式错误', Colors.red);
      return;
    }

    try {
      final api = ApiService();
      final List<int> categoryIds = [];
      if (selectedCategoryId != null && selectedCategoryId.isNotEmpty) {
        final catId = int.tryParse(selectedCategoryId);
        if (catId != null) {
          categoryIds.add(catId);
        }
      } else {
        categoryIds.addAll(product.categoryIds);
      }

      final updateData = {
        'code': codeController.text,
        'title': titleController.text,
        'acronym': acronymController.text.isEmpty ? null : acronymController.text,
        'sellingPrice': newPrice,
        'stock': newStock,
        'categoryIds': categoryIds,
      };

      await api.put('products/${product.id.toString()}', data: updateData);
      await CacheService.clearMenuCaches();
      _showSnackBar('菜品已更新', Colors.green);
      onSaved();
    } catch (e) {
      _showSnackBar('更新失败: $e', Colors.red);
    }
  }

  /// 显示管理选项对话框
  void showManageOptionsDialog(
    Map<String, List<MenuOption>> optionGroups,
    Function() onAddOption,
    Function() onEditOption,
    Function() onDeleteOption,
    Function(String) onAddOptionGroup,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('管理菜品选项'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...optionGroups.entries.map((entry) {
                  final groupType = entry.key;
                  final options = entry.value;
                  return ExpansionTile(
                    title: Text(groupType),
                    children: [
                      ...options.map((option) => ListTile(
                        title: Text(option.name),
                        subtitle: Text('额外费用: \$${option.extraCost.toStringAsFixed(2)}'),
                        trailing: PopupMenuButton(
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              child: Text('编辑'),
                              onTap: () {
                                Future.delayed(Duration(milliseconds: 100), () {
                                  onEditOption();
                                });
                              },
                            ),
                            PopupMenuItem(
                              child: Text('删除'),
                              onTap: () {
                                Future.delayed(Duration(milliseconds: 100), () {
                                  onDeleteOption();
                                });
                              },
                            ),
                          ],
                        ),
                      )).toList(),
                      ListTile(
                        leading: Icon(Icons.add),
                        title: Text('添加选项'),
                        onTap: () {
                          Navigator.pop(context);
                          onAddOption();
                        },
                      ),
                    ],
                  );
                }).toList(),
                SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showAddOptionGroupDialog(onAddOptionGroup);
                  },
                  icon: Icon(Icons.add),
                  label: Text('新增选项组'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 添加选项对话框
  void showAddOptionDialog(
    String groupType,
    Function(String, double) onAdd,
  ) {
    final nameController = TextEditingController();
    final costController = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('添加选项 - $groupType'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: '选项名称', border: OutlineInputBorder()),
            ),
            SizedBox(height: 12),
            TextField(
              controller: costController,
              decoration: InputDecoration(labelText: '额外费用', border: OutlineInputBorder()),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final cost = double.tryParse(costController.text) ?? 0;
              Navigator.pop(context);
              onAdd(nameController.text, cost);
            },
            child: Text('添加'),
          ),
        ],
      ),
    );
  }

  /// 编辑选项对话框
  void showEditOptionDialog(
    MenuOption option,
    Function(String, double) onEdit,
  ) {
    final nameController = TextEditingController(text: option.name);
    final costController = TextEditingController(text: option.extraCost.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('编辑选项'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: '选项名称', border: OutlineInputBorder()),
            ),
            SizedBox(height: 12),
            TextField(
              controller: costController,
              decoration: InputDecoration(labelText: '额外费用', border: OutlineInputBorder()),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final cost = double.tryParse(costController.text) ?? 0;
              Navigator.pop(context);
              onEdit(nameController.text, cost);
            },
            child: Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 删除选项确认对话框
  void showDeleteOptionDialog(
    MenuOption option,
    Function() onDelete,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除选项'),
        content: Text('确认要删除选项 "${option.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 添加选项组对话框
  void _showAddOptionGroupDialog(Function(String) onAdd) {
    final groupNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('新增选项组'),
        content: TextField(
          controller: groupNameController,
          decoration: InputDecoration(
            labelText: '选项组名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              if (groupNameController.text.isEmpty) {
                _showSnackBar('请输入选项组名称', Colors.orange);
                return;
              }
              Navigator.pop(context);
              onAdd(groupNameController.text);
            },
            child: Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }
}

