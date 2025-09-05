import 'package:flutter/material.dart';
import '../../common/models/category.dart';

class CategorySidebarWidget extends StatefulWidget {
  final List<Category> categories;
  final void Function(Category? parent, [Category? child])? onCategoryTap;

  const CategorySidebarWidget({
    Key? key,
    required this.categories,
    this.onCategoryTap,
  }) : super(key: key);

  @override
  State<CategorySidebarWidget> createState() => _CategorySidebarWidgetState();
}

class _CategorySidebarWidgetState extends State<CategorySidebarWidget> {
  Set<int> expandedIds = {};

  @override
  Widget build(BuildContext context) {
    final parents = widget.categories.where((c) => c.parentId == null).toList();
    final childrenMap = <int, List<Category>>{};
    for (var parent in parents) {
      childrenMap[parent.id] = widget.categories.where((c) => c.parentId == parent.id).toList();
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.grey[100]!, Colors.grey[200]!],
        ),
        boxShadow: [
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
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 2,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              'Categories',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
          // 顶部“全部”按钮
          Material(
            color: Colors.white,
            child: InkWell(
              onTap: () => widget.onCategoryTap?.call(null),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.apps, size: 16, color: Colors.blue[600]),
                    SizedBox(width: 6),
                    Text(
                      '全部',
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
              margin: EdgeInsets.all(2),
              child: ListView.builder(
                itemCount: parents.length,
                itemBuilder: (context, index) {
                  final parent = parents[index];
                  final children = childrenMap[parent.id]!;
                  final isExpanded = expandedIds.contains(parent.id);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Material(
                        color: Colors.grey[50],
                        child: InkWell(
                          onTap: () {
                            if (children.isEmpty) {
                              widget.onCategoryTap?.call(parent);
                            } else {
                              setState(() {
                                if (isExpanded) {
                                  expandedIds.remove(parent.id);
                                } else {
                                  expandedIds.add(parent.id);
                                }
                              });
                            }
                          },
                          child: Container(
                            height: 20,
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    parent.title,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                                if (children.isNotEmpty)
                                  Icon(
                                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                                    size: 16,
                                    color: Colors.grey[600],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (isExpanded && children.isNotEmpty)
                        ...children.map((child) => Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => widget.onCategoryTap?.call(parent, child),
                            child: Container(
                              height: 20,
                              padding: EdgeInsets.symmetric(horizontal: 20),
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  Icon(Icons.arrow_right, size: 12, color: Colors.grey[600]),
                                  SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      child.title,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[700],
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )),
                    ],
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
