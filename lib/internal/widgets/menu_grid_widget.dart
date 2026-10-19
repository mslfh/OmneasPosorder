import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../common/models/menu_item.dart';
import '../../common/models/category.dart';
import '../../common/models/menu_item_layout_config.dart';
import '../services/menu_layout_service.dart';
import '../utils/category_color_mapper.dart';

/// 内部已放置到网格的菜品项数据结构
class PlacedGridItem {
  final MenuItem item;
  final int col;
  final int row;
  final int spanX;
  final int spanY;
  final bool isCustomPlaced;

  PlacedGridItem({
    required this.item,
    required this.col,
    required this.row,
    required this.spanX,
    required this.spanY,
    this.isCustomPlaced = false,
  });
}

class MenuGridWidget extends StatefulWidget {
  final List<MenuItem?> products;
  final List<Category> categories;
  final bool isLoading;
  final String? error;
  final void Function(MenuItem) onTap;
  final double Function(String, double) calculateTitleFontSize;
  final bool isCardPressed;
  final int? pressedCardIndex;
  final bool isAdminMode;
  final void Function(MenuItem)? onLongPress;
  final void Function(MenuItem, int)? onReorderStart;

  const MenuGridWidget({
    super.key,
    required this.products,
    required this.categories,
    required this.isLoading,
    required this.error,
    required this.onTap,
    required this.calculateTitleFontSize,
    required this.isCardPressed,
    required this.pressedCardIndex,
    this.isAdminMode = false,
    this.onLongPress,
    this.onReorderStart,
  });

  @override
  State<MenuGridWidget> createState() => _MenuGridWidgetState();
}

class _MenuGridWidgetState extends State<MenuGridWidget> {
  // 12 列单元格标准网格
  static const int _crossAxisCount = 12;

  // 网格容器 Key，用于获取全局像素坐标
  final GlobalKey _gridKey = GlobalKey();

  // 网格编辑模式状态
  bool _isEditMode = false;

  // 当前在编辑模式下选中的菜品 ID
  int? _selectedEditingItemId;

  // 最近拖拽/调整尺寸的菜品 ID (赋予最高排版优先级)
  int? _lastMovedItemId;

