import 'package:flutter/material.dart';
import '../../common/models/category.dart';

class CategorySidebarWidget extends StatelessWidget {
  final List<Category> categories;
  final void Function(Category parent, [Category? child])? onCategoryTap;

  const CategorySidebarWidget({
    Key? key,
    required this.categories,
    this.onCategoryTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
          Expanded(
            child: Container(
              margin: EdgeInsets.all(2),
              child: ListView.builder(
                itemCount: categories.where((c) => c.parentId == null).length,
                itemBuilder: (context, index) {
                  final parent = categories.where((c) => c.parentId == null).toList()[index];
                  final children = categories.where((c) => c.parentId == parent.id).toList();
                  if (children.isEmpty) {
                    return Container(
                      margin: EdgeInsets.only(bottom: 1),
                      child: Material(
                        color: Colors.grey[50],
                        child: InkWell(
                          onTap: () => onCategoryTap?.call(parent),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            child: Text(
                              parent.title,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  return Container(
                    margin: EdgeInsets.only(bottom: 1),
                    child: ExpansionTile(
                      title: Text(
                        parent.title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      backgroundColor: Colors.white,
                      collapsedBackgroundColor: Colors.grey[50],
                      iconColor: Colors.blue[600],
                      collapsedIconColor: Colors.grey[600],
                      tilePadding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      childrenPadding: EdgeInsets.zero,
                      children: children.map((child) =>
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => onCategoryTap?.call(parent, child),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              child: Row(
                                children: [
                                  Icon(Icons.arrow_right, size: 12, color: Colors.grey[600]),
                                  SizedBox(width: 4),
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
                        ),
                      ).toList(),
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

