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

  // 单击：添加一个相同的菜品（不包括选项配置）
  void _addSameProduct(SelectedProduct ordered) {
    setState(() {
      orderedProducts.add(SelectedProduct(
        product: ordered.product,
        options: [], // 不包括选项配置
      ));
    });
  }

  // 双击：留空
  void _removeProduct(SelectedProduct ordered) {
    // 暂时留空，后续可以添加功能
  }

  // 长按：暂时留空
  void _showProductOptions(SelectedProduct ordered) {
    // 暂时留空，后续可以添加功能
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
                                      Text('+¥${opt.extraCost}',
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
              Text('基础价格: ¥${ordered.product.sellingPrice.toStringAsFixed(2)}'),
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
                        Text('+¥${opt.option.extraCost.toStringAsFixed(2)}',
                          style: TextStyle(color: Colors.red)),
                    ],
                  ),
                )),
                SizedBox(height: 16),
              ],
              Text('总价: ¥${totalPrice.toStringAsFixed(2)}',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 动态计算已点菜品区域高度
            final double minHeight = 50.0; // 减少最小高度从60到50
            final double maxHeight = 200.0; // 减少最大高度从240到200
            final double baseItemHeight = 32.0; // 减少基础菜品信息高度从40到32
            final double optionHeight = 12.0; // 减少每个选项的高度从16到12
            final int crossAxisCount = 3; // 3列显示

            // 计算实际需要的高度 - 考虑选项数量
            double maxCardHeight = baseItemHeight;
            for (var product in orderedProducts) {
              double cardHeight = baseItemHeight + (product.options.length * optionHeight) + 12; // 减少padding从16到12
              if (cardHeight > maxCardHeight) maxCardHeight = cardHeight;
            }

            final int rowCount = (orderedProducts.length / crossAxisCount).ceil();
            final double calculatedHeight = (rowCount * maxCardHeight) + 24; // 减少padding从32到24
            final double actualHeight = calculatedHeight.clamp(minHeight, maxHeight);

            // 为Web环境优化布局计算
            final screenHeight = constraints.maxHeight;
            final topSectionHeight = actualHeight; // 动态已点菜品区域
            final bottomButtonHeight = 68.0; // 结账按钮区域
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
                              '暂无已点菜品',
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
                                      onTap: () => _addSameProduct(ordered),
                                      child: Card(
                                        margin: EdgeInsets.zero,
                                        child: Padding(
                                          padding: const EdgeInsets.all(4.0), // 减少内边距从6.0到4.0
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // 主要信息行 - 包含菜品名、价格和数量控制
                                              Row(
                                                children: [
                                                  Expanded(
                                                    flex: 3, // 给菜品名称更多空间
                                                    child: Text(
                                                      ordered.product.title,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 12
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                    ),
                                                  ),
                                                  // 减号按钮
                                                  GestureDetector(
                                                    onTap: () => _decreaseQuantity(ordered),
                                                    child: Container(
                                                      width: 14,
                                                      height: 14,
                                                      margin: EdgeInsets.only(left: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red[100],
                                                        borderRadius: BorderRadius.circular(7),
                                                        border: Border.all(color: Colors.red[300]!, width: 0.5),
                                                      ),
                                                      child: Icon(
                                                        Icons.remove,
                                                        size: 8,
                                                        color: Colors.red[700],
                                                      ),
                                                    ),
                                                  ),
                                                  // 数量显示
                                                  Container(
                                                    width: 24,
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
                                                  // 加号按钮
                                                  GestureDetector(
                                                    onTap: () => _increaseQuantity(ordered),
                                                    child: Container(
                                                      width: 14,
                                                      height: 14,
                                                      decoration: BoxDecoration(
                                                        color: Colors.green[100],
                                                        borderRadius: BorderRadius.circular(7),
                                                        border: Border.all(color: Colors.green[300]!, width: 0.5),
                                                      ),
                                                      child: Icon(
                                                        Icons.add,
                                                        size: 8,
                                                        color: Colors.green[700],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              // 价格行
                                              SizedBox(height: 1),
                                              Row(
                                                children: [
                                                  Expanded(child: Container()), // 占位
                                                  Text(
                                                    '¥${ordered.product.sellingPrice.toStringAsFixed(2)}',
                                                    style: TextStyle(fontSize: 9, color: Colors.green[700]),
                                                  ),
                                                ],
                                              ),
                                              // 显示所有选项
                                              ...ordered.options.map((opt) {
                                                return Padding(
                                                  padding: const EdgeInsets.only(top: 1.0),
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          '${opt.type}: ${opt.option.name}',
                                                          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                                          overflow: TextOverflow.ellipsis,
                                                          maxLines: 1,
                                                        ),
                                                      ),
                                                      if (opt.option.extraCost > 0)
                                                        Text(
                                                          '+¥${opt.option.extraCost.toStringAsFixed(2)}',
                                                          style: TextStyle(fontSize: 7, color: Colors.red),
                                                        ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ],
                                          ),
                                        ),
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
                      // 分类侧边栏
                      Container(
                        width: 120,
                        color: Colors.grey[200],
                        child: Column(
                          children: [
                            Container(
                              height: 40,
                              alignment: Alignment.center,
                              child: Text('Categories', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            Expanded(
                              child: ListView.builder(
                                itemCount: categories.where((c) => c.parentId == null).length,
                                itemBuilder: (context, index) {
                                  final parent = categories.where((c) => c.parentId == null).toList()[index];
                                  final children = categories.where((c) => c.parentId == parent.id).toList();
                                  return ExpansionTile(
                                    title: Text(parent.title, style: TextStyle(fontSize: 12)),
                                    children: children.map((child) => ListTile(
                                      title: Text(child.title, style: TextStyle(fontSize: 11)),
                                      dense: true,
                                    )).toList(),
                                  );
                                },
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
                            // 菜品选项栏
                            Container(
                              height: 40,
                              color: Colors.blue[100],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: optionGroups.keys.map((type) {
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 12.0),
                                        child: DropdownButton<String>(
                                          hint: Text(type, style: TextStyle(fontSize: 12)),
                                          value: selectedProduct != null && selectedProduct!.title == orderedProducts.isNotEmpty ? selectedOptions[type] : null,
                                          items: optionGroups[type]!.map((opt) {
                                            return DropdownMenuItem<String>(
                                              value: opt.name,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(opt.name, style: TextStyle(fontSize: 12)),
                                                  if (opt.extraCost > 0)
                                                    Padding(
                                                      padding: const EdgeInsets.only(left: 8.0),
                                                      child: Text('+¥${opt.extraCost}', style: TextStyle(fontSize: 10, color: Colors.red)),
                                                    ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            if (orderedProducts.isEmpty || selectedProduct == null) return;
                                            setState(() {
                                              selectedOptions[type] = val;
                                              final last = orderedProducts.last;
                                              final opt = optionGroups[type]!.firstWhere((o) => o.name == val);
                                              last.options.add(SelectedOption(type: type, option: opt));
                                            });
                                          },
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                            // 菜品网格 - 使用剩余空间
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: isLoading
                                    ? Center(child: CircularProgressIndicator())
                                    : error != null
                                        ? Center(child: Text('Error: ' + error!))
                                        : GridView.builder(
                                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 4,
                                              crossAxisSpacing: 16,
                                              mainAxisSpacing: 16,
                                              childAspectRatio: 1.4, // 增加宽高比，让卡片更扁平
                                            ),
                                            itemCount: products.length,
                                            itemBuilder: (context, index) {
                                              final item = products[index];
                                              return Card(
                                                child: InkWell(
                                                  onTap: () {
                                                    setState(() {
                                                      selectedProduct = item;
                                                      orderedProducts.add(SelectedProduct(product: item, options: []));
                                                      selectedOptions.clear();
                                                    });
                                                  },
                                                  child: Padding(
                                                    padding: const EdgeInsets.all(6.0), // 减小内边距
                                                    child: Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        // 显示菜品代码
                                                        Text(
                                                          item.code,
                                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                                          textAlign: TextAlign.center,
                                                        ),
                                                        SizedBox(height: 2),
                                                        // 显示快捷键acronym
                                                        Container(
                                                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            color: Colors.orange[100],
                                                            borderRadius: BorderRadius.circular(3),
                                                            border: Border.all(color: Colors.orange[300]!, width: 0.5),
                                                          ),
                                                          child: Text(
                                                            item.acronym,
                                                            style: TextStyle(
                                                              fontSize: 9,
                                                              color: Colors.orange[800],
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                        ),
                                                        SizedBox(height: 4),
                                                        // 显示菜品标题
                                                        Expanded(
                                                          child: Text(
                                                            item.title,
                                                            style: TextStyle(fontSize: 10),
                                                            textAlign: TextAlign.center,
                                                            maxLines: 2,
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
                      ),
                    ],
                  ),
                ),
                // 结账按钮 - 固定高度
                Container(
                  height: bottomButtonHeight,
                  padding: const EdgeInsets.all(16.0),
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: orderedProducts.isEmpty ? null : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => CheckoutPage(
                            orderedProducts: orderedProducts,
                          ),
                        ),
                      );
                    },
                    child: Text('结账'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
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
