import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../common/models/menu_item.dart';
import '../../common/models/category.dart';
import '../../common/models/menu_option.dart';
import '../../common/services/sync_service.dart';
import '../keyboard_handlers/action_key_handler.dart';
import '../utils/quick_input_manager.dart';
import '../widgets/quick_input_overlay.dart';
import 'checkout_page.dart';
import '../widgets/category_sidebar_widget.dart';
import '../widgets/ordered_product_list_widget.dart';
import '../widgets/menu_option_panel_widget.dart';
import '../widgets/order_action_bar_widget.dart';
import '../widgets/menu_grid_widget.dart';
import '../utils/order_selected.dart';
import '../utils/keyboard_event_handler.dart';
import '../utils/ui_helper.dart';
import '../keyboard_handlers/navigation_key_handler.dart';
import '../keyboard_handlers/digit_key_handler.dart';
import '../keyboard_handlers/enter_key_handler.dart';
import '../keyboard_handlers/quick_input_handler.dart';
import '../keyboard_handlers/duplicate_key_handler.dart';
import '../../common/services/order_match_service.dart';
import '../../common/services/api_service.dart';
import '../services/menu_data_service.dart';
import '../services/order_match_manager.dart';

class OrderPage extends StatefulWidget {
  final bool isAdminMode;
  final void Function(
          OrderMatchResult? result, Future<void> Function()? requestCheck)?
      onOrderMatchStateChanged;

  const OrderPage({
    Key? key,
    this.isAdminMode = false,
    this.onOrderMatchStateChanged,
  }) : super(key: key);

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  // UI状态
  List<MenuItem> products = [];
  List<MenuItem> allProducts = [];
  List<Category> categories = [];
  bool isLoading = true;
  String? error;
  Map<String, List<MenuOption>> optionGroups = {};
  List<SelectedProduct> orderedProducts = [];
  SelectedProduct? selectedOrderedProduct;
  bool _isCardPressed = false;
  int? _pressedCardIndex;
  bool _isAdminMode = false;
  bool _isAllCategoriesSelected = true;

  // 快捷输入
  final _quickInputManager = QuickInputManager();
  OverlayEntry? _quickInputOverlay;
  late final KeyboardEventHandler _keyboardEventHandler;
  final TextEditingController _searchInputController = TextEditingController();
  final FocusNode _pageKeyboardFocusNode = FocusNode();
  final FocusNode _searchInputFocusNode = FocusNode();
  bool _keepSearchFocusOnNextBlur = false;

  // 服务和管理器
  final _menuDataService = MenuDataService();
  late final OrderMatchManager _orderMatchManager;
  late final UIHelper _uiHelper;

  /// 获取所有选项的平面列表（用于快捷搜索）
  List<MenuOption> get _allOptionsFlatList {
    final allOptions = <MenuOption>[];
    optionGroups.forEach((type, options) {
      allOptions.addAll(options);
    });
    return allOptions;
  }

  @override
  void initState() {
    super.initState();
    _isAdminMode = widget.isAdminMode;
    _searchInputFocusNode.addListener(_handleSearchInputFocusChange);
    _uiHelper = UIHelper();
    _orderMatchManager = OrderMatchManager();
    _initializeData();
    _keyboardEventHandler = KeyboardEventHandler();
    _registerKeyboardHandlers();
    _orderMatchManager.initialize(_onOrderMatchResultUpdated);
  }

  /// 初始化数据加载
  Future<void> _initializeData() async {
    final menuData = await _menuDataService.loadMenuData();
    final options = await _menuDataService.loadOptions();
    if (mounted) {
      setState(() {
        allProducts = menuData['allProducts'] ?? [];
        products = menuData['products'] ?? [];
        categories = menuData['categories'] ?? [];
        optionGroups = options;
        isLoading = false;
        error = menuData['error'];
      });
    }
  }

  /// 订单匹配结果更新回调
  void _onOrderMatchResultUpdated(OrderMatchResult result) {
    if (mounted) {
      setState(() {});
      widget.onOrderMatchStateChanged?.call(result, _performOrderMatchCheck);
    }
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
        clearQuickInput: () {
          _quickInputManager.clear();
          _syncSearchInputController();
        },
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
    _searchInputFocusNode.removeListener(_handleSearchInputFocusChange);
    _pageKeyboardFocusNode.dispose();
    _searchInputFocusNode.dispose();
    _searchInputController.dispose();
    _orderMatchManager.dispose();
    _removeQuickInputOverlay();
    super.dispose();
  }

