import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../common/models/menu_item.dart';
import '../../common/models/category.dart';
import '../../common/services/api_service.dart';
import '../../common/models/menu_option.dart';
import '../../common/services/sync_service.dart';
import '../keyboard_handlers/action_key_handler.dart';
import '../utils/quick_input_manager.dart';
import '../widgets/quick_input_overlay.dart';
import 'checkout_page.dart';
import '../../common/models/menu_item_adapter.dart';
import '../../common/models/category_adapter.dart';
import '../../common/models/option_groups_adapter.dart';
import '../../common/services/cache_service.dart';
import '../widgets/category_sidebar_widget.dart';
import '../widgets/ordered_product_list_widget.dart';
import '../widgets/menu_option_panel_widget.dart';
import '../widgets/order_action_bar_widget.dart';
import '../widgets/menu_grid_widget.dart';
import '../utils/order_selected.dart';
import '../utils/keyboard_event_handler.dart';
import '../keyboard_handlers/navigation_key_handler.dart';
import '../keyboard_handlers/digit_key_handler.dart';
import '../keyboard_handlers/enter_key_handler.dart';
import '../keyboard_handlers/quick_input_handler.dart';
import '../keyboard_handlers/duplicate_key_handler.dart';

class OrderPage extends StatefulWidget {
  final bool isAdminMode;

  const OrderPage({Key? key, this.isAdminMode = false}) : super(key: key);

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  List<MenuItem> products = [];
  List<MenuItem> allProducts = [];
  List<Category> categories = [];
  bool isLoading = true;
  String? error;
  Map<String, List<MenuOption>> optionGroups = {};
  List<SelectedProduct> orderedProducts = [];
  Map<String, String?> selectedOptions = {};
  MenuItem? selectedProduct;
  SelectedProduct? selectedOrderedProduct;
  late final AudioPlayer _audioPlayer;
  bool _isCardPressed = false;
  int? _pressedCardIndex;
  bool _isAdminMode = false;

  final _quickInputManager = QuickInputManager();
  OverlayEntry? _quickInputOverlay;
  late final KeyboardEventHandler _keyboardEventHandler;