  // 本地缓存的自定义网格配置 (menuItemId -> MenuItemLayoutConfig)
  Map<int, MenuItemLayoutConfig> _layoutConfigs = {};
  bool _isConfigsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadLayoutConfigs();
  }

  Future<void> _loadLayoutConfigs() async {
    final configs = await MenuLayoutService.loadLayoutConfigs();
    if (mounted) {
      setState(() {
        _layoutConfigs = configs;
        _isConfigsLoaded = true;
      });
    }
  }

  /// 依据拖拽释放时的全局屏幕坐标，精准计算目标的单元格 (col, row)
  void _handleDragEnd(MenuItem item, Offset globalOffset, int spanX, int spanY) {
    final RenderBox? renderBox =
        _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localOffset = renderBox.globalToLocal(globalOffset);
    final cellWidth = renderBox.size.width / _crossAxisCount;
    final cellHeight = cellWidth * 0.85;

    // 四舍五入计算最靠近的目标行列，并防止越界
    int targetCol =
        (localOffset.dx / cellWidth).round().clamp(0, _crossAxisCount - spanX);
    int targetRow = (localOffset.dy / cellHeight).round().clamp(0, 200);

    _updateItemConfig(item.id, col: targetCol, row: targetRow);
  }

  /// 布局计算引擎：后续菜品按序顺序填补空位，消除中间脱节与空洞，保持前期菜品相对位置稳定
  List<PlacedGridItem> _calculatePlacedItems(List<MenuItem> validProducts) {
    final Map<String, bool> occupied = {};
    final List<PlacedGridItem> result = [];

    bool isOccupied(int r, int c, int sx, int sy) {
      if (c + sx > _crossAxisCount) return true;
      for (int row = r; row < r + sy; row++) {
        for (int col = c; col < c + sx; col++) {
          if (occupied['$row,$col'] == true) return true;
        }
      }
      return false;
    }

    void markOccupied(int r, int c, int sx, int sy) {
      for (int row = r; row < r + sy; row++) {
        for (int col = c; col < c + sx; col++) {
          occupied['$row,$col'] = true;
        }
      }
    }

    // 寻找从 (startRow, startCol) 顺延开始的首个空闲位置
    math.Point<int> findNextFreeSlot(int startRow, int startCol, int sx, int sy) {
      int r = startRow < 0 ? 0 : startRow;
      int c = startCol < 0 ? 0 : startCol;
      while (true) {
        if (c + sx > _crossAxisCount) {
          c = 0;
          r++;
        }
        if (!isOccupied(r, c, sx, sy)) {
          return math.Point<int>(c, r);
        }
        c++;
      }
    }

    MenuItem? activeEditingItem;
    if (_lastMovedItemId != null) {
      for (final p in validProducts) {
        if (p.id == _lastMovedItemId) {
          activeEditingItem = p;
          break;
        }
      }
    }

    // 1. 优先放置当前正在主动移动/放置的菜品
    if (activeEditingItem != null && _layoutConfigs.containsKey(activeEditingItem.id)) {
      final config = _layoutConfigs[activeEditingItem.id]!;
      int spanX = config.spanX.clamp(2, _crossAxisCount);
      int spanY = config.spanY.clamp(2, 20);
      if (spanX * spanY < 4) {
        spanX = 2;
        spanY = 2;
      }
      int col = config.col.clamp(0, _crossAxisCount - spanX);
      int row = config.row < 0 ? 0 : config.row;

      if (isOccupied(row, col, spanX, spanY)) {
        final free = findNextFreeSlot(row, col, spanX, spanY);
        col = free.x;
        row = free.y;
      }

      markOccupied(row, col, spanX, spanY);
      result.add(PlacedGridItem(
        item: activeEditingItem,
        col: col,
        row: row,
        spanX: spanX,
        spanY: spanY,
        isCustomPlaced: true,
      ));
    }

    // 2. 将所有其他菜品按照其原有的相对顺序排序 (已有布局配置的按行、列，没有的按 categoryId)
    final List<MenuItem> remainingProducts = validProducts
        .where((item) => item.id != activeEditingItem?.id)
        .toList();

    remainingProducts.sort((a, b) {
      final hasConfigA = _layoutConfigs.containsKey(a.id);
      final hasConfigB = _layoutConfigs.containsKey(b.id);

      if (hasConfigA && hasConfigB) {
        final configA = _layoutConfigs[a.id]!;
        final configB = _layoutConfigs[b.id]!;
        final cmpRow = configA.row.compareTo(configB.row);
        if (cmpRow != 0) return cmpRow;
        return configA.col.compareTo(configB.col);
      } else if (hasConfigA) {
        return -1;
      } else if (hasConfigB) {
        return 1;
      } else {
        final catA = a.categoryIds.isNotEmpty ? a.categoryIds.first : 999999;
        final catB = b.categoryIds.isNotEmpty ? b.categoryIds.first : 999999;
        final cmpCat = catA.compareTo(catB);
        if (cmpCat != 0) return cmpCat;

        final cmpSort = a.sort.compareTo(b.sort);
        if (cmpSort != 0) return cmpSort;

        return a.code.compareTo(b.code);
      }
    });

    // 3. 按序依次安排其余菜品：前面未受影响的保持原位，后续菜品若遇到空洞则自动向前补位
    int scanRow = 0;
    int scanCol = 0;

    for (final item in remainingProducts) {
      final config = _layoutConfigs[item.id];
      int spanX = (config?.spanX ?? 3).clamp(2, _crossAxisCount);
      int spanY = (config?.spanY ?? 2).clamp(2, 20);
      if (spanX * spanY < 4) {
        spanX = 2;
        spanY = 2;
      }

      int targetCol;
      int targetRow;

      if (config != null) {
        int reqCol = config.col.clamp(0, _crossAxisCount - spanX);
        int reqRow = config.row < 0 ? 0 : config.row;

        // 如果原有位置没有被占用，并且在此之前的网格没有出现断层空洞，则保持原位
        if (!isOccupied(reqRow, reqCol, spanX, spanY) &&
            (reqRow < scanRow || (reqRow == scanRow && reqCol <= scanCol))) {
          targetCol = reqCol;
          targetRow = reqRow;
        } else {
          // 否则，从当前顺序推进点 (scanRow, scanCol) 自动顺延补位
          final free = findNextFreeSlot(scanRow, scanCol, spanX, spanY);
          targetCol = free.x;
          targetRow = free.y;
        }
      } else {
        // 未单独配置的菜品，自动顺序补位
        final free = findNextFreeSlot(scanRow, scanCol, spanX, spanY);
        targetCol = free.x;
        targetRow = free.y;
      }

      markOccupied(targetRow, targetCol, spanX, spanY);
      result.add(PlacedGridItem(
        item: item,
        col: targetCol,
        row: targetRow,
        spanX: spanX,
        spanY: spanY,
        isCustomPlaced: config != null,
      ));

      // 更新顺序扫描指针为当前放置位置之后
      scanCol = targetCol + spanX;
      scanRow = targetRow;
      if (scanCol >= _crossAxisCount) {
        scanCol = 0;
        scanRow++;
      }
    }

    return result;
  }

  /// 保存并更新菜品的网格位置与尺寸（自动持久化并同步补位后的位置）
  Future<void> _updateItemConfig(int itemId,
      {int? col, int? row, int? spanX, int? spanY}) async {
    final current = _layoutConfigs[itemId];
    final defaultSpanX = current?.spanX ?? 3;
    final defaultSpanY = current?.spanY ?? 2;
    final defaultCol = current?.col ?? 0;
    final defaultRow = current?.row ?? 0;

    int newSpanX = spanX ?? defaultSpanX;
    int newSpanY = spanY ?? defaultSpanY;

    // 确保最低 4 个单元格
    if (newSpanX * newSpanY < 4) {
      if (newSpanX < 2) newSpanX = 2;
      if (newSpanY < 2) newSpanY = 2;
    }

    final newConfig = MenuItemLayoutConfig(
      menuItemId: itemId,
      col: (col ?? defaultCol).clamp(0, _crossAxisCount - newSpanX),
      row: (row ?? defaultRow) < 0 ? 0 : (row ?? defaultRow),
      spanX: newSpanX,
      spanY: newSpanY,
    );

    _lastMovedItemId = itemId;
    _layoutConfigs[itemId] = newConfig;

    // 计算放置后更新所有变动菜品的配置，确保补位重排后的位置同步持久化
    final validProducts = widget.products.whereType<MenuItem>().toList();
    final placed = _calculatePlacedItems(validProducts);

    for (final p in placed) {
      _layoutConfigs[p.item.id] = MenuItemLayoutConfig(
        menuItemId: p.item.id,
        col: p.col,
        row: p.row,
        spanX: p.spanX,
        spanY: p.spanY,
      );
    }

    setState(() {});
    await MenuLayoutService.saveLayoutConfigs(_layoutConfigs);
  }

  /// 重置为默认网格排列
  Future<void> _resetLayout() async {
    setState(() {
      _layoutConfigs.clear();
      _selectedEditingItemId = null;
      _lastMovedItemId = null;
    });
    await MenuLayoutService.clearLayoutConfigs();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading || !_isConfigsLoaded) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.blue[400]),
            const SizedBox(height: 16),
            Text('Loading menu grid...', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }
    if (widget.error != null) {
      final errText = widget.error!;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text('Error: $errText', style: TextStyle(color: Colors.red[600])),
          ],
        ),
      );
    }

    final validProducts = widget.products.whereType<MenuItem>().toList();

    if (validProducts.isEmpty) {
      return Center(
        child: Text('No products available',
            style: TextStyle(color: Colors.grey[500], fontSize: 16)),
      );
    }

    final placedItems = _calculatePlacedItems(validProducts);

    // 计算网格总行数
    int maxRows = 6;
    for (final p in placedItems) {
      if (p.row + p.spanY > maxRows) {
        maxRows = p.row + p.spanY;
      }
    }
    maxRows += 4;

    return Column(
      children: [
        // 编辑模式顶部提示与控制条
        if (_isEditMode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.amber[100],
            child: Row(
              children: [
                const Icon(Icons.edit_road, size: 20, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '编辑模式：拖拽菜品调整位置(后续菜品自动无缝补位)，点击调节占用大小',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown[800],
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _resetLayout,
                  icon: const Icon(Icons.restore, size: 16, color: Colors.brown),
                  label: const Text('重置布局',
                      style: TextStyle(fontSize: 12, color: Colors.brown)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isEditMode = false;
                      _selectedEditingItemId = null;
                    });
                  },
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('完成', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    elevation: 1,
                  ),
                ),
              ],
            ),
          ),

        // 主网格绘制区域
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final containerWidth = constraints.maxWidth;
              final cellWidth = containerWidth / _crossAxisCount;
              final cellHeight = cellWidth * 0.85;
              final totalGridHeight = maxRows * cellHeight;

              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  key: _gridKey,
                  width: containerWidth,
                  height: totalGridHeight,
                  child: Stack(
                    children: [
                      // 1. 编辑模式下显示区域单元格线框
                      if (_isEditMode)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: GridUnitsPainter(
                              crossAxisCount: _crossAxisCount,
                              rows: maxRows,
                              cellWidth: cellWidth,
                              cellHeight: cellHeight,
                            ),
                          ),
                        ),

                      // 2. 菜品方块卡片绘制
                      ...placedItems.map((placed) {
                        final item = placed.item;
                        final left = placed.col * cellWidth;
                        final top = placed.row * cellHeight;
                        final width = placed.spanX * cellWidth;
                        final height = placed.spanY * cellHeight;

                        final isSelectedInEdit =
                            _isEditMode && _selectedEditingItemId == item.id;

                        Widget baseCardWidget = _buildItemCard(
                          context: context,
                          item: item,
                          width: width,
                          height: height,
                          spanX: placed.spanX,
                          spanY: placed.spanY,
                          isSelectedInEdit: isSelectedInEdit,
                        );

                        Widget finalCardWidget;

                        // 编辑模式下使用 LongPressDraggable 精确捕获拖拽手平移像素
                        if (_isEditMode) {
                          finalCardWidget = LongPressDraggable<MenuItem>(
                            data: item,
                            onDragEnd: (details) {
                              _handleDragEnd(
                                  item, details.offset, placed.spanX, placed.spanY);
                            },
                            feedback: Material(
                              color: Colors.transparent,
                              child: Opacity(
                                opacity: 0.85,
                                child: SizedBox(
                                  width: width,
                                  height: height,
                                  child: _buildItemCard(
                                    context: context,
                                    item: item,
                                    width: width,
                                    height: height,
                                    spanX: placed.spanX,
                                    spanY: placed.spanY,
                                    isSelectedInEdit: isSelectedInEdit,
                                    isFeedback: true,
                                  ),
                                ),
                              ),
                            ),
                            childWhenDragging: IgnorePointer(
                              child: Opacity(
                                opacity: 0.25,
                                child: baseCardWidget,
                              ),
                            ),
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedEditingItemId = item.id;
                                });
                              },
                              onLongPress: () {
                                if (widget.onLongPress != null) {
                                  widget.onLongPress!(item);
                                }
                              },
                              child: baseCardWidget,
                            ),
                          );
                        } else {
                          // 常规模式长按：进入网格编辑模式
                          finalCardWidget = GestureDetector(
                            onTap: () => widget.onTap(item),
                            onLongPress: () {
                              setState(() {
                                _isEditMode = true;
                                _selectedEditingItemId = item.id;
                              });
                            },
                            child: baseCardWidget,
                          );
                        }

                        return Positioned(
                          left: left,
                          top: top,
                          width: width,
                          height: height,
                          child: Padding(
                            padding: const EdgeInsets.all(1.5),
                            child: Stack(
                              children: [
                                Positioned.fill(child: finalCardWidget),

                                // 在编辑模式下选中时，显示调整大小控制面板
                                if (isSelectedInEdit)
                                  _buildResizeControls(
                                      item, placed.spanX, placed.spanY),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 构建卡片视图，包含拖拽图标和按卡片尺寸动态调节字体
  Widget _buildItemCard({
    required BuildContext context,
    required MenuItem item,
    required double width,
    required double height,
    required int spanX,
    required int spanY,
    required bool isSelectedInEdit,
    bool isFeedback = false,
  }) {
    final backgroundColor =
        CategoryColorMapper.getCategoryBackgroundColor(item.categoryIds, widget.categories);
    final borderColor =
        CategoryColorMapper.getCategoryBorderColor(item.categoryIds, widget.categories);

    // 根据卡片占用的单元格数量开方计算动态字体缩放比例 (基准 2x2 = 4单元格 = 1.0)
    final double totalUnits = (spanX * spanY).toDouble();
    final double scale = math.sqrt(totalUnits / 4.0).clamp(1.0, 2.3);

    final double baseFontSize = widget.calculateTitleFontSize(item.title, width);
    final double dynamicTitleFontSize = (baseFontSize * scale * 0.95).clamp(12.0, 32.0);
    final double dynamicAcronymFontSize = (10.0 * scale).clamp(9.0, 20.0);
    final double dynamicCodeFontSize = (9.0 * scale).clamp(8.0, 16.0);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Card(
        elevation: isSelectedInEdit ? 6 : 2,
        margin: EdgeInsets.zero,
        shadowColor: isSelectedInEdit ? Colors.blue : Colors.grey[300],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelectedInEdit ? Colors.blue : borderColor,
            width: isSelectedInEdit ? 2.5 : 1,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                backgroundColor,
                backgroundColor.withOpacity(0.85),
              ],
            ),
          ),
          child: Stack(
            children: [
              // 编辑模式且非 feedback 树下显示拖拽图标 (Drag Handle Icon)
              if (_isEditMode && !isFeedback)
                Positioned(
                  top: 3,
                  left: 3,
                  child: Draggable<MenuItem>(
                    data: item,
                    onDragEnd: (details) {
                      _handleDragEnd(item, details.offset, spanX, spanY);
                    },
                    feedback: Material(
                      color: Colors.transparent,
                      child: Opacity(
                        opacity: 0.85,
                        child: SizedBox(
                          width: width,
                          height: height,
                          child: _buildItemCard(
                            context: context,
                            item: item,
                            width: width,
                            height: height,
                            spanX: spanX,
                            spanY: spanY,
                            isSelectedInEdit: isSelectedInEdit,
                            isFeedback: true,
                          ),
                        ),
                      ),
                    ),
                    childWhenDragging: const SizedBox.shrink(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelectedInEdit ? Colors.blue[800] : Colors.black45,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.drag_indicator, size: 14, color: Colors.white),
                          SizedBox(width: 1),
                          Icon(Icons.open_with, size: 10, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                ),

              // 菜品名称平铺展示（平铺适应，彻底杜绝 RenderFlex 溢出）
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 6.0 * scale,
                    vertical: 4.0 * scale,
                  ),
                  child: Center(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        fontSize: dynamicTitleFontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        height: 1.15,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),

              // 菜品编号标识（动态字号）
              Positioned(
                top: 4,
                right: 4,
                child: Text(
                  item.code.length > 5 ? item.code.substring(0, 5) : item.code,
                  style: TextStyle(
                    fontSize: dynamicCodeFontSize,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // 沽清 (Sold Out) 遮罩 & 徽章标识
              if (item.isSoldOut)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: (8.0 * scale).clamp(6.0, 16.0),
                          vertical: (3.0 * scale).clamp(2.0, 8.0),
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red[700],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white, width: 1.2),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black38,
                              blurRadius: 4,
                            )
                          ],
                        ),
                        child: Text(
                          'SOLD OUT',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: (11.0 * scale).clamp(10.0, 22.0),
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // 编辑模式下的占用单元格角标
              if (_isEditMode)
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelectedInEdit ? Colors.blue[700] : Colors.black54,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${spanX * spanY}单元',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建在编辑模式下调整卡片占用单元格数量的按钮面板
  Widget _buildResizeControls(MenuItem item, int spanX, int spanY) {
    return Positioned(
      bottom: 2,
      right: 2,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        color: Colors.blue[900]?.withOpacity(0.92),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 宽度 -
              _buildResizeBtn(
                icon: Icons.remove,
                tooltip: '减少宽度',
                onPressed: () {
                  if (spanX > 2 && (spanX - 1) * spanY >= 4) {
                    _updateItemConfig(item.id, spanX: spanX - 1, spanY: spanY);
                  }
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text('宽$spanX',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              // 宽度 +
              _buildResizeBtn(
                icon: Icons.add,
                tooltip: '增加宽度',
                onPressed: () {
                  if (spanX < _crossAxisCount) {
                    _updateItemConfig(item.id, spanX: spanX + 1, spanY: spanY);
                  }
                },
              ),
              const SizedBox(width: 4),
              // 高度 -
              _buildResizeBtn(
                icon: Icons.remove,
                tooltip: '减少高度',
                onPressed: () {
                  if (spanY > 2 && spanX * (spanY - 1) >= 4) {
                    _updateItemConfig(item.id, spanX: spanX, spanY: spanY - 1);
                  }
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text('高$spanY',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              // 高度 +
              _buildResizeBtn(
                icon: Icons.add,
                tooltip: '增加高度',
                onPressed: () {
                  if (spanY < 12) {
                    _updateItemConfig(item.id, spanX: spanX, spanY: spanY + 1);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResizeBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Icon(icon, size: 14, color: Colors.white),
      ),
    );
  }
}

/// 自定义 Painter，用于在编辑模式下绘制网格区域单元背景线
class GridUnitsPainter extends CustomPainter {
  final int crossAxisCount;
  final int rows;
  final double cellWidth;
  final double cellHeight;

  GridUnitsPainter({
    required this.crossAxisCount,
    required this.rows,
    required this.cellWidth,
    required this.cellHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.15)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // 绘制垂直单元格线
    for (int col = 0; col <= crossAxisCount; col++) {
      final x = col * cellWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // 绘制水平单元格线
    for (int row = 0; row <= rows; row++) {
      final y = row * cellHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GridUnitsPainter oldDelegate) {
    return oldDelegate.crossAxisCount != crossAxisCount ||
        oldDelegate.rows != rows ||
        oldDelegate.cellWidth != cellWidth ||
        oldDelegate.cellHeight != cellHeight;
  }
}
