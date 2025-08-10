import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../../common/models/menu_item.dart';
import '../../../common/models/category.dart';
import '../../../common/services/api_service.dart';
import '../../../common/models/menu_option.dart';
import 'checkout_page.dart';
import '../../../common/models/menu_item_adapter.dart';
import '../../../common/models/category_adapter.dart';
import '../../../common/models/option_groups_adapter.dart';

class OrderPage extends StatefulWidget {
  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  List<MenuItem> products = [];
  List<Category> categories = [];
  bool isLoading = true;
  String? error;
  Map<String, List<MenuOption>> optionGroups = {};
  List<SelectedProduct> orderedProducts = [];
  Map<String, String?> selectedOptions = {};
  MenuItem? selectedProduct;
  SelectedProduct? selectedOrderedProduct; // 添加选中的已点菜品状态

  @override
  void initState() {
    super.initState();
    loadData();
    loadOptions();
  }

  Future<void> loadData() async {
    final productsBox = await Hive.openBox<MenuItemAdapter>('productsBox');
    final categoriesBox = await Hive.openBox<CategoryAdapter>('categoriesBox');

    // 检查缓存是否为空（因为app重启时已经清空了缓存）
    if (productsBox.isEmpty || categoriesBox.isEmpty) {
      print('[DEBUG] 缓存为空，从API获取数据');
      await fetchData();
    } else {
      // 使用缓存数据
      setState(() {
        products = productsBox.values.map((e) => e.toMenuItem()).toList();
        products.sort((a, b) => a.sort.compareTo(b.sort));
        categories = categoriesBox.values.map((e) => e.toCategory()).toList();
        isLoading = false;
      });
      print('[DEBUG] 使用本地缓存数据，菜品数量: ${products.length}，分类数量: ${categories.length}');
    }
  }

