import 'package:flutter/material.dart';
import '../../common/models/category.dart';

class CategoryColorMapper {
  // 分类背景色映射表
  static final Map<String, Color> _categoryColors = {
    'Noodle': Colors.grey,
    'Fry Rice': Colors.orange,
    'Soup': Colors.blue,
    'Snack': Colors.red,
    'Drink': Colors.amber, // gold色用amber表示
  };

  // 获取分类的背景色
  static Color getCategoryColor(List<int> categoryIds, List<Category> allCategories) {
    if (categoryIds.isEmpty) {
      return Colors.white; // 默认白色
    }

    // 优先查找直接匹配的分类
    for (int categoryId in categoryIds) {
      final category = allCategories.firstWhere(
        (cat) => cat.id == categoryId,
        orElse: () => Category(id: -1, title: ''),
      );

      if (category.id != -1) {
        final color = _categoryColors[category.title];
        if (color != null) {
          return color;
        }

        // 如果当前分类没有颜色，查找父分类
        if (category.parentId != null) {
          final parentCategory = allCategories.firstWhere(
            (cat) => cat.id == category.parentId,
            orElse: () => Category(id: -1, title: ''),
          );

          if (parentCategory.id != -1) {
            final parentColor = _categoryColors[parentCategory.title];
            if (parentColor != null) {
              return parentColor;
            }
          }
        }
      }
    }

    return Colors.white; // 默认白色
  }

  // 获取浅色版本（用于背景）
  static Color getCategoryBackgroundColor(List<int> categoryIds, List<Category> allCategories) {
    final baseColor = getCategoryColor(categoryIds, allCategories);
    if (baseColor == Colors.white) {
      return Colors.grey[50]!; // 使用浅灰色背景
    }
    return baseColor.withOpacity(0.1); // 浅色背景
  }

  // 获取深色版本（用于边框）
  static Color getCategoryBorderColor(List<int> categoryIds, List<Category> allCategories) {
    final baseColor = getCategoryColor(categoryIds, allCategories);
    if (baseColor == Colors.white) {
      return Colors.grey[200]!;
    }
    return baseColor.withOpacity(0.3); // 浅色边框
  }

  // 获取所有可用的分类颜色
  static Map<String, Color> getAllCategoryColors() {
    return Map.from(_categoryColors);
  }

  // 添加或更新分类颜色
  static void setCategoryColor(String categoryTitle, Color color) {
    _categoryColors[categoryTitle] = color;
  }
}