  Future<void> _playClickSound() async {
    await _uiHelper.playClickSound();
  }

  void _selectOrderedProduct(SelectedProduct ordered) {
    setState(() {
      selectedOrderedProduct =
          selectedOrderedProduct == ordered ? null : ordered;
    });
  }

  void _duplicateOrderedProduct(SelectedProduct ordered) {
    final duplicatedProduct = SelectedProduct(
      product: ordered.product,
      options: [],
      quantity: ordered.quantity,
    );
    setState(() {
      orderedProducts.add(duplicatedProduct);
      selectedOrderedProduct = duplicatedProduct;
    });
  }

  void _increaseQuantity(SelectedProduct ordered) {
    setState(() {
      ordered.quantity++;
    });
  }

  void _decreaseQuantity(SelectedProduct ordered) {
    setState(() {
      if (ordered.quantity > 1) {
        ordered.quantity--;
      } else {
        orderedProducts.remove(ordered);
      }
    });
  }

  /// 智能添加菜品方法
  void _addProductIntelligently(MenuItem item) {
    setState(() {
      final existingProductIndex = orderedProducts.indexWhere(
        (product) => product.product.id == item.id && product.options.isEmpty,
      );

      if (existingProductIndex != -1) {
        orderedProducts[existingProductIndex].quantity++;
        selectedOrderedProduct = orderedProducts[existingProductIndex];
        return;
      }

      final newProduct = SelectedProduct(product: item, options: []);
      orderedProducts.add(newProduct);
      selectedOrderedProduct = newProduct;
    });
  }

  /// 为菜品添加选项
  void _addOptionToLastProduct(String type, MenuOption option) {
    SelectedProduct? targetProduct;

    if (selectedOrderedProduct != null) {
      targetProduct = selectedOrderedProduct;
    } else if (orderedProducts.isNotEmpty) {
      targetProduct = orderedProducts.last;
    } else {
      return;
    }

    setState(() {
      final existingOptionIndex = targetProduct!.options.indexWhere(
        (opt) => opt.type == type && opt.option.id == option.id,
      );

      if (existingOptionIndex == -1) {
        targetProduct.options.add(SelectedOption(type: type, option: option));
      }
    });
  }

  /// 动态计算标题字体大小
  double _calculateTitleFontSize(String title, double containerWidth) {
    return UIHelper.calculateTitleFontSize(title, containerWidth);
  }

  void _voidOrder() {
    if (orderedProducts.isEmpty) return;
    setState(() {
      if (selectedOrderedProduct != null &&
          orderedProducts.contains(selectedOrderedProduct)) {
        orderedProducts.remove(selectedOrderedProduct);
      } else {
        orderedProducts.removeLast();
      }
      if (orderedProducts.isNotEmpty) {
        selectedOrderedProduct = orderedProducts.last;
      } else {
        selectedOrderedProduct = null;
      }
    });
  }

  void _clearOrder() async {
    final confirmed = await DialogHelper.showClearOrderDialog(context);
    if (confirmed) {
      setState(() {
        orderedProducts.clear();
        selectedOrderedProduct = null;
      });
    }
  }

  void _showQuantitySelector() async {
    final quantity = await DialogHelper.showQuantitySelectorDialog(context);
    if (quantity != null) {
      setState(() {
        if (orderedProducts.isNotEmpty) {
          orderedProducts.last.quantity = quantity;
        }
      });
    }
  }

  void _customAction() {
    // TODO: 实现自定义按钮的功能
  }

