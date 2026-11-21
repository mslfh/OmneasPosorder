import 'package:flutter/material.dart';
import '../../common/models/category.dart';
import '../../common/services/language_service.dart';
import '../utils/category_color_mapper.dart';
import '../utils/category_display_sort_mapper.dart';
import '../utils/category_priority_mapper.dart';

class CategorySidebarWidget extends StatefulWidget {
  final List<Category> categories;
  final void Function(Category? category)? onCategoryTap;
  final bool isAdminMode;
  final VoidCallback? onManageKitchenSplit;
  final VoidCallback? onCategoryColorChanged;

  const CategorySidebarWidget({
    super.key,
    required this.categories,
    this.onCategoryTap,
    this.isAdminMode = false,
    this.onManageKitchenSplit,
    this.onCategoryColorChanged,
  });

  @override
  State<CategorySidebarWidget> createState() => _CategorySidebarWidgetState();
}

class _CategorySidebarWidgetState extends State<CategorySidebarWidget> {
  @override
  void initState() {
    super.initState();
    Future.wait([
      CategoryColorMapper.loadCustomColors(),
      CategoryDisplaySortMapper.loadDisplaySortOrders(),
      CategoryPriorityMapper.loadPriorities(),
    ]).then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _moveCategoryOrder(Category category, bool isUp) async {
    final displayList = _buildHierarchicalCategories(widget.categories);
    final isTop = category.parentId == null ||
        category.parentId == 0 ||
        !widget.categories.any((c) => c.id == category.parentId);

    final siblings = displayList.where((c) {
      if (isTop) {
        return c.parentId == null ||
            c.parentId == 0 ||
            !widget.categories.any((p) => p.id == c.parentId);
      } else {
        return c.parentId == category.parentId;
      }
    }).toList();

    final currentIndex = siblings.indexWhere((c) => c.id == category.id);
    if (currentIndex == -1) return;
    final targetIndex = isUp ? currentIndex - 1 : currentIndex + 1;
    if (targetIndex < 0 || targetIndex >= siblings.length) return;

    final targetCategory = siblings[targetIndex];
    siblings[currentIndex] = targetCategory;
    siblings[targetIndex] = category;

    for (int i = 0; i < siblings.length; i++) {
      await CategoryDisplaySortMapper.setCategoryDisplaySort(siblings[i].id, i + 1);
    }

    if (mounted) {
      setState(() {});
    }
    widget.onCategoryColorChanged?.call();
  }

  void _showCategorySettingsDialog(Category category) {
    final currentColor = CategoryColorMapper.getColorForCategory(
      category,
      allCategories: widget.categories,
    );
    final isCustomColor = CategoryColorMapper.hasCustomColor(category.id);
    final isCustomDisplaySort = CategoryDisplaySortMapper.hasCustomDisplaySort(category.id);
    final currentDisplaySort = CategoryDisplaySortMapper.getDisplaySortForCategoryId(category.id);
    final isCustomPrintPriority = CategoryPriorityMapper.hasCustomPriority(category.id);
    final currentPrintPriority = CategoryPriorityMapper.getPriorityForCategoryId(category.id);

    Color selectedColor = currentColor;
    final displaySortController = TextEditingController(
      text: isCustomDisplaySort ? currentDisplaySort.toString() : '',
    );
    final printPriorityController = TextEditingController(
      text: isCustomPrintPriority ? currentPrintPriority.toString() : '',
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: selectedColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black26, width: 1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'category_settings'.trParams({'title': category.title}),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. 界面显示排序设置
                    Row(
                      children: [
                        const Icon(Icons.sort, size: 18, color: Colors.blue),
                        const SizedBox(width: 6),
                        Text(
                          'category_display_sort'.tr,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'category_display_sort_hint'.tr,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: displaySortController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '999',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((p) {
                              final isSelected = displaySortController.text == p.toString();
                              return InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    displaySortController.text = p.toString();
                                  });
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.blue : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$p',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isSelected ? Colors.white : Colors.black87,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),

                    // 2. 后厨打印优先级设置
                    Row(
                      children: [
                        const Icon(Icons.print, size: 18, color: Colors.teal),
                        const SizedBox(width: 6),
                        Text(
                          'kitchen_print_priority'.tr,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'kitchen_print_priority_hint'.tr,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: printPriorityController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '999',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((p) {
                              final isSelected = printPriorityController.text == p.toString();
                              return InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    printPriorityController.text = p.toString();
                                  });
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.teal : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$p',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isSelected ? Colors.white : Colors.black87,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),

                    // 3. 分类颜色设置
                    Text(
                      'select_category_color'.tr,
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: CategoryColorMapper.selectableColors.map((color) {
                        final bool isSelected = (color.value == selectedColor.value);
                        return InkWell(
                          onTap: () {
                            setDialogState(() {
                              selectedColor = color;
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 3,
                                  offset: Offset(0, 1),
                                ),
                              ],
                              border: Border.all(
                                color: isSelected ? Colors.black87 : Colors.white,
                                width: isSelected ? 2.5 : 1.5,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, color: Colors.white, size: 22)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                if (isCustomColor || isCustomDisplaySort || isCustomPrintPriority)
                  TextButton.icon(
                    onPressed: () async {
                      await CategoryColorMapper.setCategoryColor(category.id, null);
                      await CategoryDisplaySortMapper.setCategoryDisplaySort(category.id, null);
                      await CategoryPriorityMapper.setCategoryPriority(category.id, null);
                      if (mounted) {
                        setState(() {});
                      }
                      widget.onCategoryColorChanged?.call();
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                    icon: const Icon(Icons.restore, size: 16),
                    label: Text('reset_default_color'.tr),
                    style: TextButton.styleFrom(foregroundColor: Colors.orange[800]),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('cancel'.tr),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[600],
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    await CategoryColorMapper.setCategoryColor(category.id, selectedColor);
                    final sVal = int.tryParse(displaySortController.text.trim());
                    await CategoryDisplaySortMapper.setCategoryDisplaySort(category.id, sVal);
                    final pVal = int.tryParse(printPriorityController.text.trim());
                    await CategoryPriorityMapper.setCategoryPriority(category.id, pVal);

                    if (mounted) {
                      setState(() {});
                    }
                    widget.onCategoryColorChanged?.call();
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: Text('save'.tr),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<Category> _buildHierarchicalCategories(List<Category> categories) {
    if (categories.isEmpty) return [];

    final categoryMap = {for (var c in categories) c.id: c};
    final childrenMap = <int, List<Category>>{};
    final topLevel = <Category>[];

    for (var cat in categories) {
      if (cat.parentId == null || cat.parentId == 0 || !categoryMap.containsKey(cat.parentId)) {
        topLevel.add(cat);
      } else {
        childrenMap.putIfAbsent(cat.parentId!, () => []).add(cat);
      }
    }

    int getDisplaySort(Category c) => CategoryDisplaySortMapper.getDisplaySortForCategoryId(c.id);

    topLevel.sort((a, b) {
      final sA = getDisplaySort(a);
      final sB = getDisplaySort(b);
      if (sA != sB) return sA.compareTo(sB);
      return a.id.compareTo(b.id);
    });

    childrenMap.forEach((parentId, children) {
      children.sort((a, b) {
        final sA = getDisplaySort(a);
        final sB = getDisplaySort(b);
        if (sA != sB) return sA.compareTo(sB);
        return a.id.compareTo(b.id);
      });
    });

    final result = <Category>[];

    void addCategoryAndChildren(Category parent) {
      result.add(parent);
      final children = childrenMap[parent.id];
      if (children != null && children.isNotEmpty) {
        for (var child in children) {
          addCategoryAndChildren(child);
        }
      }
    }

    for (var top in topLevel) {
      addCategoryAndChildren(top);
    }

    for (var cat in categories) {
      if (!result.contains(cat)) {
        result.add(cat);
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final displayCategories = _buildHierarchicalCategories(widget.categories);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.grey[100]!, Colors.grey[200]!],
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 2,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 45,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue[300]!, Colors.blue[400]!],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 2,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: Text(
                      'category_title'.tr,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (widget.isAdminMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ElevatedButton.icon(
                      onPressed: widget.onManageKitchenSplit,
                      icon: const Icon(Icons.print, size: 12),
                      label: Text('kitchen_split'.tr, style: const TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 顶部“全部”按钮
          Material(
            color: Colors.white,
            child: InkWell(
              onTap: () => widget.onCategoryTap?.call(null),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.apps, size: 16, color: Colors.blue[600]),
                    const SizedBox(width: 6),
                    Text(
                      'all_categories'.tr.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(2),
              child: ListView.builder(
                itemCount: displayCategories.length,
                itemBuilder: (context, index) {
                  final category = displayCategories[index];
                  final isParent = category.parentId == null ||
                      category.parentId == 0 ||
                      !widget.categories.any((c) => c.id == category.parentId);
                  final categoryColor = CategoryColorMapper.getColorForCategory(
                    category,
                    allCategories: widget.categories,
                  );
                  final hasCustomDisplaySort = CategoryDisplaySortMapper.hasCustomDisplaySort(category.id);
                  final displaySort = CategoryDisplaySortMapper.getDisplaySortForCategoryId(category.id);
                  final hasCustomPrintPriority = CategoryPriorityMapper.hasCustomPriority(category.id);
                  final printPriority = CategoryPriorityMapper.getPriorityForCategoryId(category.id);

                  return Material(
                    color: isParent ? Colors.white : Colors.grey[50],
                    child: InkWell(
                      onTap: () {
                        widget.onCategoryTap?.call(category);
                        if (widget.isAdminMode) {
                          _showCategorySettingsDialog(category);
                        }
                      },
                      child: Container(
                        height: isParent ? 38 : 34,
                        padding: EdgeInsets.only(
                          left: isParent ? 8 : 24,
                          right: 4,
                        ),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Icon(
                              isParent
                                  ? Icons.apps
                                  : Icons.subdirectory_arrow_right,
                              size: isParent ? 16 : 14,
                              color: categoryColor,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                category.title,
                                style: TextStyle(
                                  fontSize: isParent ? 15 : 13,
                                  fontWeight:
                                      isParent
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                  color:
                                      isParent
                                          ? Colors.blueGrey[800]
                                          : Colors.grey[800],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.isAdminMode && hasCustomDisplaySort) ...[
                              const SizedBox(width: 3),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.blue[300]!, width: 0.5),
                                ),
                                child: Text(
                                  'S$displaySort',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[800],
                                  ),
                                ),
                              ),
                            ],
                            if (widget.isAdminMode && hasCustomPrintPriority) ...[
                              const SizedBox(width: 3),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.teal[50],
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.teal[300]!, width: 0.5),
                                ),
                                child: Text(
                                  'P$printPriority',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal[800],
                                  ),
                                ),
                              ),
                            ],
                            if (widget.isAdminMode) ...[
                              const SizedBox(width: 2),
                              InkWell(
                                onTap: () => _moveCategoryOrder(category, true),
                                child: Padding(
                                  padding: const EdgeInsets.all(2.0),
                                  child: Icon(
                                    Icons.arrow_drop_up,
                                    size: 20,
                                    color: Colors.blueGrey[700],
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => _moveCategoryOrder(category, false),
                                child: Padding(
                                  padding: const EdgeInsets.all(2.0),
                                  child: Icon(
                                    Icons.arrow_drop_down,
                                    size: 20,
                                    color: Colors.blueGrey[700],
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => _showCategorySettingsDialog(category),
                                child: Padding(
                                  padding: const EdgeInsets.all(2.0),
                                  child: Icon(
                                    Icons.tune,
                                    size: 16,
                                    color: Colors.teal[700],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
