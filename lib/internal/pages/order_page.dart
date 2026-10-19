import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../common/services/language_service.dart';
import '../../common/models/menu_item.dart';
import '../../common/models/category.dart';
import '../../common/models/menu_option.dart';
import '../../common/models/order_model.dart';
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
import '../utils/online_order_mapper.dart';
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
import '../widgets/online_order_selection_dialog.dart';
import '../../common/models/dining_table.dart';
import '../../common/services/dining_table_service.dart';
import '../../common/services/print_service.dart';
import '../utils/dining_table_mapper.dart';
import '../widgets/dining_table_selection_dialog.dart';

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
  OrderModel? _selectedOnlineOrder;
  List<SelectedProduct> _selectedOnlineOrderOriginalProducts = [];
  SelectedProduct? selectedOrderedProduct;
  bool _isCardPressed = false;
  int? _pressedCardIndex;
  bool _isAdminMode = false;

  // 桌台状态
  DiningTable? _selectedTable;
  bool _isTableOrderExisting = false;
  Map<String, dynamic>? _selectedTableActiveOrder;
  int? _selectedTableGuestCount;
  int? _selectedReservationId;
  List<SelectedProduct> _originalTableProducts = [];

  bool get _hasSelectedTable => _selectedTable != null;

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

  bool get _hasSelectedOnlineOrder => _selectedOnlineOrder != null;

  void _clearOnlineOrderSelection() {
    _selectedOnlineOrder = null;
    _selectedOnlineOrderOriginalProducts = [];
  }

  void _applyOnlineOrderToCart(OrderModel order) {
    final snapshot =
        OnlineOrderMapper.buildSelectedProducts(order, allProducts);
    if (snapshot.isEmpty) {
      return;
    }

    setState(() {
      orderedProducts.addAll(snapshot);
      selectedOrderedProduct = orderedProducts.last;
      _selectedOnlineOrder = order;
      _selectedOnlineOrderOriginalProducts =
          OnlineOrderMapper.cloneSelectedProducts(snapshot);
    });
  }

  Future<void> _showOnlineOrderPicker() async {
    final selectedOrder = await OnlineOrderSelectionDialog.show(context);
    if (selectedOrder == null || !mounted) return;
    _applyOnlineOrderToCart(selectedOrder);
  }

  void _clearTableSelection() {
    _selectedTable = null;
    _isTableOrderExisting = false;
    _selectedTableActiveOrder = null;
    _selectedTableGuestCount = null;
    _selectedReservationId = null;
    _originalTableProducts.clear();
  }

  Future<void> _showTablePicker() async {
    final result = await DiningTableSelectionDialog.show(context);
    if (result == null || !mounted) return;

    setState(() {
      _selectedTable = result.table;
      _isTableOrderExisting = result.isExistingOrder;
      _selectedTableActiveOrder = result.activeOrder;
      _selectedTableGuestCount = result.guestCount;
      _selectedReservationId = result.reservationId;

      orderedProducts.clear();
      if (result.rawItems != null && result.rawItems!.isNotEmpty) {
        final tableProducts =
            DiningTableMapper.buildSelectedProductsFromTableItems(
          result.rawItems!,
          allProducts,
        );
        orderedProducts.addAll(tableProducts);
        if (orderedProducts.isNotEmpty) {
          selectedOrderedProduct = orderedProducts.last;
        }
      }
      _originalTableProducts =
          OnlineOrderMapper.cloneSelectedProducts(orderedProducts);
    });

    if (result.action == DiningTableAction.checkout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openCheckoutPage();
        }
      });
    }
  }

  Widget _buildSelectedTableBanner() {
    final table = _selectedTable;
    if (table == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade400, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(Icons.table_restaurant, color: Colors.amber[900]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '已关联桌台：${table.name}${table.area != null && table.area!.isNotEmpty ? ' (${table.area})' : ''}  ${_isTableOrderExisting ? "[堂食坐台单]" : "[开台点餐]"}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.amber[900],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          OutlinedButton(
            onPressed: _showTablePicker,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('换桌', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: Colors.amber[900],
            onPressed: () {
              setState(() {
                _clearTableSelection();
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleOrderAction() async {
    if (orderedProducts.isEmpty &&
        !_hasSelectedOnlineOrder &&
        !_hasSelectedTable) {
      await _showOnlineOrderPicker();
      return;
    }

    if (_hasSelectedTable) {
      if (orderedProducts.isEmpty) {
        UIHelper.showSnackBar(context, '请先选择菜品再操作', backgroundColor: Colors.orange);
        return;
      }

      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheetCtx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '桌台：${_selectedTable!.name} (${_selectedTable!.area ?? ""})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text('已选 ${orderedProducts.length} 个菜品',
                    style: TextStyle(color: Colors.grey[700])),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('UPDATE / 更新暂存'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[800],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      Navigator.pop(sheetCtx);
                      await _saveLocalTableOrder();
                    },
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.shopping_cart),
                    label: const Text('CHECKOUT / 结账'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      Navigator.pop(sheetCtx);
                      await _openCheckoutPage();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    await _openCheckoutPage();
  }

  /// 计算相比原始暂存菜品，新增/加数量的菜品列表
  List<SelectedProduct> _calculateAddedProducts(
    List<SelectedProduct> currentProducts,
    List<SelectedProduct> originalProducts,
  ) {
    final List<SelectedProduct> added = [];

    for (var current in currentProducts) {
      final originalMatches = originalProducts.where((orig) {
        if (orig.product.id != current.product.id) return false;
        if (orig.options.length != current.options.length) return false;
        for (int i = 0; i < current.options.length; i++) {
          final cOpt = current.options[i];
          final oOpt = orig.options[i];
          if (cOpt.type != oOpt.type || cOpt.option.id != oOpt.option.id) {
            return false;
          }
        }
        return true;
      }).toList();

      if (originalMatches.isEmpty) {
        added.add(current);
      } else {
        final originalQty =
            originalMatches.fold<int>(0, (sum, item) => sum + item.quantity);
        if (current.quantity > originalQty) {
          final diffQty = current.quantity - originalQty;
          added.add(SelectedProduct(
            product: current.product,
            options: current.options,
            quantity: diffQty,
          ));
        }
      }
    }

    return added;
  }

  Future<void> _saveLocalTableOrder() async {
    if (_selectedTable == null || orderedProducts.isEmpty) return;

    final tableName = _selectedTable!.name;
    final apiItems = DiningTableMapper.toTableApiItems(orderedProducts);
    final tableService = DiningTableService();

    // 1. 追踪计算新增/加量的菜品
    final addedProducts = _calculateAddedProducts(
      orderedProducts,
      _originalTableProducts,
    );

    // 2. 更新本地 SQLite 数据库中该桌台/预约单的暂存菜品
    await tableService.saveLocalTableItems(
      _selectedTable!.id,
      apiItems,
      reservationId: _selectedReservationId,
    );

    // 3. 将新增/加量的菜品发送到 PrintService 进行后厨打单
    if (addedProducts.isNotEmpty) {
      await PrintService().printKitchenTicketForAddedItems(
        tableName: tableName,
        addedProducts: addedProducts,
      );
    }

    if (!mounted) return;

    final addedCount = addedProducts.fold<int>(0, (s, p) => s + p.quantity);
    final msg = addedCount > 0
        ? '桌台 $tableName 菜品已更新，新增 $addedCount 项菜品已发送后厨打单！'
        : '桌台 $tableName 暂存菜品已更新！';

    UIHelper.showToast(
      context,
      msg,
      backgroundColor: Colors.green,
    );

    setState(() {
      orderedProducts.clear();
      selectedOrderedProduct = null;
      _clearTableSelection();
    });
  }

  Future<void> _openCheckoutPage() async {
    if (orderedProducts.isEmpty && !_hasSelectedOnlineOrder && !_hasSelectedTable) {
      await _handleOrderAction();
      return;
    }

    final tableToClear = _selectedTable;
    final resIdToClear = _selectedReservationId;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => CheckoutPage(
          orderedProducts: orderedProducts,
          onlineOrder: _selectedOnlineOrder,
          originalOnlineOrderedProducts: _selectedOnlineOrderOriginalProducts,
          diningTable: _selectedTable,
          reservationId: _selectedReservationId,
        ),
      ),
    );

    if (result == true) {
      if (tableToClear != null) {
        await DiningTableService().clearLocalTableItems(
          tableToClear.id,
          reservationId: resIdToClear,
        );
      }

      setState(() {
        orderedProducts.clear();
        selectedOrderedProduct = null;
        _clearOnlineOrderSelection();
        _clearTableSelection();
      });
    }
  }

  Widget _buildSelectedOnlineOrderBanner() {
    final order = _selectedOnlineOrder;
    if (order == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_done, color: Colors.orange[700]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '已添加在线订单：${order.orderNo}${order.remoteOrderNumber != null ? ' / ${order.remoteOrderNumber}' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '${_selectedOnlineOrderOriginalProducts.length} items',
            style: TextStyle(color: Colors.orange[800]),
          ),
        ],
      ),
    );
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
        onOrder: _openCheckoutPage,
        hasOrderedProducts: () =>
            orderedProducts.isNotEmpty || _hasSelectedOnlineOrder,
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
          if (orderedProducts.isEmpty) {
            _clearOnlineOrderSelection();
          }
        }),
        refreshUI: () => setState(() {
          if (orderedProducts.isEmpty) {
            selectedOrderedProduct = null;
            _clearOnlineOrderSelection();
          }
        }),
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
      if (orderedProducts.isEmpty) {
        selectedOrderedProduct = null;
        _clearOnlineOrderSelection();
      }
    });
  }

  /// 智能添加菜品方法
  void _addProductIntelligently(MenuItem item) {
    if (item.isSoldOut) {
      UIHelper.showSnackBar(
        context,
        '${item.title} 已沽清 (Sold Out)',
        backgroundColor: Colors.deepOrange,
      );
      return;
    }
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
        _clearOnlineOrderSelection();
      }
    });
  }

  void _clearOrder() {
    if (orderedProducts.isEmpty && !_hasSelectedOnlineOrder) return;
    setState(() {
      orderedProducts.clear();
      selectedOrderedProduct = null;
      _clearOnlineOrderSelection();
    });
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
      if (orderedProducts.isEmpty) {
        _clearOnlineOrderSelection();
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



  /// 沽清设置 API 调用
  Future<void> _setProductSoldOut(MenuItem product, String type) async {
    try {
      final api = ApiService();
      await api.post('products/${product.id}/sold-out', data: {
        'type': type,
      });

      // 刷新菜品数据
      final menuData = await _menuDataService.loadMenuData();
      if (mounted) {
        setState(() {
          allProducts = menuData['allProducts'] ?? [];
          products = menuData['products'] ?? [];
          categories = menuData['categories'] ?? [];
        });
      }

      String msg;
      switch (type) {
        case 'available':
          msg = '${product.title} 已恢复在售';
          break;
        case '4h':
          msg = '${product.title} 已设置沽清 4 小时';
          break;
        case 'today':
          msg = '${product.title} 已设置今日沽清';
          break;
        case 'this_week':
          msg = '${product.title} 已设置本周沽清';
          break;
        case 'indefinite':
          msg = '${product.title} 已设置永久沽清';
          break;
        default:
          msg = '沽清状态已更新';
      }

      if (!mounted) return;
      UIHelper.showSnackBar(context, msg, backgroundColor: Colors.green);
    } catch (e) {
      if (!mounted) return;
      UIHelper.showSnackBar(context, '设置沽清失败: $e', backgroundColor: Colors.red);
    }
  }

  /// 显示沽清设置对话框
  void _showSoldOutDialog(MenuItem product) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.no_meals, color: Colors.orange[800]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${product.title} - 沽清设置',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: product.isSoldOut ? Colors.red[50] : Colors.green[50],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: product.isSoldOut ? Colors.red[200]! : Colors.green[200]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    product.isSoldOut ? Icons.cancel : Icons.check_circle,
                    color: product.isSoldOut ? Colors.red : Colors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '当前状态：${product.isSoldOut ? "已沽清 (Sold Out)" : "正常在售"}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: product.isSoldOut ? Colors.red[800] : Colors.green[800],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('请选择沽清时长或恢复在售：',
                style: TextStyle(fontSize: 14, color: Colors.black87)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildSoldOutOptionTile(
                  dialogContext,
                  product,
                  type: 'available',
                  label: '恢复在售',
                  icon: Icons.refresh,
                  color: Colors.green,
                ),
                _buildSoldOutOptionTile(
                  dialogContext,
                  product,
                  type: '4h',
                  label: '沽清 4 小时',
                  icon: Icons.timer,
                  color: Colors.orange,
                ),
                _buildSoldOutOptionTile(
                  dialogContext,
                  product,
                  type: 'today',
                  label: '今日沽清',
                  icon: Icons.today,
                  color: Colors.deepOrange,
                ),
                _buildSoldOutOptionTile(
                  dialogContext,
                  product,
                  type: 'this_week',
                  label: '本周沽清',
                  icon: Icons.date_range,
                  color: Colors.brown,
                ),
                _buildSoldOutOptionTile(
                  dialogContext,
                  product,
                  type: 'indefinite',
                  label: '永久沽清',
                  icon: Icons.block,
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _buildSoldOutOptionTile(
    BuildContext dialogContext,
    MenuItem product, {
    required String type,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pop(dialogContext);
        _setProductSoldOut(product, type);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
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
              // 沽清快捷操作条
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: product.isSoldOut ? Colors.red[50] : Colors.amber[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: product.isSoldOut ? Colors.red[200]! : Colors.amber[300]!,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      product.isSoldOut ? Icons.no_meals : Icons.check_circle,
                      color: product.isSoldOut ? Colors.red : Colors.green[700],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        product.isSoldOut ? '当前状态：已沽清 (Sold Out)' : '当前状态：正常在售',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: product.isSoldOut ? Colors.red[800] : Colors.green[800],
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showSoldOutDialog(product);
                      },
                      icon: const Icon(Icons.edit_attributes, size: 16),
                      label: const Text('设置沽清', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
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
                UIHelper.showSnackBar(context, '价格格式错误', backgroundColor: Colors.red);
                return;
              }

              if (newStock == null) {
                UIHelper.showSnackBar(context, '库存格式错误', backgroundColor: Colors.red);
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

                UIHelper.showSnackBar(context, '选项已删除', backgroundColor: Colors.green);
              } catch (e) {
                UIHelper.showSnackBar(context, '删除失败: $e', backgroundColor: Colors.red);
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
                UIHelper.showSnackBar(context, '请输入选项组名称', backgroundColor: Colors.orange);
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

                UIHelper.showSnackBar(context, '选项组已创建', backgroundColor: Colors.green);
              } catch (e) {
                UIHelper.showSnackBar(context, '创建失败: $e', backgroundColor: Colors.red);
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

              return Column(
                children: [
                  // 桌台 & 在线订单提示 Banner
                  _buildSelectedTableBanner(),
                  _buildSelectedOnlineOrderBanner(),
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
                  // 主内容区域 - 自动填充所有剩余可用高度
                  Expanded(
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
                                          style: const TextStyle(
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
                                child: MenuGridWidget(
                                  products: products,
                                  categories: categories,
                                  isLoading: isLoading,
                                  error: error,
                                  onTap: (item) async {
                                    final index = products.indexOf(item);
                                    setState(() {
                                      _isCardPressed = true;
                                      _pressedCardIndex = index;
                                    });
                                    Future.delayed(
                                        const Duration(milliseconds: 150), () {
                                      if (mounted) {
                                        setState(() {
                                          _isCardPressed = false;
                                          _pressedCardIndex = null;
                                        });
                                      }
                                    });
                                    _playClickSound();
                                    _addProductIntelligently(item);
                                  },
                                  calculateTitleFontSize:
                                      _calculateTitleFontSize,
                                  isCardPressed: _isCardPressed,
                                  pressedCardIndex: _pressedCardIndex,
                                  isAdminMode: _isAdminMode,
                                  onLongPress: (item) {
                                    if (_isAdminMode) {
                                      _showEditProductDialog(item);
                                    } else {
                                      _showSoldOutDialog(item);
                                    }
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
                    onOrder: _handleOrderAction,
                    onSelectTable: _showTablePicker,
                    selectedTableName: _selectedTable?.name,
                    orderedCount: orderedProducts.length,
                    orderEnabled: true,
                    showQuickSelectButton: true,
                    isQuickSearchActive: _searchInputFocusNode.hasFocus,
                    orderLabel: _hasSelectedTable
                        ? 'confirm'.tr.toUpperCase()
                        : (orderedProducts.isEmpty && !_hasSelectedOnlineOrder
                            ? 'ADD ORDER'
                            : 'ORDER'),
                    orderIcon: _hasSelectedTable
                        ? Icons.check_circle_outline
                        : (orderedProducts.isEmpty && !_hasSelectedOnlineOrder
                            ? Icons.playlist_add
                            : Icons.shopping_cart),
                    orderColor: _hasSelectedTable
                        ? Colors.amber[800]!
                        : (orderedProducts.isEmpty && !_hasSelectedOnlineOrder
                            ? Colors.blueGrey
                            : Colors.green),
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
