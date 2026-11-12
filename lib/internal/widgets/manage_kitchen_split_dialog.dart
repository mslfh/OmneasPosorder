import 'package:flutter/material.dart';
import '../../common/models/kitchen_split_group.dart';
import '../../common/models/menu_item.dart';
import '../../common/models/category.dart';
import '../../common/services/kitchen_split_service.dart';
import '../utils/ui_helper.dart';

class ManageKitchenSplitDialog extends StatefulWidget {
  final List<MenuItem> allProducts;
  final List<Category> categories;
  final VoidCallback onSaved;

  const ManageKitchenSplitDialog({
    Key? key,
    required this.allProducts,
    required this.categories,
    required this.onSaved,
  }) : super(key: key);

  static Future<void> show({
    required BuildContext context,
    required List<MenuItem> allProducts,
    required List<Category> categories,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ManageKitchenSplitDialog(
        allProducts: allProducts,
        categories: categories,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<ManageKitchenSplitDialog> createState() =>
      _ManageKitchenSplitDialogState();
}

class _ManageKitchenSplitDialogState extends State<ManageKitchenSplitDialog> {
  final KitchenSplitService _splitService = KitchenSplitService();
  List<KitchenSplitGroup> _groups = [];
  KitchenSplitGroup? _selectedGroup;
  bool _isLoading = true;

  // 搜索相关
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Category? _selectedCategoryForAdd;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    final loaded = await _splitService.getSplitGroups();
    if (mounted) {
      setState(() {
        _groups = loaded;
        if (_groups.isNotEmpty) {
          _selectedGroup = _groups.first;
        }
        _isLoading = false;
      });
    }
  }

  void _addGroup() {
    final newId = _groups.isEmpty
        ? 1
        : (_groups.map((g) => g.id).reduce((a, b) => a > b ? a : b) + 1);
    final newGroup = KitchenSplitGroup(
      id: newId,
      name: '分单 $newId',
      productIds: [],
    );

    setState(() {
      _groups.add(newGroup);
      _selectedGroup = newGroup;
    });
  }

  void _deleteGroup(KitchenSplitGroup group) {
    setState(() {
      _groups.removeWhere((g) => g.id == group.id);
      if (_selectedGroup?.id == group.id) {
        _selectedGroup = _groups.isNotEmpty ? _groups.first : null;
      }
    });
  }

  void _renameGroup(KitchenSplitGroup group) {
    final controller = TextEditingController(text: group.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名分单打印项'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入分单名称（如：热菜单、冷盘单）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                setState(() {
                  final index = _groups.indexWhere((g) => g.id == group.id);
                  if (index != -1) {
                    _groups[index] = _groups[index].copyWith(name: newName);
                    if (_selectedGroup?.id == group.id) {
                      _selectedGroup = _groups[index];
                    }
                  }
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 移除指定商品
  void _removeProductFromGroup(int productId) {
    if (_selectedGroup == null) return;
    setState(() {
      final newProductIds = List<int>.from(_selectedGroup!.productIds)
        ..remove(productId);
      final updatedGroup = _selectedGroup!.copyWith(productIds: newProductIds);

      final index = _groups.indexWhere((g) => g.id == _selectedGroup!.id);
      if (index != -1) {
        _groups[index] = updatedGroup;
        _selectedGroup = updatedGroup;
      }
    });
  }

  /// 添加指定商品到当前选中的分单组（自动从其他组中移除，保证一个商品只归属一个分单项）
  void _addProductToGroup(int productId) {
    if (_selectedGroup == null) return;
    setState(() {
      // 先从所有组中移除该商品
      for (int i = 0; i < _groups.length; i++) {
        final list = List<int>.from(_groups[i].productIds)..remove(productId);
        _groups[i] = _groups[i].copyWith(productIds: list);
      }

      // 将商品加入当前组
      final targetIndex = _groups.indexWhere((g) => g.id == _selectedGroup!.id);
      if (targetIndex != -1) {
        final currentList = List<int>.from(_groups[targetIndex].productIds);
        if (!currentList.contains(productId)) {
          currentList.add(productId);
        }
        _groups[targetIndex] =
            _groups[targetIndex].copyWith(productIds: currentList);
        _selectedGroup = _groups[targetIndex];
      }
    });
  }

  /// 批量添加某一分类下的所有商品
  void _addCategoryProductsToGroup(int categoryId) {
    if (_selectedGroup == null) return;
    final catProducts = widget.allProducts
        .where((p) => p.categoryIds.contains(categoryId))
        .map((p) => p.id)
        .toList();

    if (catProducts.isEmpty) {
      UIHelper.showToast(context, '该分类下没有商品', backgroundColor: Colors.red);
      return;
    }

    setState(() {
      for (final pId in catProducts) {
        for (int i = 0; i < _groups.length; i++) {
          final list = List<int>.from(_groups[i].productIds)..remove(pId);
          _groups[i] = _groups[i].copyWith(productIds: list);
        }
      }

      final targetIndex = _groups.indexWhere((g) => g.id == _selectedGroup!.id);
      if (targetIndex != -1) {
        final currentList = List<int>.from(_groups[targetIndex].productIds);
        for (final pId in catProducts) {
          if (!currentList.contains(pId)) {
            currentList.add(pId);
          }
        }
        _groups[targetIndex] =
            _groups[targetIndex].copyWith(productIds: currentList);
        _selectedGroup = _groups[targetIndex];
      }
    });

    UIHelper.showToast(context, '已添加分类下的 ${catProducts.length} 项商品到当前分单组',
        backgroundColor: Colors.green);
  }

  Future<void> _saveAll() async {
    try {
      await _splitService.saveSplitGroups(_groups);
      widget.onSaved();
      if (mounted) {
        UIHelper.showToast(context, '后厨分单配置保存成功！',
            backgroundColor: Colors.green);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        UIHelper.showToast(context, '保存失败: $e', backgroundColor: Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 850,
        height: 560,
        padding: const EdgeInsets.all(20),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // 标题区
                  Row(
                    children: [
                      const Icon(Icons.print, color: Colors.orange, size: 28),
                      const SizedBox(width: 10),
                      const Text(
                        '后厨打印分单配置 (Kitchen Split Setup)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const Divider(),
                  // 内容区 (左侧分单组，右侧菜品管理)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 左侧分单组列表
                        SizedBox(
                          width: 240,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    '分单打印项列表',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: _addGroup,
                                    icon: const Icon(Icons.add, size: 14),
                                    label: const Text('新增分单',
                                        style: TextStyle(fontSize: 12)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                    ),
                                  )
                                ],
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey[300]!),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ListView.separated(
                                    itemCount: _groups.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final group = _groups[index];
                                      final isSelected =
                                          _selectedGroup?.id == group.id;
                                      return ListTile(
                                        dense: true,
                                        selected: isSelected,
                                        selectedTileColor: Colors.orange[50],
                                        title: Text(
                                          group.name,
                                          style: TextStyle(
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isSelected
                                                ? Colors.orange[900]
                                                : Colors.black87,
                                          ),
                                        ),
                                        subtitle: Text(
                                          '包含 ${group.productIds.length} 项商品',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[600]),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.edit,
                                                  size: 16, color: Colors.blue),
                                              onPressed: () =>
                                                  _renameGroup(group),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 16,
                                                  color: Colors.red),
                                              onPressed: () =>
                                                  _deleteGroup(group),
                                            ),
                                          ],
                                        ),
                                        onTap: () {
                                          setState(() {
                                            _selectedGroup = group;
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // 右侧菜品关联区
                        Expanded(
                          child: _selectedGroup == null
                              ? Center(
                                  child: Text(
                                    '请在左侧选择或新增分单项',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                )
                              : _buildGroupItemManager(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  // 底部操作按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _saveAll,
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('保存分单配置'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGroupItemManager() {
    final group = _selectedGroup!;
    final groupProductIds = Set<int>.from(group.productIds);

    final groupProducts = widget.allProducts
        .where((p) => groupProductIds.contains(p.id))
        .toList();

    // 搜索可添加商品
    List<MenuItem> searchResults = [];
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      searchResults = widget.allProducts.where((p) {
        final matchesQuery = p.title.toLowerCase().contains(q) ||
            p.code.toLowerCase().contains(q) ||
            (p.acronym?.toLowerCase().contains(q) ?? false);
        return matchesQuery;
      }).toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 工具栏：按分类一键添加 & 菜品搜索框
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Text('按分类批量添加: ',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<Category>(
                      isDense: true,
                      value: _selectedCategoryForAdd,
                      decoration: const InputDecoration(
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        border: OutlineInputBorder(),
                        hintText: '选择分类',
                      ),
                      items: widget.categories.map((cat) {
                        return DropdownMenuItem<Category>(
                          value: cat,
                          child: Text(cat.title,
                              style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (cat) {
                        setState(() {
                          _selectedCategoryForAdd = cat;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _selectedCategoryForAdd == null
                        ? null
                        : () {
                            _addCategoryProductsToGroup(
                                _selectedCategoryForAdd!.id);
                          },
                    icon: const Icon(Icons.category, size: 14),
                    label: const Text('添加全分类菜品', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('直接搜索添加: ',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        hintText: '搜索菜品名称 / 编码',
                        border: const OutlineInputBorder(),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                  });
                                },
                              )
                            : const Icon(Icons.search, size: 16),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 搜索结果展开浮层（若有搜索内容）
        if (_searchQuery.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 130),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.blue[300]!),
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4)
                ],
              ),
              child: searchResults.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text('无匹配菜品', style: TextStyle(fontSize: 12)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: searchResults.length,
                      itemBuilder: (ctx, idx) {
                        final item = searchResults[idx];
                        final isAdded = groupProductIds.contains(item.id);
                        return ListTile(
                          dense: true,
                          title: Text('#${item.code} ${item.title}',
                              style: const TextStyle(fontSize: 12)),
                          subtitle: Text(
                              '\$${item.sellingPrice.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 11)),
                          trailing: isAdded
                              ? const Text('已在当前组',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.green))
                              : ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                  ),
                                  onPressed: () {
                                    _addProductToGroup(item.id);
                                  },
                                  child: const Text('添加',
                                      style: TextStyle(fontSize: 11)),
                                ),
                        );
                      },
                    ),
            ),
          ),
        ],

        const SizedBox(height: 8),
        Text(
          '【${group.name}】已关联菜品列表 (${groupProducts.length} 项):',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 4),

        // 已关联菜品列表网格/列表
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: groupProducts.isEmpty
                ? Center(
                    child: Text(
                      '暂无关联菜品，可通过上方分类或搜索进行添加',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    itemCount: groupProducts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = groupProducts[index];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.orange[100],
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                                fontSize: 10, color: Colors.orange[900]),
                          ),
                        ),
                        title: Text('#${item.code} ${item.title}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            '售价: \$${item.sellingPrice.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 11)),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Colors.red, size: 20),
                          onPressed: () => _removeProductFromGroup(item.id),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