  final TextEditingController _searchInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isAdminMode = widget.isAdminMode;
    _audioPlayer = AudioPlayer();
    loadData();
    loadOptions();
    _keyboardEventHandler = KeyboardEventHandler();
    _registerKeyboardHandlers();
  }

  @override
  void didUpdateWidget(covariant OrderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update admin mode state if it changes from parent widget
    if (widget.isAdminMode != oldWidget.isAdminMode) {
      setState(() {
        _isAdminMode = widget.isAdminMode;
      });
    }
  }

  void _registerKeyboardHandlers() {
    // 快捷输入处理（字母/Backspace/ESC/上下箭头等）- 必须在前面，优先处理
    _keyboardEventHandler.addHandler(
      quickInputHandler(
        quickInputManager: _quickInputManager,
        updateQuickInputOverlay: _updateQuickInputOverlay,
        setState: setState,
        getAllOptions: () => _allOptionsFlatList,
        getPreferOptions: () => orderedProducts.isNotEmpty,
      ),
    );

    // 方向键：切换已点菜品区 - 快捷输入无输入时才处理
    _keyboardEventHandler.addHandler(
      navigationKeyHandler(
        hasQuickInput: () => _quickInputManager.hasInput,
        onNavigate: _navigateOrderedProducts,
        playClickSound: _playClickSound,
      ),
    );

    // 数字键：设置数量
    _keyboardEventHandler.addHandler(
      digitKeyHandler(
        quickInputManager: _quickInputManager,
        orderedProducts: orderedProducts,
        setProductQuantity: _setProductQuantity,
        playClickSound: _playClickSound,
      ),
    );

    // Enter键：快捷输入选择 + 下单 - 必须在快捷输入处理器之后
    _keyboardEventHandler.addHandler(
      enterKeyHandler(
        quickInputManager: _quickInputManager,
        addProductIntelligently: _addProductIntelligently,
        addOptionToLastProduct: _addOptionToLastProduct,
        playClickSound: _playClickSound,
        clearQuickInput: _quickInputManager.clear,
        removeQuickInputOverlay: _removeQuickInputOverlay,
        refreshUI: () => setState(() {}),
        onOrder: () async {
          // 动态检查是否有菜品，而不是在注册时检查
          if (orderedProducts.isNotEmpty) {
            final result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (context) => CheckoutPage(
                  orderedProducts: orderedProducts,
                ),
              ),
            );
            // 如果返回 true，表示订单成功，清空购物车
            if (result == true) {
              setState(() {
                orderedProducts.clear();
                selectedOrderedProduct = null;
              });
            }
          }
        },
        hasOrderedProducts: () => orderedProducts.isNotEmpty,
      ),
    );

    // 操作键：Backspace (VOID) 和 Delete (CLEAR)
    _keyboardEventHandler.addHandler(
      actionKeyHandler(
        orderedProducts: orderedProducts,
        selectedOrderedProductGetter: () => selectedOrderedProduct,
        voidOrder: _voidOrder,
        clearOrder: _clearOrder,
        playClickSound: _playClickSound,
        setSelectedOrderedProduct: (product) => setState(() {
          selectedOrderedProduct = product;
        }),
        refreshUI: () => setState(() {}),
      ),
    );

    // Ctrl 键：复制选中的菜品
    _keyboardEventHandler.addHandler(
      duplicateKeyHandler(
        orderedProducts: orderedProducts,
        selectedOrderedProductGetter: () => selectedOrderedProduct,
        duplicateProduct: _duplicateOrderedProduct,
        playClickSound: _playClickSound,
        setSelectedOrderedProduct: (product) => setState(() {
          selectedOrderedProduct = product;
        }),
      ),
    );
    // 你可以继续添加更多 handler ...
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _searchInputController.dispose();
    super.dispose();
  }

  Future<void> _playClickSound() async {
    try {
      // 本地assets/audio/click.mp3
      await _audioPlayer.play(AssetSource('audio/click.mp3'));
    } catch (e) {
      // 忽略音效错误
    }
  }

  Future<void> loadData() async {
    final productsBox = await Hive.openBox<MenuItemAdapter>('productsBox');
    final categoriesBox = await Hive.openBox<CategoryAdapter>('categoriesBox');

    // 检查缓存是否为空（因为app重启时已经清空了缓存）
    if (productsBox.isEmpty || categoriesBox.isEmpty) {
      print('[DEBUG] 缓存为空，从API获取数据');
      await fetchData();
    } else {
      setState(() {
        allProducts = productsBox.values.map((e) => e.toMenuItem()).toList(); // 保存原始数据
        products = List<MenuItem>.from(allProducts); // 默认显示全部
        products.sort((a, b) {
          int cmp = a.sort.compareTo(b.sort);
          if (cmp != 0) return cmp;
          return a.code.compareTo(b.code);
        });
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
      print('[DEBUG] prodRes.data["data"]: ' + prodRes.data['data'].toString());
      print('[DEBUG] prodRes.data["data"] type: ' + prodRes.data['data'].runtimeType.toString());
      final prodDataRaw = prodRes.data['data'];
      List prodData;
      if (prodDataRaw is List) {
        prodData = prodDataRaw;
      } else {
        print('[ERROR] products/active 返回的 data 不是 List，实际类型: ' + prodDataRaw.runtimeType.toString());
        prodData = [];
      }
      final catData = catRes.data['data'] as List;
      setState(() {
        allProducts = prodData.where((e) => e is Map<String, dynamic>).map((e) => MenuItem.fromJson(e as Map<String, dynamic>)).toList(); // 保存原始数据
        products = List<MenuItem>.from(allProducts); // 默认显示全部
        products.sort((a, b) {
          int cmp = a.sort.compareTo(b.sort);
          if (cmp != 0) return cmp;
          return a.code.compareTo(b.code);
        });
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

  // 获取所有选项的平面列表（用于快捷搜索）
  List<MenuOption> get _allOptionsFlatList {
    final allOptions = <MenuOption>[];
    optionGroups.forEach((type, options) {
      allOptions.addAll(options);
    });
    return allOptions;
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
        options: [], // 不复制选项
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

  // VOID操作 - 删除当前已点菜品（优先删除选中项）
  void _voidOrder() {
    if (orderedProducts.isEmpty) return;

    setState(() {
      if (selectedOrderedProduct != null && orderedProducts.contains(selectedOrderedProduct)) {
        orderedProducts.remove(selectedOrderedProduct);
      } else {
        orderedProducts.removeLast();
      }
      // 删除后自动选中最后一个菜品
      if (orderedProducts.isNotEmpty) {
        selectedOrderedProduct = orderedProducts.last;
      } else {
        selectedOrderedProduct = null;
      }
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

  // 快捷输入相关方法
  void _updateQuickInputOverlay() {
    // 不调用 performSearch — 快捷输入框有内容时搜索结果已是最新的
    // performSearch 只在输入时调用（在 quickInputHandler 中），不在高亮改变时调用

    if (_quickInputManager.hasInput && _quickInputManager.hasResults) {
      _showQuickInputOverlay();
    } else if (!_quickInputManager.hasInput) {
      _removeQuickInputOverlay();
    } else if (_quickInputManager.hasInput && !_quickInputManager.hasResults) {
      _showQuickInputOverlay(); // 显示"无匹配结果"
    }
  }

  void _showQuickInputOverlay() {
    if (_quickInputOverlay != null) {
      _quickInputOverlay!.markNeedsBuild();
      return;
    }

    _quickInputOverlay = OverlayEntry(
      builder: (context) => QuickInputOverlay(
        input: _quickInputManager.input,
        searchResults: _quickInputManager.searchResults,
        highlightedIndex: _quickInputManager.highlightedIndex,
        isSearchingOptions: _quickInputManager.isSearchingOptions,
        onClose: () {
          _quickInputManager.clear();
          _removeQuickInputOverlay();
        },
        onItemTap: (item) {
          _addProductIntelligently(item);
          _playClickSound();
          _quickInputManager.clear();
          _removeQuickInputOverlay();
        },
        onOptionTap: (option) {
          if (orderedProducts.isNotEmpty) {
            _addOptionToLastProduct(option.type, option);
            _playClickSound();
          }
          _quickInputManager.clear();
          _removeQuickInputOverlay();
        },
      ),
    );

    Overlay.of(context)?.insert(_quickInputOverlay!);
  }

  void _removeQuickInputOverlay() {
    _quickInputOverlay?.remove();
    _quickInputOverlay = null;
  }

  // 设置菜品数量
  void _setProductQuantity(int quantity) {
    if (orderedProducts.isEmpty) return;

    setState(() {
      // 优先为选中的菜品设置数量，如果没有选中的菜品则为最后一个菜品设置数量
      SelectedProduct? targetProduct;

      if (selectedOrderedProduct != null) {
        targetProduct = selectedOrderedProduct;
      } else {
        targetProduct = orderedProducts.last;
      }

      if (quantity == 0) {
        // 如果数量为0，删除该菜品
        orderedProducts.remove(targetProduct);
        if (selectedOrderedProduct == targetProduct) {
          selectedOrderedProduct = null;
        }
      } else {
        // 设置新数量
        targetProduct!.quantity = quantity;
      }
    });
  }

  void _navigateOrderedProducts(LogicalKeyboardKey key) {
    if (orderedProducts.isEmpty) return;
    int currentIndex = selectedOrderedProduct != null
        ? orderedProducts.indexOf(selectedOrderedProduct!)
        : -1;
    int newIndex;
    switch (key) {
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowUp:
        newIndex = currentIndex <= 0 ? orderedProducts.length - 1 : currentIndex - 1;
        break;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowDown:
        newIndex = currentIndex >= orderedProducts.length - 1 || currentIndex == -1
            ? 0
            : currentIndex + 1;
        break;
      default:
        return;
    }
    setState(() {
      selectedOrderedProduct = orderedProducts[newIndex];
    });
  }

  // 拉单测试按钮回调
  Future<void> _syncRemoteOrders() async {
    try {
      final syncService = SyncService();
      await syncService.fetchAndSyncRemoteOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拉取并同步服务器订单完成')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拉单失败: \\${e.toString()}')),
        );
      }
    }
  }

  /// Show edit product dialog (Admin Mode)
  void _showEditProductDialog(MenuItem product) {
    final codeController = TextEditingController(text: product.code);
    final titleController = TextEditingController(text: product.title);
    final acronymController = TextEditingController(text: product.acronym);
    final priceController = TextEditingController(text: product.sellingPrice.toString());
    final stockController = TextEditingController(text: product.stock.toString());
    String? selectedCategoryId = product.categoryIds.isNotEmpty ? product.categoryIds.first.toString() : null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('编辑菜品'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                decoration: InputDecoration(
                  labelText: '菜品代码',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: '菜品名称',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: acronymController,
                decoration: InputDecoration(
                  labelText: '快捷键',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: priceController,
                decoration: InputDecoration(
                  labelText: '售价',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
              SizedBox(height: 12),
              TextField(
                controller: stockController,
                decoration: InputDecoration(
                  labelText: '库存',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 12),
              DropdownButton<String>(
                value: selectedCategoryId,
                isExpanded: true,
                hint: Text('选择分类'),
                items: categories.map((cat) {
                  return DropdownMenuItem(
                    value: cat.id.toString(),
                    child: Text(cat.title),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedCategoryId = value;
                  });
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newPrice = double.tryParse(priceController.text);
              final newStock = int.tryParse(stockController.text);

              if (newPrice == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('价格格式错误')),
                );
                return;
              }

              if (newStock == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('库存格式错误')),
                );
                return;
              }

              try {
                final api = ApiService();
                final List<int> categoryIds = [];
                if (selectedCategoryId != null && selectedCategoryId!.isNotEmpty) {
                  final catId = int.tryParse(selectedCategoryId!);
                  if (catId != null) {
                    categoryIds.add(catId);
                  }
                } else {
                  categoryIds.addAll(product.categoryIds);
                }

                final updateData = {
                  'code': codeController.text,
                  'title': titleController.text,
                  'acronym': acronymController.text.isEmpty ? null : acronymController.text,
                  'sellingPrice': newPrice,
                  'stock': newStock,
                  'categoryIds': categoryIds,
                };

                await api.put('products/${product.id.toString()}', data: updateData);

                Navigator.pop(context);

                // 清除缓存以确保获取最新数据
                await CacheService.clearMenuCaches();

                // 刷新菜品和分类数据
                await loadData();

                // 同时刷新选项数据以保持一致性
                await loadOptions();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('菜品已更新'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('更新失败: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('保存'),
          ),
        ],
      ),
    );
  }

  /// Show manage menu options dialog (Admin Mode)
  void _showManageOptionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('管理菜品选项'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...optionGroups.entries.map((entry) {
                  final groupType = entry.key;
                  final options = entry.value;
                  return ExpansionTile(
                    title: Text(groupType),
                    children: [
                      ...options.map((option) => ListTile(
                        title: Text(option.name),
                        subtitle: Text('额外费用: \$${option.extraCost.toStringAsFixed(2)}'),
                        trailing: PopupMenuButton(
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              child: Text('编辑'),
                              onTap: () {
                                Future.delayed(Duration(milliseconds: 100), () {
                                  _showEditOptionDialog(option, groupType);
                                });
                              },
                            ),
                            PopupMenuItem(
                              child: Text('删除'),
                              onTap: () {
                                Future.delayed(Duration(milliseconds: 100), () {
                                  _showDeleteOptionDialog(option, groupType);
                                });
                              },
                            ),
                          ],
                        ),
                      )).toList(),
                      ListTile(
                        leading: Icon(Icons.add),
                        title: Text('添加选项'),
                        onTap: () {
                          Navigator.pop(context);
                          _showAddOptionDialog(groupType);
                        },
                      ),
                    ],
                  );
                }).toList(),
                SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showAddOptionGroupDialog();
                  },
                  icon: Icon(Icons.add),
                  label: Text('新增选项组'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// Show add menu option dialog (Admin Mode)
  void _showAddOptionDialog(String groupType) {
    final nameController = TextEditingController();
    final costController = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('添加选项 - $groupType'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: '选项名称',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: costController,
              decoration: InputDecoration(
                labelText: '额外费用',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final cost = double.tryParse(costController.text) ?? 0;
              try {
                final api = ApiService();
                await api.post('attributes', data: {
                  'type': groupType,
                  'name': nameController.text,
                  'extra_cost': cost,
                });

                Navigator.pop(context);

                // 清除选项缓存以确保获取最新数据
                await CacheService.clearOptionsCache();
                await fetchOptions();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('选项已添加'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('添加失败: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('添加'),
          ),
        ],
      ),
    );
  }

  /// Show edit menu option dialog (Admin Mode)
  void _showEditOptionDialog(MenuOption option, String groupType) {
    final nameController = TextEditingController(text: option.name);
    final costController = TextEditingController(text: option.extraCost.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('编辑选项'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: '选项名称',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: costController,
              decoration: InputDecoration(
                labelText: '额外费用',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final cost = double.tryParse(costController.text) ?? 0;
              try {
                final api = ApiService();
                await api.put('attributes/${option.id}', data: {
                  'name': nameController.text,
                  'extra_cost': cost,
                });

                Navigator.pop(context);

                // 清除选项缓存以确保获取最新数据
                await CacheService.clearOptionsCache();
                await fetchOptions();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('选项已更新'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('更新失败: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('保存'),
          ),
        ],
      ),
    );
  }

  /// Show delete menu option dialog (Admin Mode)
  void _showDeleteOptionDialog(MenuOption option, String groupType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除选项'),
        content: Text('确认要删除选项 "${option.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final api = ApiService();
                await api.delete('attributes/${option.id}');

                Navigator.pop(context);

                // 清除选项缓存以确保获取最新数据
                await CacheService.clearOptionsCache();
                await fetchOptions();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('选项已删除'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('删除失败: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('删除'),
          ),
        ],
      ),
    );
  }

  /// Show add option group dialog (Admin Mode)
  void _showAddOptionGroupDialog() {
    final groupNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('新增选项组'),
        content: TextField(
          controller: groupNameController,
          decoration: InputDecoration(
            labelText: '选项组名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (groupNameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('请输入选项组名称')),
                );
                return;
              }

              try {
                // 选项组通过添加第一个选项来创建
                final api = ApiService();
                await api.post('attributes', data: {
                  'type': groupNameController.text,
                  'name': '新选项',
                  'extra_cost': 0,
                });

                Navigator.pop(context);

                // 清除选项缓存以确保获取最新数据
                await CacheService.clearOptionsCache();
                await fetchOptions();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('选项组已创建'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('创建失败: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('创建'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        // 统一处理快捷输入 - 既支持商品搜索也支持选项搜索
        _keyboardEventHandler.handle(event, allProducts);
        _searchInputController.text = _quickInputManager.input;
        _searchInputController.selection = TextSelection.fromPosition(TextPosition(offset: _searchInputController.text.length));
      },
      child: Scaffold(
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
                  OrderedProductListWidget(
                    orderedProducts: orderedProducts,
                    selectedOrderedProduct: selectedOrderedProduct,
                    onSelect: _selectOrderedProduct,
                    onDoubleTap: _duplicateOrderedProduct,
                    onIncrease: _increaseQuantity,
                    onDecrease: _decreaseQuantity,
                    minHeight: minHeight,
                    maxHeight: maxHeight,
                    baseItemHeight: baseItemHeight,
                    optionHeight: optionHeight,
                    crossAxisCount: crossAxisCount,
                    containerWidth: constraints.maxWidth - 32,
                    actualHeight: actualHeight,
                    maxCardHeight: maxCardHeight,
                  ),
                  // 主内容区域 - 使用计算出的固定高度
                  SizedBox(
                    height: availableHeight,
                    child: Row(
                      children: [
                        // 左侧：分类侧边栏 + 菜品选项区
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              Expanded(
                                flex: 1,
                                child: CategorySidebarWidget(
                                  categories: categories,
                                  onCategoryTap: (parent, [child]) {
                                    if (parent == null) {
                                      // “全部”按钮，显示所有菜品
                                      setState(() {
                                        products = List<MenuItem>.from(allProducts);
                                        products.sort((a, b) {
                                          int cmp = a.sort.compareTo(b.sort);
                                          if (cmp != 0) return cmp;
                                          return a.code.compareTo(b.code);
                                        });
                                      });
                                    } else {
                                      int selectedCategoryId = child?.id ?? parent.id;
                                      setState(() {
                                        products = allProducts.where((item) => item.categoryIds.contains(selectedCategoryId)).toList();
                                        products.sort((a, b) {
                                          int cmp = a.sort.compareTo(b.sort);
                                          if (cmp != 0) return cmp;
                                          return a.code.compareTo(b.code);
                                        });
                                      });
                                    }
                                  },
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: MenuOptionPanelWidget(
                                  optionGroups: optionGroups,
                                  orderedProducts: orderedProducts,
                                  onOptionTap: _showOptionDialog,
                                  isAdminMode: _isAdminMode,
                                  onManageOptions: _isAdminMode ? _showManageOptionsDialog : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 8,
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
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            _quickInputManager.input.isEmpty
                                              ? 'Type name or acronym to search ...'
                                              : _quickInputManager.input,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: _quickInputManager.input.isEmpty
                                                ? Colors.grey[600]
                                                : Colors.black,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // 菜品网格 - 使用所有剩余空间
                              Expanded(
                                child: MenuGridWidget(
                                  products: products,
                                  categories: categories, // 新增
                                  isLoading: isLoading,
                                  error: error,
                                  onTap: (item) async {
                                    final index = products.indexOf(item);
                                    setState(() {
                                      _isCardPressed = true;
                                      _pressedCardIndex = index;
                                    });
                                    // 150ms后自动恢复动画
                                    Future.delayed(Duration(milliseconds: 150), () {
                                      if (mounted) {
                                        setState(() {
                                          _isCardPressed = false;
                                          _pressedCardIndex = null;
                                        });
                                      }
                                    });
                                    // 声音和添加菜品异步进行
                                    _playClickSound();
                                    _addProductIntelligently(item);
                                  },
                                  calculateTitleFontSize: _calculateTitleFontSize,
                                  isCardPressed: _isCardPressed,
                                  pressedCardIndex: _pressedCardIndex,
                                  isAdminMode: _isAdminMode,
                                  onLongPress: _isAdminMode ? _showEditProductDialog : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 操作区域 - 优化显示效果
                  OrderActionBarWidget(
                    onVoidOrder: _voidOrder,
                    onClearOrder: _clearOrder,
                    onShowQuantitySelector: _showQuantitySelector,
                    onCustomAction: _customAction,
                    onOrder: orderedProducts.isEmpty
                        ? null
                        : () async {
                            final result = await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (context) => CheckoutPage(
                                  orderedProducts: orderedProducts,
                                ),
                              ),
                            );
                            // 如果返回 true，表示订单成功，清空购物车
                            if (result == true) {
                              setState(() {
                                orderedProducts.clear();
                                selectedOrderedProduct = null;
                              });
                            }
                          },
                    orderedCount: orderedProducts.length,
                    orderEnabled: orderedProducts.isNotEmpty,
                    onSyncRemoteOrders: _syncRemoteOrders, // 新增
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
