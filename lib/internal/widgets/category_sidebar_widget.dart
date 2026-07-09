import 'package:flutter/material.dart';
import '../../common/models/category.dart';

class CategorySidebarWidget extends StatelessWidget {
  final List<Category> categories;
  final void Function(Category? category)? onCategoryTap;

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
          // 顶部“全部”按钮
          Material(
            color: Colors.white,
            child: InkWell(
              onTap: () => onCategoryTap?.call(null),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.apps, size: 16, color: Colors.blue[600]),
                    SizedBox(width: 6),
                    Text(
                      'ALL',
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
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final isParent = category.parentId == null;
                  return Material(
                    color: isParent ? Colors.white : Colors.grey[100],
                    child: InkWell(
                      onTap: () => onCategoryTap?.call(category),
                      child: Container(
                        height: isParent ? 38 : 35,
                        padding: EdgeInsets.symmetric(
                          horizontal: isParent ? 8 : 20,
                        ),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Icon(
                              isParent
                                  ? Icons.apps
                                  : Icons.restaurant_menu,
                              size: 15,
                              color:
                                  isParent
                                      ? Colors.blueGrey[700]
                                      : Colors.grey[600],
                            ),
                            SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                category.title,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight:
                                      isParent
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                  color:
                                      isParent
                                          ? Colors.blueGrey[800]
                                          : Colors.grey[700],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
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
