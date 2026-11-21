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

  /// 预设默认背景调色板 (Material 100 鲜明高识别度调色，比 50 色阶稍微加深)
  static const List<Color> defaultBackgroundPalette = [
    Color(0xFFBBDEFB), // 清澈天蓝 100
    Color(0xFFFFE0B2), // 暖亮黄橙 100
    Color(0xFFB2DFDB), // 鲜亮青绿 100
    Color(0xFFE1BEE7), // 柔紫 100
    Color(0xFFFFECB3), // 明黄 100
    Color(0xFFF8BBD0), // 浅粉 100
    Color(0xFFC5CAE9), // 靛蓝 100
    Color(0xFFB2EBF2), // 青蓝 100
    Color(0xFFFFCCBC), // 橘红 100
    Color(0xFFF0F4C3), // 嫩绿 100
    Color(0xFFC8E6C9), // 鲜绿 100
    Color(0xFFE2E8F0), // 干净浅灰
  ];

  /// 预设默认边框调色板 (Material 300 纯正线条，配合 100 背景更清晰)
  static const List<Color> defaultBorderPalette = [
    Color(0xFF64B5F6), // 蓝边框
    Color(0xFFFFB74D), // 橙边框
    Color(0xFF4DB6AC), // 青边框
    Color(0xFFBA68C8), // 紫边框
    Color(0xFFFFD54F), // 黄边框
    Color(0xFFF06292), // 粉边框
    Color(0xFF7986CB), // 靛蓝边框
    Color(0xFF4DD0E1), // 青蓝边框
    Color(0xFFFF8A65), // 橘红边框
    Color(0xFFDCE775), // 嫩绿边框
    Color(0xFF81C784), // 鲜绿边框
    Color(0xFF94A3B8), // 浅灰边框
  ];

  /// 将自定义基础颜色转换为高纯度背景色（适度加深亮度与对比度）
  static Color _toPureCrispColor(Color baseColor) {
    if (baseColor == Colors.white) {
      return const Color(0xFFE2E8F0);
    }
    final hsl = HSLColor.fromColor(baseColor);
    final newSat = (hsl.saturation).clamp(0.65, 1.0);
    const newLight = 0.82;
    return hsl.withSaturation(newSat).withLightness(newLight).toColor();
  }

  /// 获取分类背景纯色
  static Color getCategoryBackgroundColor(List<int> categoryIds, List<Category> allCategories) {
    if (categoryIds.isEmpty) {
      return const Color(0xFFE2E8F0);
    }

    for (int categoryId in categoryIds) {
      final category = allCategories.firstWhere(
        (cat) => cat.id == categoryId,
        orElse: () => Category(id: -1, title: ''),
      );

      if (category.id != -1) {
        if (hasCustomColor(category.id)) {
          final customColor = getColorForCategoryId(category.id, allCategories: allCategories);
          return _toPureCrispColor(customColor);
        }
        final index = category.id.abs() % defaultBackgroundPalette.length;
        return defaultBackgroundPalette[index];
      }
    }

    return const Color(0xFFE2E8F0);
  }

  /// 获取干净清爽的边框颜色
  static Color getCategoryBorderColor(List<int> categoryIds, List<Category> allCategories) {
    if (categoryIds.isEmpty) {
      return const Color(0xFFCBD5E1);
    }

    for (int categoryId in categoryIds) {
      final category = allCategories.firstWhere(
        (cat) => cat.id == categoryId,
        orElse: () => Category(id: -1, title: ''),
      );

      if (category.id != -1) {
        if (hasCustomColor(category.id)) {
          final customColor = getColorForCategoryId(category.id, allCategories: allCategories);
          final hsl = HSLColor.fromColor(customColor);
          return hsl.withSaturation(hsl.saturation.clamp(0.60, 1.0)).withLightness(0.68).toColor();
        }
        final index = category.id.abs() % defaultBorderPalette.length;
        return defaultBorderPalette[index];
      }
    }

    return const Color(0xFFCBD5E1);
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