  void _showOptionDialog(String type) {
    if (orderedProducts.isEmpty) {
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
                crossAxisCount: 5,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 1.8,
              ),
              itemCount: optionGroups[type]?.length ?? 0,
              itemBuilder: (context, index) {
                final option = optionGroups[type]![index];
                return Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    onTap: () {
                      _addOptionToLastProduct(type, option);
                      Navigator.pop(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            option.name,
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (option.extraCost > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Text(
                                '+\$${option.extraCost.toStringAsFixed(2)}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600),
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

  // 快捷输入相关方法
  void _syncSearchInputController() {
    final quickInput = _quickInputManager.input;
    if (_searchInputController.text == quickInput) return;
    _searchInputController.text = quickInput;
    _searchInputController.selection = TextSelection.fromPosition(
      TextPosition(offset: _searchInputController.text.length),
    );
  }

  void _updateQuickInputFromTextField(String value) {
    _quickInputManager.updateInput(
      value,
      allProducts,
      allOptions: _allOptionsFlatList,
      preferOptions: orderedProducts.isNotEmpty,
    );
    setState(_updateQuickInputOverlay);
  }

  Future<void> _confirmQuickInputSelection(
      {bool keepSearchFocus = false}) async {
    final selectedItem = _quickInputManager.getSelectedItem();
    if (selectedItem == null) return;

    if (selectedItem is MenuItem) {
      _addProductIntelligently(selectedItem);
      await _playClickSound();
    } else if (selectedItem is MenuOption && orderedProducts.isNotEmpty) {
      _addOptionToLastProduct(selectedItem.type, selectedItem);
      await _playClickSound();
    } else {
      return;
    }

    _quickInputManager.clear();
    _syncSearchInputController();
    _removeQuickInputOverlay();

    if (keepSearchFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchInputFocusNode.requestFocus();
        }
      });
    }
  }

  void _handleSearchInputFocusChange() {
    if (mounted) {
      setState(() {});
    }
    if (_searchInputFocusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _searchInputFocusNode.hasFocus) return;
      if (_keepSearchFocusOnNextBlur) {
        _keepSearchFocusOnNextBlur = false;
        _searchInputFocusNode.requestFocus();
        return;
      }
      _pageKeyboardFocusNode.requestFocus();
    });
  }

  bool _shouldHandleGlobalKeyEvent(KeyEvent event) {
    if (!_searchInputFocusNode.hasFocus) return true;

    final key = event.logicalKey;
    final isQuickInputControlKey = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.escape ||
        (key == LogicalKeyboardKey.enter && _quickInputManager.hasInput);

    return isQuickInputControlKey;
  }

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
          _syncSearchInputController();
          _removeQuickInputOverlay();
        },
        onItemTap: (item) {
          _addProductIntelligently(item);
          _playClickSound();
          _quickInputManager.clear();
          _syncSearchInputController();
          _removeQuickInputOverlay();
        },
        onOptionTap: (option) {
          if (orderedProducts.isNotEmpty) {
            _addOptionToLastProduct(option.type, option);
            _playClickSound();
          }
          _quickInputManager.clear();
          _syncSearchInputController();
          _removeQuickInputOverlay();
        },
      ),
    );

    Overlay.of(context).insert(_quickInputOverlay!);
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
        newIndex =
            currentIndex <= 0 ? orderedProducts.length - 1 : currentIndex - 1;
        break;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowDown:
        newIndex =
            currentIndex >= orderedProducts.length - 1 || currentIndex == -1
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
          SnackBar(content: Text('拉单失败: \${e.toString()}')),
        );
      }
    }
  }

  /// Show edit product dialog (Admin Mode)
  void _showEditProductDialog(MenuItem product) {
    final codeController = TextEditingController(text: product.code);
    final titleController = TextEditingController(text: product.title);
    final acronymController = TextEditingController(text: product.acronym);
    final priceController =
        TextEditingController(text: product.sellingPrice.toString());
    final stockController =
        TextEditingController(text: product.stock.toString());
    String? selectedCategoryId = product.categoryIds.isNotEmpty
        ? product.categoryIds.first.toString()
        : null;

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
                final List<int> categoryIds = [];
                if (selectedCategoryId != null &&
                    selectedCategoryId!.isNotEmpty) {
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
                  'acronym': acronymController.text.isEmpty
                      ? null
                      : acronymController.text,
                  'sellingPrice': newPrice,
                  'stock': newStock,
                  'categoryIds': categoryIds,
                };

                final api = ApiService();
                await api.put('products/${product.id.toString()}',
                    data: updateData);

                Navigator.pop(context);

                // 刷新菜品数据
                final menuData = await _menuDataService.loadMenuData();
                if (mounted) {
                  setState(() {
                    allProducts = menuData['allProducts'] ?? [];
                    products = menuData['products'] ?? [];
                    categories = menuData['categories'] ?? [];
                  });
                }

                UIHelper.showSnackBar(context, '菜品已更新',
                    backgroundColor: Colors.green);
              } catch (e) {
                UIHelper.showSnackBar(context, '更新失败: $e',
                    backgroundColor: Colors.red);
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
                      ...options
                          .map((option) => ListTile(
                                title: Text(option.name),
                                subtitle: Text(
                                    '额外费用: \$${option.extraCost.toStringAsFixed(2)}'),
                                trailing: PopupMenuButton(
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      child: Text('编辑'),
                                      onTap: () {
                                        Future.delayed(
                                            Duration(milliseconds: 100), () {
                                          _showEditOptionDialog(
                                              option, groupType);
                                        });
                                      },
                                    ),
                                    PopupMenuItem(
                                      child: Text('删除'),
                                      onTap: () {
                                        Future.delayed(
                                            Duration(milliseconds: 100), () {
                                          _showDeleteOptionDialog(
                                              option, groupType);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
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

                // 刷新选项数据
                final options = await _menuDataService.loadOptions();
                if (mounted) {
                  setState(() {
                    optionGroups = options;
                  });
                }

                UIHelper.showSnackBar(context, '选项已添加',
                    backgroundColor: Colors.green);
              } catch (e) {
                UIHelper.showSnackBar(context, '添加失败: $e',
                    backgroundColor: Colors.red);
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
    final costController =
        TextEditingController(text: option.extraCost.toString());

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

                // 刷新选项数据
                final options = await _menuDataService.loadOptions();
                if (mounted) {
                  setState(() {
                    optionGroups = options;
                  });
                }

                UIHelper.showSnackBar(context, '选项已更新',
                    backgroundColor: Colors.green);
              } catch (e) {
                UIHelper.showSnackBar(context, '更新失败: $e',
                    backgroundColor: Colors.red);
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

                // 刷新选项数据
                final options = await _menuDataService.loadOptions();
                if (mounted) {
                  setState(() {
                    optionGroups = options;
                  });
                }

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

                // 刷新选项数据
                final options = await _menuDataService.loadOptions();
                if (mounted) {
                  setState(() {
                    optionGroups = options;
                  });
                }

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

  Future<void> _performOrderMatchCheck() async {
    await _orderMatchManager.performCheck(_onOrderMatchResultUpdated);
  }

  bool _menuItemMatchesCategory(
    MenuItem item,
    Set<String> categoryTitles,
    Map<int, Category> categoryById,
  ) {
    for (final categoryId in item.categoryIds) {
      final visited = <int>{};
      int? currentId = categoryId;
      while (currentId != null && !visited.contains(currentId)) {
        visited.add(currentId);
        final category = categoryById[currentId];
        if (category == null) break;
        if (categoryTitles.contains(category.title.trim().toLowerCase())) {
          return true;
        }
        currentId = category.parentId;
      }
    }
    return false;
  }

  bool _menuItemIsFryRice(MenuItem item, Map<int, Category> categoryById) {
    for (final categoryId in item.categoryIds) {
      final visited = <int>{};
      int? currentId = categoryId;
      while (currentId != null && !visited.contains(currentId)) {
        visited.add(currentId);
        final category = categoryById[currentId];
        if (category == null) break;
        final normalized = category.title.trim().toLowerCase();
        if (normalized == 'fry rice' ||
            normalized == 'fried rice' ||
            normalized.contains('fry rice') ||
            normalized.contains('fried rice')) {
          return true;
        }
        currentId = category.parentId;
      }
    }
    return false;
  }

  List<MenuItem?> _arrangeMenuProductsByColumns(List<MenuItem> sourceProducts) {
    if (sourceProducts.isEmpty) return <MenuItem?>[];

    final sortedProducts = List<MenuItem>.from(sourceProducts)
      ..sort((a, b) {
        final sortCompare = a.sort.compareTo(b.sort);
        if (sortCompare != 0) return sortCompare;
        return a.code.compareTo(b.code);
      });

    final categoryById = <int, Category>{
      for (final category in categories) category.id: category,
    };

    final mealProducts = <MenuItem>[];
    final soupProducts = <MenuItem>[];
    final drinkAndSnackProducts = <MenuItem>[];

    for (final item in sortedProducts) {
      final isSoup = _menuItemMatchesCategory(item, {'soup'}, categoryById);
      final isDrinkOrSnack = _menuItemMatchesCategory(
        item,
        {'drink', 'snack'},
        categoryById,
      );
      final isMeal = _menuItemMatchesCategory(
        item,
        {'meal', 'noodle', 'fry rice'},
        categoryById,
      );

      if (isSoup) {
        soupProducts.add(item);
      } else if (isDrinkOrSnack) {
        drinkAndSnackProducts.add(item);
      } else if (isMeal) {
        mealProducts.add(item);
      } else {
        mealProducts.add(item);
      }
    }

    final fryRiceMeals = <MenuItem>[];
    final otherMeals = <MenuItem>[];
    for (final meal in mealProducts) {
      if (_menuItemIsFryRice(meal, categoryById)) {
        fryRiceMeals.add(meal);
      } else {
        otherMeals.add(meal);
      }
    }
    final prioritizedMealProducts = <MenuItem>[
      ...fryRiceMeals,
      ...otherMeals,
    ];

    final mealColumn1 = <MenuItem>[];
    final mealColumn2 = <MenuItem>[];
    final soupOverflowMeals = <MenuItem>[];

    for (final meal in prioritizedMealProducts) {
      if (mealColumn1.length <= mealColumn2.length) {
        mealColumn1.add(meal);
      } else {
        mealColumn2.add(meal);
      }
    }

    while (mealColumn1.isNotEmpty || mealColumn2.isNotEmpty) {
      final currentHeights = <int>[
        mealColumn1.length,
        mealColumn2.length,
        soupProducts.length + soupOverflowMeals.length,
      ];
      final currentSpread = currentHeights.reduce((a, b) => a > b ? a : b) -
          currentHeights.reduce((a, b) => a < b ? a : b);

      var moveFromColumn1 = mealColumn1.length >= mealColumn2.length;
      if ((moveFromColumn1 && mealColumn1.isEmpty) ||
          (!moveFromColumn1 && mealColumn2.isEmpty)) {
        moveFromColumn1 = !moveFromColumn1;
      }
      final sourceColumn = moveFromColumn1 ? mealColumn1 : mealColumn2;
      if (sourceColumn.isEmpty) break;

      final movedItem = sourceColumn.removeLast();
      final nextMeal1Height = mealColumn1.length;
      final nextMeal2Height = mealColumn2.length;
      final nextSoupHeight = soupProducts.length + soupOverflowMeals.length + 1;
      final nextHeights = <int>[
        nextMeal1Height,
        nextMeal2Height,
        nextSoupHeight,
      ];
      final nextSpread = nextHeights.reduce((a, b) => a > b ? a : b) -
          nextHeights.reduce((a, b) => a < b ? a : b);

      if (nextSpread > currentSpread) {
        sourceColumn.add(movedItem);
        break;
      }

      soupOverflowMeals.add(movedItem);
    }

    final soupColumn = <MenuItem>[
      ...soupProducts,
      ...soupOverflowMeals,
    ];

    final columns = <List<MenuItem>>[
      mealColumn1,
      mealColumn2,
      soupColumn,
      drinkAndSnackProducts,
    ];

    final maxRows = columns.fold<int>(
      0,
      (maxRows, column) => column.length > maxRows ? column.length : maxRows,
    );

    final arranged = <MenuItem?>[];
    for (var row = 0; row < maxRows; row++) {
      for (final column in columns) {
        arranged.add(row < column.length ? column[row] : null);
      }
    }

    return arranged;
  }

  // ...existing code...

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _pageKeyboardFocusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (!_shouldHandleGlobalKeyEvent(event)) return;
        final keepSearchFocusedAfterEnter = event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            _searchInputFocusNode.hasFocus &&
            _quickInputManager.hasInput;
        if (keepSearchFocusedAfterEnter) {
          _keepSearchFocusOnNextBlur = true;
        }
        // 统一处理快捷输入 - 既支持商品搜索也支持选项搜索
        _keyboardEventHandler.handle(event, allProducts);
        _syncSearchInputController();
        if (keepSearchFocusedAfterEnter) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _searchInputFocusNode.requestFocus();
            }
          });
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double searchBarHeight = 40.0;
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
                double cardHeight = baseItemHeight +
                    (product.options.length * optionHeight) +
                    16; // 增加padding
                if (cardHeight > maxCardHeight) maxCardHeight = cardHeight;
              }

              final int rowCount =
                  (orderedProducts.length / crossAxisCount).ceil();
              final double calculatedHeight =
                  (rowCount * maxCardHeight) + 32; // 增加容器padding
              final double actualHeight =
                  calculatedHeight.clamp(minHeight, maxHeight);

              // 为Web环境优化布局计算
              final screenHeight = constraints.maxHeight;
              final topSectionHeight = actualHeight; // 动态已点菜品区域
              final bottomButtonHeight = 60.0;
              final availableHeight =
                  screenHeight - topSectionHeight - bottomButtonHeight;

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
                                flex: 6,
                                child: CategorySidebarWidget(
                                  categories: categories,
                                  onCategoryTap: (category) {
                                    if (category == null) {
                                      // “全部”按钮，显示所有菜品
                                      setState(() {
                                        _isAllCategoriesSelected = true;
                                        products =
                                            List<MenuItem>.from(allProducts);
                                        products.sort((a, b) {
                                          int cmp = a.sort.compareTo(b.sort);
                                          if (cmp != 0) return cmp;
                                          return a.code.compareTo(b.code);
                                        });
                                      });
                                    } else {
                                      final selectedCategoryId = category.id;
                                      setState(() {
                                        _isAllCategoriesSelected = false;
                                        products = allProducts
                                            .where((item) => item.categoryIds
                                                .contains(selectedCategoryId))
                                            .toList();
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
                                flex: 4,
                                child: MenuOptionPanelWidget(
                                  optionGroups: optionGroups,
                                  orderedProducts: orderedProducts,
                                  onOptionTap: _showOptionDialog,
                                  isAdminMode: _isAdminMode,
                                  onManageOptions: _isAdminMode
                                      ? _showManageOptionsDialog
                                      : null,
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
                                height: searchBarHeight,
                                color: Colors.grey[100],
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0),
                                  child: Row(
                                    children: [
                                      Icon(Icons.search, size: 20),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          focusNode: _searchInputFocusNode,
                                          controller: _searchInputController,
                                          onChanged:
                                              _updateQuickInputFromTextField,
                                          onTapOutside: (_) {
                                            _keepSearchFocusOnNextBlur = false;
                                            _searchInputFocusNode.unfocus();
                                            _pageKeyboardFocusNode
                                                .requestFocus();
                                          },
                                          decoration: InputDecoration(
                                            border: InputBorder.none,
                                            isCollapsed: true,
                                            hintText: 'Type to quick search.',
                                            hintStyle: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // 菜品网格 - 使用所有剩余空间
                              Expanded(
                                child: Builder(
                                  builder: (_) {
                                    final arrangedMenuProducts =
                                        _isAllCategoriesSelected
                                            ? _arrangeMenuProductsByColumns(
                                                products)
                                            : products
                                                .map<MenuItem?>((item) => item)
                                                .toList();
                                    return MenuGridWidget(
                                      products: arrangedMenuProducts,
                                      categories: categories, // 新增
                                      isLoading: isLoading,
                                      error: error,
                                      onTap: (item) async {
                                        final index =
                                            arrangedMenuProducts.indexOf(item);
                                        setState(() {
                                          _isCardPressed = true;
                                          _pressedCardIndex = index;
                                        });
                                        // 150ms后自动恢复动画
                                        Future.delayed(
                                            Duration(milliseconds: 150), () {
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
                                      calculateTitleFontSize:
                                          _calculateTitleFontSize,
                                      isCardPressed: _isCardPressed,
                                      pressedCardIndex: _pressedCardIndex,
                                      isAdminMode: _isAdminMode,
                                      onLongPress: _isAdminMode
                                          ? _showEditProductDialog
                                          : null,
                                    );
                                  },
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
                            final result =
                                await Navigator.of(context).push<bool>(
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
                    showQuickSelectButton: true,
                    isQuickSearchActive: _searchInputFocusNode.hasFocus,
                    onSelectQuickInput: () async {
                      if (_quickInputManager.hasInput) {
                        _keepSearchFocusOnNextBlur = true;
                        await _confirmQuickInputSelection(
                            keepSearchFocus: true);
                        return;
                      }
                      _searchInputFocusNode.requestFocus();
                    },
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
