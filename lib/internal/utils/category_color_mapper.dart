import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../../common/models/category.dart';
import '../../common/services/database_service.dart';

class CategoryColorMapper {
  static final Logger _logger = Logger();
  static const String _settingKey = 'category_custom_colors';

  // 默认调色板：循环映射给没有自定义颜色的分类（12种清晰区分的调色）
  static const List<Color> defaultPalette = [
    Colors.blue,
    Colors.orange,
    Colors.teal,
    Colors.purple,
    Colors.amber,
    Colors.pink,
    Colors.indigo,
    Colors.cyan,
    Colors.deepOrange,
    Colors.lime,
    Colors.green,
    Colors.blueGrey,
  ];

  // 用户自定义分类颜色表 <categoryId, Color>
  static final Map<int, Color> _customCategoryColors = {};
  static bool _isLoaded = false;

  /// 加载自定义分类颜色
  static Future<void> loadCustomColors() async {
    if (_isLoaded) return;
    try {
      final jsonStr = await DatabaseService().getSetting(_settingKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        _customCategoryColors.clear();
        decoded.forEach((key, value) {
          final id = int.tryParse(key);
          if (id != null && value is int) {
            _customCategoryColors[id] = Color(value);
          }
        });
      }
    } catch (e) {
      _logger.e('加载分类颜色配置异常: $e');
    } finally {
      _isLoaded = true;
    }
  }

  /// 保存分类颜色配置到数据库
  static Future<void> _saveCustomColors() async {
    try {
      final mapToSave = _customCategoryColors.map((id, color) => MapEntry(id.toString(), color.value));
      final jsonStr = jsonEncode(mapToSave);
      await DatabaseService().saveSetting(_settingKey, jsonStr);
    } catch (e) {
      _logger.e('保存分类颜色配置异常: $e');
    }
  }

  /// 获取指定 categoryId 的基础颜色
  static Color getColorForCategoryId(
    int categoryId, {
    List<Category>? allCategories,
    Set<int>? visited,
  }) {
    // 1. 优先查找直接设置的自定义颜色
    if (_customCategoryColors.containsKey(categoryId)) {
      return _customCategoryColors[categoryId]!;
    }

    // 2. 如果当前分类没有自定义颜色，且属于子分类，默认继承父分类的颜色
    if (allCategories != null && allCategories.isNotEmpty) {
      final category = allCategories.firstWhere(
        (cat) => cat.id == categoryId,
        orElse: () => Category(id: -1, title: ''),
      );
      if (category.id != -1 && category.parentId != null) {
        final currentVisited = visited ?? <int>{};
        currentVisited.add(categoryId);
        if (!currentVisited.contains(category.parentId)) {
          return getColorForCategoryId(
            category.parentId!,
            allCategories: allCategories,
            visited: currentVisited,
          );
        }
      }
    }

    // 3. 顶层分类（或找不到父分类时）默认按 categoryId 循环映射调色板
    final index = categoryId.abs() % defaultPalette.length;
    return defaultPalette[index];
  }

  /// 获取指定分类对象的颜色
  static Color getColorForCategory(Category category, {List<Category>? allCategories}) {
    return getColorForCategoryId(category.id, allCategories: allCategories);
  }

  /// 获取分类列表（菜品的 categoryIds）对应的基础颜色
  static Color getCategoryColor(List<int> categoryIds, List<Category> allCategories) {
    if (categoryIds.isEmpty) {
      return Colors.white; // 默认白色
    }

    for (int categoryId in categoryIds) {
      final category = allCategories.firstWhere(
        (cat) => cat.id == categoryId,
        orElse: () => Category(id: -1, title: ''),
      );

      if (category.id != -1) {
        return getColorForCategoryId(category.id, allCategories: allCategories);
      }
    }

    return Colors.white;
  }

  /// 获取浅色版本（用于背景）
  static Color getCategoryBackgroundColor(List<int> categoryIds, List<Category> allCategories) {
    final baseColor = getCategoryColor(categoryIds, allCategories);
    if (baseColor == Colors.white) {
      return Colors.grey[50]!;
    }
    return baseColor.withOpacity(0.12);
  }

  /// 获取深色版本（用于边框）
  static Color getCategoryBorderColor(List<int> categoryIds, List<Category> allCategories) {
    final baseColor = getCategoryColor(categoryIds, allCategories);
    if (baseColor == Colors.white) {
      return Colors.grey[200]!;
    }
    return baseColor.withOpacity(0.35);
  }

  /// 设置分类自定义颜色（传入 null 则恢复默认）
  static Future<void> setCategoryColor(int categoryId, Color? color) async {
    if (color == null) {
      _customCategoryColors.remove(categoryId);
    } else {
      _customCategoryColors[categoryId] = color;
    }
    await _saveCustomColors();
  }

  /// 判断指定分类是否有自定义颜色
  static bool hasCustomColor(int categoryId) {
    return _customCategoryColors.containsKey(categoryId);
  }

  /// 可供选择的预设调色板
  static List<Color> get selectableColors => defaultPalette;
}
