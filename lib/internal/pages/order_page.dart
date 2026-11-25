import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../common/services/language_service.dart';
import '../../common/services/order_service.dart';
import '../../common/services/database_service.dart';
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
import '../keyboard_handlers/toggle_order_type_key_handler.dart';
import '../../common/services/order_match_service.dart';
import '../services/menu_data_service.dart';
import '../services/order_match_manager.dart';
import '../widgets/online_order_selection_dialog.dart';
import '../../common/models/dining_table.dart';
import '../../common/services/dining_table_service.dart';
import '../../common/services/print_service.dart';
import '../utils/dining_table_mapper.dart';
import '../widgets/dining_table_selection_dialog.dart';
import '../widgets/edit_product_dialog.dart';
import '../widgets/sold_out_dialog.dart';
import '../widgets/manage_options_dialog.dart';
import '../widgets/manage_kitchen_split_dialog.dart';
import '../widgets/option_selection_dialog.dart';
import '../widgets/selected_order_banners_widget.dart';

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
  String _orderType = 'takeaway';
  bool _isShareMode = true;

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
  final TextEditingController _tableNumberInputController = TextEditingController();
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
    MenuDataService.soldOutEventNotifier.addListener(_onSoldOutEventPushed);
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
      orderedProducts.clear();
      orderedProducts.addAll(snapshot);
      selectedOrderedProduct = orderedProducts.last;
      _selectedOnlineOrder = order;
      _selectedOnlineOrderOriginalProducts =
          OnlineOrderMapper.cloneSelectedProducts(snapshot);

      if (order.type != null) {
        final t = order.type!.toLowerCase();
        if (t.contains('takeaway') || t.contains('take_away')) {
          _orderType = 'takeaway';
        } else {
          _orderType = 'dinein';
          if (t.contains('noshare') || t.contains('no_share')) {
            _isShareMode = false;
          } else if (t.contains('share')) {
            _isShareMode = true;
          }
        }
      }
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
    _tableNumberInputController.clear();
  }

  Future<void> _showTablePicker() async {
    final result = await DiningTableSelectionDialog.show(context);
    if (result == null || !mounted) return;

    setState(() {
      _selectedTable = result.table;
      _tableNumberInputController.text = result.table.name;
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
        orderedProducts.addAll(tableProducts.cast<SelectedProduct>());
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

  Future<DiningTable> _ensureTableSelectedByName(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw Exception('Please enter a Table Number / 请输入台号');
    }

    if (_selectedTable != null &&
        (_selectedTable!.name.toLowerCase() == name.toLowerCase() ||
            _selectedTable!.id.toString() == name)) {
      return _selectedTable!;
    }

    final tables = await DiningTableService().getTables();
    final matches = tables.where((t) =>
        t.name.toLowerCase() == name.toLowerCase() ||
        t.id.toString() == name).toList();

    if (matches.isNotEmpty) {
      final matchedTable = matches.first;
      setState(() {
        _selectedTable = matchedTable;
        _tableNumberInputController.text = matchedTable.name;
      });
      return matchedTable;
    }

    final customTable = DiningTable(
      id: 990000 + name.hashCode.abs() % 90000,
      name: name,
      capacity: 4,
      status: 'occupied',
    );

    setState(() {
      _selectedTable = customTable;
      _tableNumberInputController.text = name;
    });
    return customTable;
  }

  Future<void> _handleOrderOrCheckoutTrigger() async {
    if (orderedProducts.isEmpty && !_hasSelectedOnlineOrder && !_hasSelectedTable) {
      await _showOnlineOrderPicker();
      return;
    }

    final bool isDineIn = _orderType == 'dinein' || _selectedTable != null;

    if (isDineIn) {
      await _showDineInConfirmDialog();
    } else {
      await _openCheckoutPage();
    }
  }

  Future<void> _showDineInConfirmDialog() async {
    if (orderedProducts.isEmpty) {
      UIHelper.showSnackBar(context, 'select_items_first'.tr, backgroundColor: Colors.orange);
      return;
    }

    final controller = TextEditingController(
      text: _tableNumberInputController.text.isNotEmpty
          ? _tableNumberInputController.text
          : (_selectedTable?.name ?? ''),
    );

    double totalPrice = 0.0;
    for (var p in orderedProducts) {
      double itemPrice = p.product.getPrice(_orderType == 'dinein' || _selectedTable != null);
      double optionsTotal = p.options.fold(0.0, (s, o) => s + o.option.extraCost);
      totalPrice += (itemPrice + optionsTotal) * p.quantity;
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.restaurant, color: Colors.blue[800]),
              const SizedBox(width: 8),
              Text('${'dine_in'.tr} - ${'confirm'.tr}'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${'selected_items_count'.trParams({'count': '${orderedProducts.length}'})} (\$${totalPrice.toStringAsFixed(2)})',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        labelText: 'Table Number (台号)',
                        hintText: 'e.g. 5, A1, Table 12',
                        prefixIcon: const Icon(Icons.table_restaurant),
                        border: const OutlineInputBorder(),
                        suffixIcon: controller.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  controller.clear();
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                      await _showTablePicker();
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      backgroundColor: Colors.blueGrey[700],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Pick Table'),
                  ),
                ],
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.all(16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save & Kitchen (下后厨单)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onPressed: () async {
                final tableInput = controller.text.trim();
                if (tableInput.isEmpty) {
                  UIHelper.showSnackBar(context, 'Please enter Table Number / 请输入台号', backgroundColor: Colors.orange);
                  return;
                }
                Navigator.of(dialogContext).pop();
                _tableNumberInputController.text = tableInput;
                await _ensureTableSelectedByName(tableInput);
                await _saveLocalTableOrder();
              },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.shopping_cart_checkout, size: 18),
              label: const Text('Checkout Now (立刻结账)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onPressed: () async {
                final tableInput = controller.text.trim();
                if (tableInput.isEmpty) {
                  UIHelper.showSnackBar(context, 'Please enter Table Number / 请输入台号', backgroundColor: Colors.orange);
                  return;
                }
                Navigator.of(dialogContext).pop();
                _tableNumberInputController.text = tableInput;
                await _ensureTableSelectedByName(tableInput);
                await _openCheckoutPage();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildTableNumberInputHeader() {
    if (_orderType != 'dinein') return const SizedBox.shrink();

    return Container(
      width: 140,
      margin: const EdgeInsets.only(left: 8),
      child: TextField(
        controller: _tableNumberInputController,
        decoration: InputDecoration(
          labelText: 'Table No.',
          hintText: '台号',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          prefixIcon: const Icon(Icons.table_restaurant, size: 16),
          border: const OutlineInputBorder(),
          suffixIcon: _tableNumberInputController.text.isNotEmpty
              ? InkWell(
                  onTap: () {
                    setState(() {
                      _tableNumberInputController.clear();
                      _clearTableSelection();
                    });
                  },
                  child: const Icon(Icons.close, size: 14),
                )
              : null,
        ),
        onChanged: (val) async {
          if (val.trim().isNotEmpty) {
            await _ensureTableSelectedByName(val.trim());
          } else {
            setState(() {
              _clearTableSelection();
            });
          }
        },
      ),
    );
  }

  Widget _buildSelectedTableBanner() {
    return SelectedTableBannerWidget(
      table: _selectedTable,
      isTableOrderExisting: _isTableOrderExisting,
      onChangeTable: _showTablePicker,
      onClearTable: () {
        setState(() {
          _clearTableSelection();
        });
      },
    );
  }

  Future<void> _handleOrderAction() async {
    await _handleOrderOrCheckoutTrigger();
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
        ? 'table_items_updated_printed'.trParams({
            'tableName': tableName,
            'count': '$addedCount',
          })
        : 'table_items_updated'.trParams({'tableName': tableName});

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
          initialOrderType: _orderType,
          isShareMode: _isShareMode,
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
        isSearchFocused: () => _searchInputFocusNode.hasFocus,
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
        onConfirmQuickInput: () async => await _confirmQuickInputSelection(keepSearchFocus: true),
        addProductIntelligently: (item) {
          if (_isAdminMode) {
            _showEditProductDialog(item);
          } else {
            _addProductIntelligently(item);
          }
        },
        addOptionToLastProduct: _addOptionToLastProduct,
        playClickSound: _playClickSound,
        clearQuickInput: () {
          _quickInputManager.clear();
          _syncSearchInputController();
        },
        removeQuickInputOverlay: _removeQuickInputOverlay,
        refreshUI: () => setState(() {}),
        onOrder: _handleOrderOrCheckoutTrigger,
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

    // Ctrl 键：切换外卖/堂食 (Takeaway / Dine in)
    _keyboardEventHandler.addHandler(
      toggleOrderTypeKeyHandler(
        onToggleOrderType: () {
          setState(() {
            _orderType = _orderType == 'takeaway' ? 'dinein' : 'takeaway';
          });
        },
        playClickSound: _playClickSound,
      ),
    );
    // 你可以继续添加更多 handler ...
  }

  void _onSoldOutEventPushed() {
    final event = MenuDataService.soldOutEventNotifier.value;
    if (event == null || !mounted) return;

    final int productId = event['productId'];
    final bool isSoldOut = event['isSoldOut'];
    final String? soldOutLabel = event['soldOutLabel'];

    setState(() {
      allProducts = allProducts.map((p) {
        if (p.id == productId) {
          return p.copyWith(isSoldOut: isSoldOut, soldOutLabel: soldOutLabel);
        }
        return p;
      }).toList();

      products = products.map((p) {
        if (p.id == productId) {
          return p.copyWith(isSoldOut: isSoldOut, soldOutLabel: soldOutLabel);
        }
        return p;
      }).toList();
    });
  }

  @override
  void dispose() {
    MenuDataService.soldOutEventNotifier.removeListener(_onSoldOutEventPushed);
    _searchInputFocusNode.removeListener(_handleSearchInputFocusChange);
    _pageKeyboardFocusNode.dispose();
    _searchInputFocusNode.dispose();
    _searchInputController.dispose();
    _tableNumberInputController.dispose();
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
        'product_sold_out_msg'.trParams({'title': item.title}),
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

    if (option.id == 0 || option.type.toLowerCase() == 'manual') {
      _handleManualOptionAddition(targetProduct!, option.name);
      return;
    }

    setState(() {
      targetProduct!.options.add(SelectedOption(type: type, option: option));
    });
  }

  Future<void> _handleManualOptionAddition(
      SelectedProduct targetProduct, String optionName) async {
    final double? extraPrice = await _showManualOptionPriceDialog(optionName);
    if (extraPrice == null) return;

    final manualOption = MenuOption(
      id: 0,
      name: optionName,
      type: 'manual',
      extraCost: extraPrice,
    );

    setState(() {
      targetProduct.options.add(
        SelectedOption(type: 'manual', option: manualOption),
      );
    });
    await _playClickSound();
  }

  /// 弹出手动添加 Option 的 Extra Price 金额输入弹窗
  Future<double?> _showManualOptionPriceDialog(String optionName) {
    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ManualOptionPriceDialog(optionName: optionName),
    );
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
    if (orderedProducts.isEmpty) return;
    final options = optionGroups[type] ?? [];
    if (options.isEmpty) return;

    OptionSelectionDialog.show(
      context: context,
      type: type,
      options: options,
      onOptionSelected: (option) {
        _addOptionToLastProduct(type, option);
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

    _quickInputManager.clear();
    _syncSearchInputController();
    _removeQuickInputOverlay();

    if (selectedItem is MenuItem) {
      if (selectedItem.id == 0) {
        final result = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (dialogContext) => _ManualProductPriceDialog(productName: selectedItem.title),
        );
        if (result == null) return;
        
        final manualItem = MenuItem(
          id: DateTime.now().millisecondsSinceEpoch,
          code: 'MANUAL_${DateTime.now().millisecondsSinceEpoch}',
          title: result['name'] as String,
          acronym: '',
          sellingPrice: result['price'] as double,
          dineInPrice: result['price'] as double,
          stock: 999,
          sort: 0,
          categoryIds: [],
          isPrintable: true,
        );
        _addProductIntelligently(manualItem);
        await _playClickSound();
      } else if (_isAdminMode) {
        _showEditProductDialog(selectedItem);
        await _playClickSound();
      } else {
        _addProductIntelligently(selectedItem);
        await _playClickSound();
      }
    } else if (selectedItem is MenuOption && orderedProducts.isNotEmpty) {
      _addOptionToLastProduct(selectedItem.type, selectedItem);
      await _playClickSound();
    }

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
    final bool isSearchActive = _quickInputManager.hasInput && _quickInputManager.hasResults;
    final isQuickInputControlKey = (isSearchActive && (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown)) ||
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
        onItemTap: (item) async {
          _playClickSound();
          _quickInputManager.clear();
          _syncSearchInputController();
          _removeQuickInputOverlay();
          if (item.id == 0) {
            final result = await showDialog<Map<String, dynamic>>(
              context: context,
              builder: (dialogContext) => _ManualProductPriceDialog(productName: item.title),
            );
            if (result != null) {
              final manualItem = MenuItem(
                id: DateTime.now().millisecondsSinceEpoch,
                code: 'MANUAL_${DateTime.now().millisecondsSinceEpoch}',
                title: result['name'] as String,
                acronym: '',
                sellingPrice: result['price'] as double,
                dineInPrice: result['price'] as double,
                stock: 999,
                sort: 0,
                categoryIds: [],
                isPrintable: true,
              );
              _addProductIntelligently(manualItem);
            }
          } else if (_isAdminMode) {
            _showEditProductDialog(item);
          } else {
            _addProductIntelligently(item);
          }
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



  Future<void> _refreshMenuData() async {
    final menuData = await _menuDataService.loadMenuData();
    if (mounted) {
      setState(() {
        allProducts = menuData['allProducts'] ?? [];
        products = menuData['products'] ?? [];
        categories = menuData['categories'] ?? [];
      });
    }
  }

  Future<void> _refreshOptionsData() async {
    final options = await _menuDataService.loadOptions();
    if (mounted) {
      setState(() {
        optionGroups = options;
      });
    }
  }

  /// 显示沽清设置对话框
  void _showSoldOutDialog(MenuItem product) {
    SoldOutDialog.show(
      context: context,
      product: product,
      onProductUpdated: _refreshMenuData,
    );
  }

  /// Show edit product dialog (Admin Mode)
  void _showEditProductDialog(MenuItem product) {
    EditProductDialog.show(
      context: context,
      product: product,
      categories: categories,
      onProductUpdated: _refreshMenuData,
      onShowSoldOut: _showSoldOutDialog,
    );
  }

  /// Show manage menu options dialog (Admin Mode)
  void _showManageOptionsDialog() {
    ManageOptionsDialog.show(
      context: context,
      optionGroups: optionGroups,
      onOptionsUpdated: _refreshOptionsData,
    );
  }

  /// Show manage kitchen split dialog (Admin Mode)
  void _showManageKitchenSplitDialog() {
    ManageKitchenSplitDialog.show(
      context: context,
      allProducts: allProducts,
      categories: categories,
      onSaved: _refreshMenuData,
    );
  }

  Future<void> _performOrderMatchCheck() async {
    await _orderMatchManager.performCheck(_onOrderMatchResultUpdated);
  }

  Widget _buildOrderTypeAndShareSelector() {
    final bool isDineIn = _orderType == 'dinein' || _selectedTable != null;
    final int totalQty =
        orderedProducts.fold<int>(0, (sum, p) => sum + p.quantity);
    final double totalAmount = orderedProducts.fold<double>(0.0, (sum, p) {
      final price = p.product.getPrice(isDineIn);
      final optCost =
          p.options.fold<double>(0.0, (s, o) => s + o.option.extraCost);
      return sum + (price + optCost) * p.quantity;
    });

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: Row(
        children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment<String>(
                value: 'takeaway',
                label: Text(
                  'takeaway'.tr,
                  style: TextStyle(
                    color: _orderType == 'takeaway' ? Colors.orange[900] : Colors.grey[700],
                    fontWeight: _orderType == 'takeaway' ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                icon: Icon(
                  Icons.takeout_dining,
                  size: 16,
                  color: _orderType == 'takeaway' ? Colors.orange[900] : Colors.grey[600],
                ),
              ),
              ButtonSegment<String>(
                value: 'dinein',
                label: Text(
                  'dine_in'.tr,
                  style: TextStyle(
                    color: _orderType == 'dinein' ? Colors.blue[800] : Colors.grey[700],
                    fontWeight: _orderType == 'dinein' ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                icon: Icon(
                  Icons.restaurant,
                  size: 16,
                  color: _orderType == 'dinein' ? Colors.blue[800] : Colors.grey[600],
                ),
              ),
            ],
            selected: {_orderType},
            onSelectionChanged: (Set<String> selection) {
              setState(() {
                _orderType = selection.first;
              });
            },
            style: ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                if (states.contains(WidgetState.selected)) {
                  return _orderType == 'takeaway'
                      ? Colors.orange.shade50
                      : Colors.blue.shade50;
                }
                return null;
              }),
            ),
          ),
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: totalQty > 0 ? Colors.deepOrange.shade50 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: totalQty > 0 ? Colors.deepOrange.shade400 : Colors.grey.shade400,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shopping_bag_outlined,
                      size: 18,
                      color: totalQty > 0 ? Colors.orange[900] : Colors.grey[700],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$totalQty ${'quantity'.tr}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: totalQty > 0 ? Colors.orange[900] : Colors.grey[800],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '|',
                      style: TextStyle(
                        fontSize: 12,
                        color: totalQty > 0 ? Colors.deepOrange[300] : Colors.grey[500],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '\$${totalAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: totalQty > 0 ? Colors.orange[900] : Colors.grey[800],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Visibility(
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            visible: _orderType == 'dinein',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('share'.tr),
                      icon: const Icon(Icons.groups, size: 14),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('no_share'.tr),
                      icon: const Icon(Icons.person, size: 14),
                    ),
                  ],
                  selected: {_isShareMode},
                  onSelectionChanged: (Set<bool> selection) {
                    setState(() {
                      _isShareMode = selection.first;
                    });
                  },
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                _buildTableNumberInputHeader(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleOrderNow() async {
    if (orderedProducts.isEmpty) {
      UIHelper.showSnackBar(context, 'select_items_first'.tr,
          backgroundColor: Colors.orange);
      return;
    }

    try {
      final orderService = OrderService();
      final databaseService = DatabaseService();
      final printService = PrintService();

      final bool isDineIn = _orderType == 'dinein' || _selectedTable != null;
      final items = OnlineOrderMapper.toCheckoutItems(orderedProducts, isDineIn: isDineIn);
      final double total = orderedProducts.fold(0.0, (sum, p) {
        double price = p.product.getPrice(isDineIn);
        double optCost = p.options.fold(0.0, (s, o) => s + o.option.extraCost);
        return sum + (price + optCost) * p.quantity;
      });

      final now = DateTime.now();
      String finalType = _orderType == 'dinein'
          ? (_isShareMode ? 'dinein_share' : 'dinein_noshare')
          : 'takeaway';

      String tableNote =
          _selectedTable != null ? '[桌台: ${_selectedTable!.name}]' : '';

      String orderNo;

      if (_selectedOnlineOrder != null) {
        // 更新已有暂存单/网单
        final updatedOrder = _selectedOnlineOrder!.copyWith(
          items: jsonEncode(items),
          totalAmount: double.parse(total.toStringAsFixed(2)),
          type: finalType,
          note: tableNote.isNotEmpty ? tableNote : _selectedOnlineOrder!.note,
          orderStatus: OrderStatus.pending,
        );
        await databaseService.updateOrder(updatedOrder);
        if (await printService.isAutoPrintEnabled()) {
          await printService.printOrderWithTemplates(updatedOrder);
        }
        orderNo = updatedOrder.orderNo;
      } else {
        // 新建暂存订单
        orderNo = await orderService.generateOrderNo();
        final orderId =
            '$orderNo-${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

        final order = OrderModel(
          id: orderId,
          orderNo: orderNo,
          orderTime: now,
          createdAt: now,
          items: jsonEncode(items),
          totalAmount: double.parse(total.toStringAsFixed(2)),
          discountAmount: 0.0,
          taxRate: 10.0,
          serviceFee: 0.0,
          cashAmount: 0.0,
          posAmount: 0.0,
          orderStatus: OrderStatus.pending,
          syncStatus: SyncStatus.pending,
          printStatus: PrintStatus.pending,
          note: tableNote.isNotEmpty ? tableNote : null,
          type: finalType,
          cashChange: 0.0,
          voucherAmount: 0.0,
          isOnlineOrder: false,
        );

        await databaseService.insertOrder(order);

        if (await printService.isAutoPrintEnabled()) {
          await printService.printOrderWithTemplates(order);
        }
      }

      if (!mounted) return;

      UIHelper.showToast(
        context,
        '${'staging_order_created'.tr}: #$orderNo',
        backgroundColor: Colors.green,
      );

      setState(() {
        orderedProducts.clear();
        selectedOrderedProduct = null;
        _clearTableSelection();
        _clearOnlineOrderSelection();
      });
    } catch (e) {
      if (!mounted) return;
      UIHelper.showSnackBar(context, 'Order creation failed: $e',
          backgroundColor: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _pageKeyboardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (!_shouldHandleGlobalKeyEvent(event)) return KeyEventResult.ignored;
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

        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.arrowUp ||
             event.logicalKey == LogicalKeyboardKey.arrowDown ||
             event.logicalKey == LogicalKeyboardKey.escape ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double searchBarHeight = 40.0;
              final double minHeight = 120.0;
              final double maxHeight = 280.0;
              final double baseItemHeight = 32.0;
              final double optionHeight = 14.0;
              final int crossAxisCount = 3;

              double maxCardHeight = baseItemHeight;
              for (var product in orderedProducts) {
                double cardHeight = baseItemHeight +
                    (product.options.length * optionHeight) +
                    16;
                if (cardHeight > maxCardHeight) maxCardHeight = cardHeight;
              }

              final int rowCount =
                  (orderedProducts.length / crossAxisCount).ceil();
              final double calculatedHeight =
                  (rowCount * maxCardHeight) + 32;
              final double actualHeight =
                  calculatedHeight.clamp(minHeight, maxHeight);

              return Column(
                children: [
                  _buildSelectedTableBanner(),
                  //顶部展示区
                  _buildOrderTypeAndShareSelector(),
                  // 已点菜品区
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
                    isDineIn: _orderType == 'dinein' || _selectedTable != null,
                  ),
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
                                  isAdminMode: _isAdminMode,
                                  onManageKitchenSplit: _isAdminMode
                                      ? _showManageKitchenSplitDialog
                                      : null,
                                  onCategoryColorChanged: () {
                                    setState(() {});
                                  },
                                  onCategoryTap: (category) {
                                    if (category == null) {
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
                                      final targetCategoryIds = <int>{selectedCategoryId};
                                      void collectChildren(int parentId) {
                                        for (final cat in categories) {
                                          if (cat.parentId == parentId && !targetCategoryIds.contains(cat.id)) {
                                            targetCategoryIds.add(cat.id);
                                            collectChildren(cat.id);
                                          }
                                        }
                                      }
                                      collectChildren(selectedCategoryId);

                                      setState(() {
                                        products = allProducts
                                            .where((item) => item.categoryIds
                                                .any((id) => targetCategoryIds.contains(id)))
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
                        // 右侧：搜索区 + 菜品网格
                        Expanded(
                          flex: 8,
                          child: Column(
                            children: [
                              Container(
                                height: searchBarHeight,
                                color: Colors.grey[100],
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.search, size: 20),
                                      const SizedBox(width: 8),
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
                                            hintText: 'quick_search_hint'.tr,
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
                                    if (_isAdminMode) {
                                      _showEditProductDialog(item);
                                    } else {
                                      _addProductIntelligently(item);
                                    }
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
                  OrderActionBarWidget(
                    onVoidOrder: _voidOrder,
                    onClearOrder: _clearOrder,
                    onShowQuantitySelector: _showQuantitySelector,
                    onCustomAction: _customAction,
                    onOrder: _handleOrderAction,
                    onOrderNow: _handleOrderNow,
                    onSelectTable: _showTablePicker,
                    selectedTableName: _selectedTable?.name,
                    selectedOrder: _selectedOnlineOrder,
                    orderedCount: orderedProducts.length,
                    orderEnabled: true,
                    showQuickSelectButton: true,
                    isQuickSearchActive: _searchInputFocusNode.hasFocus,
                    orderLabel: _hasSelectedTable
                        ? 'confirm'.tr.toUpperCase()
                        : (_hasSelectedOnlineOrder
                            ? (_selectedOnlineOrder!.isPaid
                                ? 'update'.tr.toUpperCase()
                                : 'checkout'.tr.toUpperCase())
                            : (orderedProducts.isEmpty
                                ? 'add_order'.tr.toUpperCase()
                                : 'order'.tr.toUpperCase())),
                    orderIcon: _hasSelectedTable
                        ? Icons.check_circle_outline
                        : (_hasSelectedOnlineOrder
                            ? (_selectedOnlineOrder!.isPaid
                                ? Icons.sync_alt
                                : Icons.payment)
                            : (orderedProducts.isEmpty
                                ? Icons.playlist_add
                                : Icons.shopping_cart)),
                    orderColor: _hasSelectedTable
                        ? Colors.amber[800]!
                        : (_hasSelectedOnlineOrder
                            ? (_selectedOnlineOrder!.isPaid
                                ? Colors.teal[700]!
                                : Colors.deepOrange)
                            : (orderedProducts.isEmpty
                                ? Colors.blueGrey
                                : Colors.green)),
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

class _ManualOptionPriceDialog extends StatefulWidget {
  final String optionName;

  const _ManualOptionPriceDialog({required this.optionName});

  @override
  State<_ManualOptionPriceDialog> createState() =>
      __ManualOptionPriceDialogState();
}

class __ManualOptionPriceDialogState extends State<_ManualOptionPriceDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '0');
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final price = double.tryParse(_controller.text.trim()) ?? 0.0;
    Navigator.of(context).pop(price < 0 ? 0.0 : price);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      title: Row(
        children: [
          const Icon(Icons.edit_note, color: Colors.purple),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'manual_option_extra_price'.trParams({'name': widget.optionName}),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('extra_price_label'.tr,
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: const InputDecoration(
              prefixText: '\$ ',
              border: OutlineInputBorder(),
              hintText: '0.00',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text('cancel'.tr),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: Text('confirm'.tr),
        ),
      ],
    );
  }
}

class _ManualProductPriceDialog extends StatefulWidget {
  final String productName;

  const _ManualProductPriceDialog({required this.productName});

  @override
  State<_ManualProductPriceDialog> createState() =>
      __ManualProductPriceDialogState();
}

class __ManualProductPriceDialogState extends State<_ManualProductPriceDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.productName);
    _priceController = TextEditingController(text: '0');
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        _priceController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _priceController.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim()) ?? 0.0;
    Navigator.of(context).pop({
      'name': name.isEmpty ? widget.productName : name,
      'price': price < 0 ? 0.0 : price,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      title: Row(
        children: [
          const Icon(Icons.add_shopping_cart, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'manual_product_price'.trParams({'name': widget.productName}),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('product_name_label'.tr,
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          Text('extra_price_label'.tr,
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _priceController,
            focusNode: _focusNode,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              prefixText: '\$ ',
              border: OutlineInputBorder(),
              hintText: '0.00',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text('cancel'.tr),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: Text('confirm'.tr),
        ),
      ],
    );
  }
  }