  Future<void> fetchData() async {
    try {
      final api = ApiService();
      final prodRes = await api.get('products/active');
      final catRes = await api.get('categories/active');
      final prodData = prodRes.data['data'] as List;
      final catData = catRes.data['data'] as List;
      setState(() {
        products = prodData.map((e) => MenuItem.fromJson(e)).toList();
        products.sort((a, b) => a.sort.compareTo(b.sort));
        categories = catData.map((e) => Category.fromJson(e)).toList();
        isLoading = false;
      });
      final productsBox = Hive.box<MenuItemAdapter>('productsBox');
      final categoriesBox = Hive.box<CategoryAdapter>('categoriesBox');
      await productsBox.clear();
      await categoriesBox.clear();
      for (var item in products) {
        await productsBox.add(MenuItemAdapter.fromMenuItem(item));
      }
      for (var cat in categories) {
        await categoriesBox.add(CategoryAdapter.fromCategory(cat));
      }
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> loadOptions() async {
    try {
      // 确保 box 已经打开
      Box<OptionGroupsAdapter> optionGroupsBox;
      if (Hive.isBoxOpen('optionGroupsBox')) {
        optionGroupsBox = Hive.box<OptionGroupsAdapter>('optionGroupsBox');
      } else {
        optionGroupsBox = await Hive.openBox<OptionGroupsAdapter>('optionGroupsBox');
      }
      
      final adapter = optionGroupsBox.get('groups');
      
      // 检查缓存是否为空（因为app重启时已经清空了缓存）
      if (adapter == null || adapter.groups.isEmpty) {
        print('[DEBUG] 选项配置缓存为空，从API获取数据');
        await fetchOptions();
      } else {
        setState(() {
          optionGroups = adapter.groups;
        });
        print('[DEBUG] ✅ 使用本地缓存的 optionGroups，组数: ${adapter.groups.length}');
      }

    } catch (e) {
      print('[DEBUG] ❌ loadOptions 出错: $e');
      // 出错时尝试调用 API
      await fetchOptions();
    }
  }

  Future<void> fetchOptions() async {
    try {
      final api = ApiService();
      final response = await api.get('attributes/group');
      final data = response.data['data'] as Map<String, dynamic>;
      final groups = data.map((type, list) => MapEntry(
        type,
        (list as List).map((e) => MenuOption.fromJson(e)).toList(),
      ));
      setState(() {
        optionGroups = groups;
      });
      final optionGroupsBox = Hive.box<OptionGroupsAdapter>('optionGroupsBox');
      await optionGroupsBox.put('groups', OptionGroupsAdapter(groups: groups));
    } catch (e) {
      // 可选：处理错误
    }
  }

  // 单击：选中菜品（添加描边效果）
  void _selectOrderedProduct(SelectedProduct ordered) {
    setState(() {
      selectedOrderedProduct = selectedOrderedProduct == ordered ? null : ordered;
    });
  }

  // 双击：复制当前菜品
  void _duplicateOrderedProduct(SelectedProduct ordered) {
    setState(() {
      final duplicatedProduct = SelectedProduct(
        product: ordered.product,
        options: ordered.options.map((opt) => SelectedOption(
          type: opt.type,
          option: opt.option,
        )).toList(),
        quantity: ordered.quantity,
      );
      orderedProducts.add(duplicatedProduct);
      // 将新复制的菜品设置为选中状态
      selectedOrderedProduct = duplicatedProduct;
    });
  }

  // 增加数量
  void _increaseQuantity(SelectedProduct ordered) {
    setState(() {
      ordered.quantity++;
    });
  }

  // 减少数量
  void _decreaseQuantity(SelectedProduct ordered) {
    setState(() {
      if (ordered.quantity > 1) {
        ordered.quantity--;
      } else {
        // 如果数量为1，再减就删除这个菜品
        orderedProducts.remove(ordered);
      }
    });
  }

  // 修改菜品选项
  void _editProductOptions(SelectedProduct ordered) {
    Map<String, String?> editingOptions = {};
    // 初始化当前选项
    for (var opt in ordered.options) {
      editingOptions[opt.type] = opt.option.name;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('修改 ${ordered.product.title}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: optionGroups.keys.map((type) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(type, style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 8),
                          DropdownButton<String>(
                            isExpanded: true,
                            hint: Text('选择 $type'),
                            value: editingOptions[type],
                            items: optionGroups[type]!.map((opt) {
                              return DropdownMenuItem<String>(
                                value: opt.name,
                                child: Row(
                                  children: [
                                    Expanded(child: Text(opt.name)),
                                    if (opt.extraCost > 0)
                                      Text('+\$${opt.extraCost}',
                                        style: TextStyle(color: Colors.red, fontSize: 12)),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setDialogState(() {
                                editingOptions[type] = val;
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      ordered.options.clear();
                      editingOptions.forEach((type, optionName) {
                        if (optionName != null) {
                          final option = optionGroups[type]!.firstWhere((o) => o.name == optionName);
                          ordered.options.add(SelectedOption(type: type, option: option));
                        }
                      });
                    });
                    Navigator.pop(context);
                  },
                  child: Text('确认'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 复制并修改菜品
  void _copyAndEditProduct(SelectedProduct ordered) {
    setState(() {
      final newProduct = SelectedProduct(
        product: ordered.product,
        options: ordered.options.map((opt) => SelectedOption(
          type: opt.type,
          option: opt.option,
        )).toList(),
      );
      orderedProducts.add(newProduct);
    });
    // 立即打开编辑对话框
    Future.delayed(Duration(milliseconds: 100), () {
      _editProductOptions(orderedProducts.last);
    });
  }

  // 查看菜品详情
  void _showProductDetails(SelectedProduct ordered) {
    double totalPrice = ordered.product.sellingPrice;
    for (var opt in ordered.options) {
      totalPrice += opt.option.extraCost;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(ordered.product.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('菜品代码: ${ordered.product.code}'),
              Text('快捷键: ${ordered.product.acronym}'),
              Text('基础价格: \$${ordered.product.sellingPrice.toStringAsFixed(2)}'),
              SizedBox(height: 16),
              if (ordered.options.isNotEmpty) ...[
                Text('选项配置:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                ...ordered.options.map((opt) => Padding(
                  padding: const EdgeInsets.only(left: 16.0, bottom: 4.0),
                  child: Row(
                    children: [
                      Expanded(child: Text('${opt.type}: ${opt.option.name}')),
                      if (opt.option.extraCost > 0)
                        Text('+\$${opt.option.extraCost.toStringAsFixed(2)}',
                          style: TextStyle(color: Colors.red)),
                    ],
                  ),
                )),
                SizedBox(height: 16),
              ],
              Text('总价: \$${totalPrice.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  // VOID操作 - 删除当前已点菜品（最后一个）
  void _voidOrder() {
    if (orderedProducts.isEmpty) return;

    setState(() {
      orderedProducts.removeLast(); // 删除最后一个菜品
    });
  }

  // CLEAR操作 - 清空订单
  void _clearOrder() {
    if (orderedProducts.isEmpty) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('清空订单'),
          content: Text('确定要清空所有已点菜品吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  orderedProducts.clear();
                });
                Navigator.pop(context);
              },
              child: Text('确认'),
            ),
          ],
        );
      },
    );
  }

  // X按钮 - 数量设置
  void _showQuantitySelector() {
    if (orderedProducts.isEmpty) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('设置数量'),
          content: Text('选择要应用到最后添加菜品的数量：'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消'),
            ),
            ...([1, 2, 3, 4, 6].map((quantity) =>
              TextButton(
                onPressed: () {
                  setState(() {
                    if (orderedProducts.isNotEmpty) {
                      orderedProducts.last.quantity = quantity;
                    }
                  });
                  Navigator.pop(context);
                },
                child: Text('x$quantity'),
              ),
            )).toList(),
          ],
        );
      },
    );
  }

  // Custom按钮的操作
  void _customAction() {
    // TODO: 实现自定义按钮的功能
  }

  // 显示选项弹窗
  void _showOptionDialog(String type) {
    if (orderedProducts.isEmpty) {
      // 移除弹窗提示，直接返回
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('选择 $type', style: TextStyle(fontSize: 16)),
          contentPadding: EdgeInsets.all(16),
          content: Container(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5, // 改为5列
                crossAxisSpacing: 6, // 减小间距
                mainAxisSpacing: 6, // 减小间距
                childAspectRatio: 1.8, // 调整宽高比
              ),
              itemCount: optionGroups[type]?.length ?? 0,
              itemBuilder: (context, index) {
                final option = optionGroups[type]![index];
                return Card(
                  margin: EdgeInsets.zero, // 移除外边距
                  child: InkWell(
                    onTap: () {
                      _addOptionToLastProduct(type, option);
                      Navigator.pop(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4.0), // 减小内边距
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            option.name,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold), // 增大字体
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (option.extraCost > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Text(
                                '+\$${option.extraCost.toStringAsFixed(2)}',
                                style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600), // 增大字体
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消'),
            ),
          ],
        );
      },
    );
  }

  // 智能添加菜品方法
  void _addProductIntelligently(MenuItem item) {
    setState(() {
      // 检查已点菜品中是否有相同菜品且没有选项的
      final existingProductIndex = orderedProducts.indexWhere(
        (product) => product.product.id == item.id && product.options.isEmpty,
      );

      if (existingProductIndex != -1) {
        // 如果找到相同菜品且没有选项，直接增加该菜品的数量
        orderedProducts[existingProductIndex].quantity++;
        // 将增加数量的菜品设置为选中状态
        selectedOrderedProduct = orderedProducts[existingProductIndex];
        return;
      }

      // 否则添加新的菜品项
      selectedProduct = item;
      final newProduct = SelectedProduct(product: item, options: []);
      orderedProducts.add(newProduct);
      // 将新添加的菜品设置为选中状态
      selectedOrderedProduct = newProduct;
      selectedOptions.clear();
    });
  }

  // 优化选项添加方法 - 支持为选中的菜品添加选项
  void _addOptionToLastProduct(String type, MenuOption option) {
    // 优先为选中的菜品添加选项，如果没有选中的菜品则为最后一个菜品添加选项
    SelectedProduct? targetProduct;

    if (selectedOrderedProduct != null) {
      targetProduct = selectedOrderedProduct;
    } else if (orderedProducts.isNotEmpty) {
      targetProduct = orderedProducts.last;
    } else {
      return;
    }

    setState(() {
      // 检查是否已存在相同类型和选项的组合
      final existingOptionIndex = targetProduct!.options.indexWhere(
        (opt) => opt.type == type && opt.option.id == option.id,
      );

      if (existingOptionIndex != -1) {
        // 如果已存在相同的选项，静默处理（不显示弹窗）
        return;
      } else {
        // 支持同类型多选 - 不移除同类型的旧选项，直接添加新选项
        // targetProduct.options.removeWhere((opt) => opt.type == type);

        // 添加新选项
        targetProduct.options.add(SelectedOption(type: type, option: option));
      }
    });
  }

  // 动态计算标题字体大小
  double _calculateTitleFontSize(String title, double containerWidth) {
    final baseSize = 16.0;
    final maxSize = 18.0;
    final minSize = 10.0;

    // 预估文字宽度（粗略计算）
    final estimatedCharWidth = baseSize * 0.6; // 中文字符大约是字体大小的0.6倍宽
    final availableWidth = containerWidth - 40; // 减去padding和右侧code按钮空间
    final maxCharsPerLine = (availableWidth / estimatedCharWidth).floor();

    // 根据标题长度和可用宽度调整字体大小
    if (title.length <= maxCharsPerLine) {
      return baseSize; // 一行能显示完，使用基础大小
    } else if (title.length <= maxCharsPerLine * 2) {
      return (baseSize - 1).clamp(minSize, maxSize); // 两行显示，稍微小一点
    } else {
      return (baseSize - 3).clamp(minSize, maxSize); // 需要更多行，使用更小字体
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 动态计算已点菜品区域高度 - 优化选项累加处理
            final double minHeight = 120.0; // 增加最小高度以容纳更多选项
            final double maxHeight = 280.0; // 增加最大高度以容纳更多选项
            final double baseItemHeight = 32.0; // 基础菜品信息高度
            final double optionHeight = 14.0; // 增加每个选项的高度以提供更好的可读性
            final int crossAxisCount = 3; // 3列显示

            // 计算实际需要的高度 - 考虑选项数量和累加效果
            double maxCardHeight = baseItemHeight;
            for (var product in orderedProducts) {
              // 为每个菜品计算高度，包括基础高度、选项高度和内边距
              double cardHeight = baseItemHeight + (product.options.length * optionHeight) + 16; // 增加padding
              if (cardHeight > maxCardHeight) maxCardHeight = cardHeight;
            }

            final int rowCount = (orderedProducts.length / crossAxisCount).ceil();
            final double calculatedHeight = (rowCount * maxCardHeight) + 32; // 增加容器padding
            final double actualHeight = calculatedHeight.clamp(minHeight, maxHeight);

            // 为Web环境优化布局计算
            final screenHeight = constraints.maxHeight;
            final topSectionHeight = actualHeight; // 动态已点菜品区域
            final bottomButtonHeight = 60.0; // 减少操作区域高度，使其更紧凑
            final availableHeight = screenHeight - topSectionHeight - bottomButtonHeight;

            return Column(
              children: [
                // 已点菜品列表 - 动态高度
                Container(
                  height: topSectionHeight,
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: orderedProducts.isEmpty
                        ? Center(
                            child: Text(
                              'No items ordered yet',
                              style: TextStyle(color: Colors.grey[600], fontSize: 14),
                            ),
                          )
                        : ListView(
                            physics: actualHeight >= maxHeight
                                ? AlwaysScrollableScrollPhysics()
                                : NeverScrollableScrollPhysics(),
                            children: [
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: orderedProducts.map((ordered) {
                                  // 计算每个卡片的宽度（3列布局，平均分配宽度）
                                  // 已点菜品区域是跨越整个屏幕宽度的，不需要减去侧边栏
                                  final availableWidth = constraints.maxWidth - 32; // 只减去容器的padding(16*2)
                                  final cardWidth = (availableWidth - 8) / 3; // 减去间距，然后除以3列

                                  return SizedBox(
                                    width: cardWidth,
                                    child: GestureDetector(
                                      onTap: () => _selectOrderedProduct(ordered),
                                      onDoubleTap: () => _duplicateOrderedProduct(ordered),
                                      child: LayoutBuilder(
                                        builder: (context, orderedCardConstraints) {
                                          // 检查当前菜品是否被选中
                                          final isSelected = selectedOrderedProduct == ordered;

                                          return Card(
                                            margin: EdgeInsets.zero,
                                            // 为选中的菜品添加描边效果
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              side: BorderSide(
                                                color: isSelected ? Colors.blue[600]! : Colors.grey[300]!,
                                                width: 1.0,
                                              ),
                                            ),
                                            // 为选中的菜品添加阴影效果
                                            elevation: isSelected ? 8 : 2,
                                            shadowColor: isSelected ? Colors.blue[200] : Colors.grey[300],
                                            // 为选中的菜品添加背景颜色变化
                                            color: Colors.white,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.all(4.0),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    // 菜品标题行 - 响应式适配，优先级最高
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          flex: 4, // 给菜品名称绝对优先权
                                                          child: Text(
                                                            ordered.product.title,
                                                            style: TextStyle(
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: _calculateTitleFontSize(ordered.product.title, orderedCardConstraints.maxWidth * 0.7), // 动态字体
                                                              height: 1.1,
                                                              color: isSelected ? Colors.blue[800] : Colors.black87,
                                                            ),
                                                            maxLines: null, // 允许多行
                                                            overflow: TextOverflow.visible, // 完全显示
                                                          ),
                                                        ),
                                                        // 数量控制按钮 - 增大尺寸便于点击
                                                        Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            // 减号按钮
                                                            GestureDetector(
                                                              onTap: () => _decreaseQuantity(ordered),
                                                              child: Container(
                                                                width: 20,
                                                                height: 20,
                                                                margin: EdgeInsets.only(left: 4),
                                                                decoration: BoxDecoration(
                                                                  color: Colors.red[100],
                                                                  borderRadius: BorderRadius.circular(10),
                                                                  border: Border.all(color: Colors.red[200]!, width: 0.5),
                                                                ),
                                                                child: Icon(
                                                                  Icons.remove,
                                                                  size: 12,
                                                                  color: Colors.red[700],
                                                                ),
                                                              ),
                                                            ),
                                                            // 数量显示
                                                            Container(
                                                              width: 28,
                                                              alignment: Alignment.center,
                                                              child: Text(
                                                                '${ordered.quantity}',
                                                                style: TextStyle(
                                                                  fontWeight: FontWeight.bold,
                                                                  fontSize: 12,
                                                                  color: Colors.blue[700],
                                                                ),
                                                              ),
                                                            ),
                                                            // 加号按钮 - 增大可点击区域
                                                            GestureDetector(
                                                              onTap: () => _increaseQuantity(ordered),
                                                              child: Container(
                                                                width: 20,
                                                                height: 20,
                                                                decoration: BoxDecoration(
                                                                  color: Colors.green[100],
                                                                  borderRadius: BorderRadius.circular(10),
                                                                  border: Border.all(color: Colors.green[200]!, width: 0.5),
                                                                ),
                                                                child: Icon(
                                                                  Icons.add,
                                                                  size: 12,
                                                                  color: Colors.green[700],
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                    // 价格行 - 固定在底部
                                                    SizedBox(height: 2),
                                                    Row(
                                                      children: [
                                                        Expanded(child: Container()), // 占位
                                                        Text(
                                                          '￥${ordered.product.sellingPrice.toStringAsFixed(2)}',
                                                          style: TextStyle(fontSize: 9, color: Colors.green[700]),
                                                        ),
                                                      ],
                                                    ),
                                                    // 显示所有选项 - 动态高度
                                                    ...ordered.options.map((opt) {
                                                      return Padding(
                                                        padding: const EdgeInsets.only(top: 1.0),
                                                        child: Row(
                                                          children: [
                                                            Expanded(
                                                              child: Text(
                                                                ' - ${opt.option.name}',
                                                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,color: Colors.grey[600]),
                                                                overflow: TextOverflow.ellipsis,
                                                                maxLines: 1,
                                                              ),
                                                            ),
                                                            if (opt.option.extraCost > 0)
                                                              Text(
                                                                '+\$ ${opt.option.extraCost.toStringAsFixed(2)}',
                                                                style: TextStyle(fontSize: 8,  color: Colors.red),
                                                              ),
                                                          ],
                                                        ),
                                                      );
                                                    }),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                  ),
                ),
                // 主内容区域 - 使用计算出的固定高度
                SizedBox(
                  height: availableHeight,
                  child: Row(
                    children: [
                      // 分类侧边栏 - 现在包含菜品选项区
                      Container(
                        width: 140, // 增加宽度以提供更好的显示效果
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
                            // 分类标题区域
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
                                )
                              ),
                            ),
                            // 分类列表区域
                            Expanded(
                              child: Container(
                                margin: EdgeInsets.all(2), // 减少边距
                                child: ListView.builder(
                                  itemCount: categories.where((c) => c.parentId == null).length,
                                  itemBuilder: (context, index) {
                                    final parent = categories.where((c) => c.parentId == null).toList()[index];
                                    final children = categories.where((c) => c.parentId == parent.id).toList();

                                    // 如果没有子分类，显示为普通ListTile
                                    if (children.isEmpty) {
                                      return Container(
                                        margin: EdgeInsets.only(bottom: 1),
                                        child: Material(
                                          color: Colors.grey[50],
                                          child: InkWell(
                                            onTap: () {
                                              // TODO: 实现分类筛选功能
                                            },
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

                                    // 有子分类时显示ExpansionTile
                                    return Container(
                                      margin: EdgeInsets.only(bottom: 1), // 减少间距
                                      child: ExpansionTile(
                                        title: Text(
                                          parent.title,
                                          style: TextStyle(
                                            fontSize: 12, // 减小字体
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey[800],
                                          )
                                        ),
                                        backgroundColor: Colors.white,
                                        collapsedBackgroundColor: Colors.grey[50],
                                        iconColor: Colors.blue[600],
                                        collapsedIconColor: Colors.grey[600],
                                        tilePadding: EdgeInsets.symmetric(horizontal: 8, vertical: 2), // 减少内边距
                                        childrenPadding: EdgeInsets.zero,
                                        children: children.map((child) =>
                                          Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              onTap: () {
                                                // TODO: 实现分类筛选功能
                                              },
                                              child: Container(
                                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6), // 减少内边距
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.arrow_right, size: 12, color: Colors.grey[600]), // 减小图标
                                                    SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        child.title,
                                                        style: TextStyle(
                                                          fontSize: 11, // 减小字体
                                                          color: Colors.grey[700],
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          )
                                        ).toList(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            // 菜品选项区 - 优化显示效果
                            Container(
                              height: 230, // 增加高度
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.blue[50]!, Colors.blue[100]!],
                                ),
                                border: Border(
                                  top: BorderSide(color: Colors.blue[200]!, width: 2),
                                ),
                              ),
                              child: Column(
                                children: [
                                  // 选项标题区域
                                  Container(
                                    height: 35,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Colors.blue[200]!, Colors.blue[300]!],
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'Options',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Colors.blue[800],
                                      )
                                    ),
                                  ),
                                  // 选项按钮区域
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(6.0),
                                      child: Column(
                                        children: optionGroups.keys.map((type) {
                                          // 获取当前已选择的选项
                                          String? currentOption;
                                          if (orderedProducts.isNotEmpty) {
                                            final lastProduct = orderedProducts.last;
                                            try {
                                              final selectedOpt = lastProduct.options.firstWhere(
                                                (opt) => opt.type == type,
                                              );
                                              currentOption = selectedOpt.option.name;
                                            } catch (e) {
                                              // 如果没有找到该类型的选项，currentOption保持为null
                                            }
                                          }

                                          return Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.only(bottom: 3.0),
                                              child: SizedBox(
                                                width: double.infinity,
                                                child: ElevatedButton(
                                                  onPressed: () => _showOptionDialog(type),
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        type,
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                      if (currentOption != null)
                                                        Text(
                                                          currentOption,
                                                          style: TextStyle(
                                                            fontSize: 8,
                                                            fontWeight: FontWeight.normal,
                                                          ),
                                                          overflow: TextOverflow.ellipsis,
                                                          maxLines: 1,
                                                        ),
                                                    ],
                                                  ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: currentOption != null ? Colors.blue[400] : Colors.grey[200],
                                                    foregroundColor: currentOption != null ? Colors.white : Colors.grey[700],
                                                    elevation: currentOption != null ? 3 : 1,
                                                    shadowColor: currentOption != null ? Colors.blue[200] : Colors.grey[300],
                                                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                                    minimumSize: Size(0, 0),
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                      side: BorderSide(
                                                        color: currentOption != null ? Colors.blue[600]! : Colors.grey[400]!,
                                                        width: 1,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 主内容区
                      Expanded(
                        child: Column(
                          children: [
                            // 搜索区
                            Container(
                              height: 40,
                              color: Colors.grey[100],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.search, size: 20),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        decoration: InputDecoration(
                                          hintText: 'Search menu...',
                                          border: InputBorder.none,
                                          isDense: true,
                                        ),
                                        style: TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // 菜品网格 - 使用所有剩余空间
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [Colors.grey[50]!, Colors.white],
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0), // 减少内边距
                                  child: isLoading
                                      ? Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              CircularProgressIndicator(color: Colors.blue[400]),
                                              SizedBox(height: 16),
                                              Text('Loading menu...', style: TextStyle(color: Colors.grey[600])),
                                            ],
                                          ),
                                        )
                                      : error != null
                                          ? Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                                                  SizedBox(height: 16),
                                                  Text('Error: ' + error!, style: TextStyle(color: Colors.red[600])),
                                                ],
                                              ),
                                            )
                                          : GridView.builder(
                                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount: 4,
                                                crossAxisSpacing: 2, // 减少间距
                                                mainAxisSpacing: 2, // 减少间距
                                                childAspectRatio: 1.1, // 调整宽高比，使卡片更紧凑
                                              ),
                                              itemCount: products.length,
                                              itemBuilder: (context, index) {
                                                final item = products[index];
                                                return LayoutBuilder(
                                                  builder: (context, cardConstraints) {
                                                    return Card(
                                                      elevation: 2,
                                                      shadowColor: Colors.grey[300],
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                        side: BorderSide(color: Colors.grey[200]!, width: 1),
                                                      ),
                                                      child: InkWell(
                                                        onTap: () => _addProductIntelligently(item),
                                                        borderRadius: BorderRadius.circular(8),
                                                        child: Container(
                                                          decoration: BoxDecoration(
                                                            borderRadius: BorderRadius.circular(8),
                                                            gradient: LinearGradient(
                                                              begin: Alignment.topCenter,
                                                              end: Alignment.bottomCenter,
                                                              colors: [Colors.white, Colors.grey[50]!],
                                                            ),
                                                          ),
                                                          child: Stack(
                                                            children: [
                                                              // 主要内容
                                                              Padding(
                                                                padding: const EdgeInsets.all(6.0),
                                                                child: Column(
                                                                  children: [
                                                                    // 菜品标题 - 绝对优先级，占用所有可用空间
                                                                    Expanded(
                                                                      child: Container(
                                                                        width: double.infinity,
                                                                        padding: const EdgeInsets.only(right: 20.0), // 为右上角的code留出空间
                                                                        child: Center(
                                                                          child: Text(
                                                                            item.title,
                                                                            style: TextStyle(
                                                                              fontSize: _calculateTitleFontSize(item.title, cardConstraints.maxWidth),
                                                                              fontWeight: FontWeight.bold,
                                                                              color: Colors.black87,
                                                                              height: 1.1, // 紧凑行高
                                                                            ),
                                                                            textAlign: TextAlign.center,
                                                                            maxLines: null, // 允许多行显示
                                                                            overflow: TextOverflow.visible, // 确保文字完全显示
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    // 缩写显示 - 固定在底部，只有有空间时才显示
                                                                    if (cardConstraints.maxHeight > 60) // 只有足够高度时才显示缩写
                                                                      Container(
                                                                        margin: EdgeInsets.only(top: 2),
                                                                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                                        decoration: BoxDecoration(
                                                                          color: Colors.blue[100],
                                                                          borderRadius: BorderRadius.circular(3),
                                                                          border: Border.all(color: Colors.blue[300]!, width: 0.5),
                                                                        ),
                                                                        child: Text(
                                                                          item.acronym,
                                                                          style: TextStyle(
                                                                            fontSize: 9,
                                                                            color: Colors.blue[800],
                                                                            fontWeight: FontWeight.w600,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                  ],
                                                                ),
                                                              ),
                                                              // 悬浮在右上角的圆形code
                                                              Positioned(
                                                                top: 4,
                                                                right: 4,
                                                                child: Text(
                                                                  item.code.length > 4
                                                                      ? item.code.substring(0, 4)
                                                                      : item.code,
                                                                  style: TextStyle(
                                                                    fontSize: 9,
                                                                    color: Colors.grey[600],
                                                                    fontWeight: FontWeight.w500,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                );
                                              },
                                            ),
                              ),
                            ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // 操作区域 - 优化显示效果
                Container(
                  height: 60.0, // 减少高度以提供更紧凑的视觉效果
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.grey[200]!, Colors.grey[300]!],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                  child: Row(
                    children: [
                      // VOID按钮
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3.0),
                          child: ElevatedButton.icon(
                            onPressed: _voidOrder,
                            icon: Icon(Icons.delete_outline, size: 16),
                            label: Text('VOID', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[300],
                              foregroundColor: Colors.white,
                              elevation: 3,
                              shadowColor: Colors.red[200],
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // CLEAR按钮
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3.0),
                          child: ElevatedButton.icon(
                            onPressed: _clearOrder,
                            icon: Icon(Icons.clear_all, size: 16),
                            label: Text('CLEAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange[300],
                              foregroundColor: Colors.white,
                              elevation: 3,
                              shadowColor: Colors.orange[200],
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // X按钮 - 数量设置
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3.0),
                          child: ElevatedButton.icon(
                            onPressed: _showQuantitySelector,
                            icon: Icon(Icons.add_circle_outline, size: 16),
                            label: Text('QTY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple[300],
                              foregroundColor: Colors.white,
                              elevation: 3,
                              shadowColor: Colors.purple[200],
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Custom按钮
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3.0),
                          child: ElevatedButton.icon(
                            onPressed: _customAction,
                            icon: Icon(Icons.settings, size: 16),
                            label: Text('CUSTOM', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[300],
                              foregroundColor: Colors.white,
                              elevation: 3,
                              shadowColor: Colors.blue[200],
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Order按钮 - 突出显示
                      Expanded(
                        flex: 2, // 给Order按钮更大的空间
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3.0),
                          child: ElevatedButton.icon(
                            onPressed: orderedProducts.isEmpty ? null : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => CheckoutPage(
                                    orderedProducts: orderedProducts,
                                  ),
                                ),
                              );
                            },
                            icon: Icon(Icons.shopping_cart, size: 18),
                            label: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('ORDER', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                if (orderedProducts.isNotEmpty)
                                  Text('${orderedProducts.length} items', style: TextStyle(fontSize: 9)),
                              ],
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: orderedProducts.isEmpty ? Colors.grey[400] : Colors.green[500],
                              foregroundColor: Colors.white,
                              elevation: orderedProducts.isEmpty ? 1 : 6,
                              shadowColor: orderedProducts.isEmpty ? Colors.grey[300] : Colors.green[300],
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              animationDuration: Duration(milliseconds: 200),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class SelectedProduct {
  final MenuItem product;
  List<SelectedOption> options;
  int quantity; // 添加数量属性

  SelectedProduct({
    required this.product,
    required this.options,
    this.quantity = 1, // 默认数量为1
  });
}

class SelectedOption {
  final String type;
  final MenuOption option;

  SelectedOption({required this.type, required this.option});
}
