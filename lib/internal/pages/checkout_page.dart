import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../common/services/language_service.dart';
import '../../common/models/order_model.dart';
import '../../common/models/dining_table.dart';
import '../../common/services/order_service.dart';
import '../../common/services/print_service.dart';
import '../../common/services/settings_service.dart';
import '../../common/services/database_service.dart';
import '../../common/services/dining_table_service.dart';
import 'order_list_page.dart';
import '../utils/order_selected.dart';
import '../utils/online_order_mapper.dart';

/// Settlement mode: Full bill, Split by person (均分), Split by item (按菜分单)
enum SplitType { full, byPerson, byItem }

/// TextInputFormatter to intercept space key input (soft keyboard & hardware keyboard across PC and Pad/Mobile)
class _SpaceToTogglePaymentFormatter extends TextInputFormatter {
  final VoidCallback onSpacePressed;

  _SpaceToTogglePaymentFormatter({required this.onSpacePressed});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.contains(' ')) {
      Future.microtask(onSpacePressed);
      return oldValue;
    }
    return newValue;
  }
}

class CheckoutPage extends StatefulWidget {
  final List<SelectedProduct> orderedProducts;
  final OrderModel? onlineOrder;
  final List<SelectedProduct> originalOnlineOrderedProducts;
  final DiningTable? diningTable;
  final int? tableOrderId;
  final int? reservationId;

  const CheckoutPage({
    super.key,
    required this.orderedProducts,
    this.onlineOrder,
    this.originalOnlineOrderedProducts = const [],
    this.diningTable,
    this.tableOrderId,
    this.reservationId,
  });

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  double receivedAmount = 0.0;
  bool isCash = false;
  String orderType = 'TAKE AWAY';
  final TextEditingController _controller = TextEditingController();
  final FocusNode _amountInputFocusNode = FocusNode();
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _noteInputFocusNode = FocusNode();
  bool keepChange = false;
  bool isPlacingOrder = false;

  // 分餐结算状态
  SplitType splitType = SplitType.full;

  // 按人头均分状态
  int splitPersonCount = 2;
  int currentPersonIndex = 1;
  double totalPaidSoFar = 0.0;

  // 按菜品分单状态
  List<SelectedProduct> remainingProducts = [];
  Map<int, int> selectedSplitQuantities = {};

  // 统一单号与分单日志追溯
  String? _masterOrderId;
  String? _masterOrderNo;
  double _accumulatedCash = 0.0;
  double _accumulatedPos = 0.0;
  int _subBillCount = 0;

  @override
  void initState() {
    super.initState();
    if (widget.diningTable != null) {
      orderType = 'DINE IN (${widget.diningTable!.name})';
    }
    _controller.text = '';
    _initRemainingProducts();
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _amountInputFocusNode.requestFocus();
    });
  }

  void _initRemainingProducts() {
    remainingProducts = widget.orderedProducts
        .map((p) => SelectedProduct(
              product: p.product,
              options: List.from(p.options),
              quantity: p.quantity,
            ))
        .toList();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    _controller.dispose();
    _amountInputFocusNode.dispose();
    _noteController.dispose();
    _noteInputFocusNode.dispose();
    super.dispose();
  }

  /// 总订单金额
  double get totalPrice {
    double sum = 0.0;
    for (var p in widget.orderedProducts) {
      double itemPrice = p.product.sellingPrice;
      double optionsTotal =
          p.options.fold(0.0, (s, o) => s + o.option.extraCost);
      sum += (itemPrice + optionsTotal) * p.quantity;
    }
    return double.parse(sum.toStringAsFixed(2));
  }

  /// 当前需支付金额（根据结算模式）
  double get currentPayableAmount {
    switch (splitType) {
      case SplitType.full:
        return totalPrice;
      case SplitType.byPerson:
        if (currentPersonIndex < splitPersonCount) {
          return double.parse(
              (totalPrice / splitPersonCount).toStringAsFixed(2));
        } else {
          return double.parse(
              (totalPrice - totalPaidSoFar).toStringAsFixed(2));
        }
      case SplitType.byItem:
        double sum = 0.0;
        for (int i = 0; i < remainingProducts.length; i++) {
          int qty = selectedSplitQuantities[i] ?? 0;
          if (qty > 0) {
            double itemPrice = remainingProducts[i].product.sellingPrice;
            double optionsTotal = remainingProducts[i].options
                .fold(0.0, (s, o) => s + o.option.extraCost);
            sum += (itemPrice + optionsTotal) * qty;
          }
        }
        return double.parse(sum.toStringAsFixed(2));
    }
  }

  /// 剩余待支付总额
  double get remainingTotalToPay {
    switch (splitType) {
      case SplitType.full:
        return totalPrice;
      case SplitType.byPerson:
        return double.parse((totalPrice - totalPaidSoFar).toStringAsFixed(2));
      case SplitType.byItem:
        double sum = 0.0;
        for (var p in remainingProducts) {
          double itemPrice = p.product.sellingPrice;
          double optionsTotal =
              p.options.fold(0.0, (s, o) => s + o.option.extraCost);
          sum += (itemPrice + optionsTotal) * p.quantity;
        }
        return double.parse(sum.toStringAsFixed(2));
    }
  }

  double get change =>
      double.parse((receivedAmount - currentPayableAmount).toStringAsFixed(2));

  bool get hasOnlineOrder => widget.onlineOrder != null;
  bool get onlineOrderItemsChanged =>
      hasOnlineOrder &&
      !OnlineOrderMapper.areSelectedProductsEqual(
        widget.orderedProducts,
        widget.originalOnlineOrderedProducts,
      );

  void _onSplitTypeChanged(SplitType newType) {
    setState(() {
      splitType = newType;
      _masterOrderId = null;
      _masterOrderNo = null;
      _accumulatedCash = 0.0;
      _accumulatedPos = 0.0;
      _subBillCount = 0;

      if (newType == SplitType.byPerson) {
        splitPersonCount = 2;
        currentPersonIndex = 1;
        totalPaidSoFar = 0.0;
      } else if (newType == SplitType.byItem) {
        _initRemainingProducts();
        selectedSplitQuantities.clear();
      }
      keepChange = false;
      updateReceivedAmount(currentPayableAmount);
    });
  }

  void updateReceivedAmount(double value) {
    final rounded = double.parse(value.toStringAsFixed(2));
    setState(() {
      receivedAmount = rounded;
      _controller.text = rounded == 0.0 ? '' : rounded.toStringAsFixed(2);
      _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length));
      if (receivedAmount - currentPayableAmount <= 0) {
        keepChange = false;
      }
    });
  }

  void _togglePaymentMethod() {
    setState(() {
      isCash = !isCash;
      updateReceivedAmount(currentPayableAmount);
    });
  }

  void _toggleOrderType() {
    setState(() {
      orderType = orderType == 'DINE IN' ? 'TAKE AWAY' : 'DINE IN';
    });
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight) {
      _toggleOrderType();
      return true;
    }

    if (key == LogicalKeyboardKey.enter) {
      if (!isPlacingOrder) {
        _placeOrder();
      }
      return true;
    }

    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return true;
    }

    return false;
  }

  Widget _buildSelectedTableBanner() {
    final table = widget.diningTable;
    if (table == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.table_restaurant, color: Colors.amber[800]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '已关联桌台：${table.name}${table.area != null ? ' (${table.area})' : ''}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.amber[900],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineOrderInfoCard() {
    final order = widget.onlineOrder!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_done, color: Colors.blue[700], size: 18),
              const SizedBox(width: 6),
              Text(
                'Online Order #${order.orderNo}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Remote: ${order.remoteOrderNumber ?? '-'}'),
          Text(
              'Current status: ${order.orderStatus.name} / ${order.syncStatus.name}'),
          if (order.note != null && order.note!.isNotEmpty)
            Text('Note: ${order.note}'),
          Text(
            onlineOrderItemsChanged
                ? 'Items changed: yes'
                : 'Items changed: no',
            style: TextStyle(
              color: onlineOrderItemsChanged
                  ? Colors.orange[800]
                  : Colors.green[700],
            ),
          ),
        ],
      ),
    );
  }

  /// 结算模式选择器组件
  Widget _buildSplitModeSelector() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.call_split, size: 18, color: Colors.indigo),
              const SizedBox(width: 6),
              const Text(
                'Mode:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              SegmentedButton<SplitType>(
                segments: const [
                  ButtonSegment<SplitType>(
                    value: SplitType.full,
                    label: Text('Full Bill'),
                    icon: Icon(Icons.receipt_long, size: 14),
                  ),
                  ButtonSegment<SplitType>(
                    value: SplitType.byPerson,
                    label: Text('By Person'),
                    icon: Icon(Icons.groups, size: 14),
                  ),
                  ButtonSegment<SplitType>(
                    value: SplitType.byItem,
                    label: Text('By Item'),
                    icon: Icon(Icons.restaurant_menu, size: 14),
                  ),
                ],
                selected: {splitType},
                onSelectionChanged: (Set<SplitType> newSelection) {
                  _onSplitTypeChanged(newSelection.first);
                },
                style: const ButtonStyle(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          if (splitType == SplitType.byPerson) ...[
            const SizedBox(height: 10),
            _buildSplitByPersonPanel(),
          ] else if (splitType == SplitType.byItem) ...[
            const SizedBox(height: 10),
            _buildSplitByItemPanel(),
          ],
        ],
      ),
    );
  }

  /// 按人头均分控制面板
  Widget _buildSplitByPersonPanel() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.indigo[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'People Count:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: splitPersonCount > 2
                    ? () {
                        setState(() {
                          splitPersonCount--;
                          currentPersonIndex = 1;
                          totalPaidSoFar = 0.0;
                          updateReceivedAmount(currentPayableAmount);
                        });
                      }
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  '$splitPersonCount',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: splitPersonCount < 20
                    ? () {
                        setState(() {
                          splitPersonCount++;
                          currentPersonIndex = 1;
                          totalPaidSoFar = 0.0;
                          updateReceivedAmount(currentPayableAmount);
                        });
                      }
                    : null,
              ),
              const SizedBox(width: 12),
              ...[2, 3, 4, 5].map((count) => Padding(
                    padding: const EdgeInsets.only(right: 4.0),
                    child: ChoiceChip(
                      label: Text('$count'),
                      selected: splitPersonCount == count,
                      visualDensity: VisualDensity.compact,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            splitPersonCount = count;
                            currentPersonIndex = 1;
                            totalPaidSoFar = 0.0;
                            updateReceivedAmount(currentPayableAmount);
                          });
                        }
                      },
                    ),
                  )),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Person $currentPersonIndex of $splitPersonCount',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo[900],
                  fontSize: 14,
                ),
              ),
              Text(
                'Payable: \$${currentPayableAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.deepOrange,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (currentPersonIndex - 1) / splitPersonCount,
              backgroundColor: Colors.indigo[100],
              color: Colors.indigo[600],
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  /// 按菜品分单控制面板
  Widget _buildSplitByItemPanel() {
    int selectedItemCount =
        selectedSplitQuantities.values.fold(0, (sum, qty) => sum + qty);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.teal[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Selected Items: $selectedItemCount (Tap item to add)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal[900],
                  fontSize: 13,
                ),
              ),
              Text(
                'Sub-bill: \$${currentPayableAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.deepOrange,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.select_all, size: 16),
                label: const Text('Select All'),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  setState(() {
                    for (int i = 0; i < remainingProducts.length; i++) {
                      selectedSplitQuantities[i] =
                          remainingProducts[i].quantity;
                    }
                    updateReceivedAmount(currentPayableAmount);
                  });
                },
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(Icons.deselect, size: 16),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  setState(() {
                    selectedSplitQuantities.clear();
                    updateReceivedAmount(0.0);
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get placeOrderButtonText {
    if (isPlacingOrder) return 'Placing Order...';
    switch (splitType) {
      case SplitType.full:
        return 'Place Order';
      case SplitType.byPerson:
        return 'Pay Person $currentPersonIndex/$splitPersonCount (\$${currentPayableAmount.toStringAsFixed(2)})';
      case SplitType.byItem:
        return 'Pay Sub-bill (\$${currentPayableAmount.toStringAsFixed(2)})';
    }
  }

  @override
  Widget build(BuildContext context) {
    final listProducts = splitType == SplitType.byItem
        ? remainingProducts
        : widget.orderedProducts;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text('checkout'.tr),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSelectedTableBanner(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Ordered Items',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (splitType == SplitType.byItem)
                    Text(
                      'Remaining items: ${remainingProducts.length}',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.teal[800],
                          fontWeight: FontWeight.w600),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (hasOnlineOrder) _buildOnlineOrderInfoCard(),
              if (hasOnlineOrder) const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: listProducts.length,
                  itemBuilder: (context, idx) {
                    final p = listProducts[idx];
                    double itemPrice = p.product.sellingPrice;
                    double optionsTotal =
                        p.options.fold(0.0, (s, o) => s + o.option.extraCost);
                    double itemTotalPrice =
                        (itemPrice + optionsTotal) * p.quantity;
                    int selectedQty = selectedSplitQuantities[idx] ?? 0;
                    bool isItemSelected =
                        splitType == SplitType.byItem && selectedQty > 0;

                    return Card(
                      color: isItemSelected ? Colors.teal[50] : null,
                      shape: isItemSelected
                          ? RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: const BorderSide(
                                  color: Colors.teal, width: 1.5),
                            )
                          : null,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: splitType == SplitType.byItem
                            ? () {
                                setState(() {
                                  if (selectedQty < p.quantity) {
                                    selectedSplitQuantities[idx] =
                                        selectedQty + 1;
                                    updateReceivedAmount(currentPayableAmount);
                                  }
                                });
                              }
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            p.product.title,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        if (splitType == SplitType.byItem &&
                                            selectedQty > 0) ...[
                                          const SizedBox(width: 8),
                                          InkWell(
                                            onTap: () {
                                              setState(() {
                                                if (selectedQty - 1 <= 0) {
                                                  selectedSplitQuantities
                                                      .remove(idx);
                                                } else {
                                                  selectedSplitQuantities[
                                                          idx] =
                                                      selectedQty - 1;
                                                }
                                                updateReceivedAmount(
                                                    currentPayableAmount);
                                              });
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: BoxDecoration(
                                                color: Colors.red[100],
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.remove,
                                                size: 16,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.teal,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '$selectedQty/${p.quantity}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[100],
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: Colors.blue[300]!,
                                              width: 1),
                                        ),
                                        child: Text(
                                          'x${p.quantity}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: Colors.blue[700],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                          '\$${itemTotalPrice.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                      'Unit price: \$${itemPrice.toStringAsFixed(2)}',
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600])),
                                ],
                              ),
                              ...p.options.map((opt) => Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('${opt.type}: ${opt.option.name}',
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey[700])),
                                        if (opt.option.extraCost > 0)
                                          Text(
                                              '+\$${opt.option.extraCost.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.red)),
                                      ],
                                    ),
                                  )),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              // 总额与拆单模式
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    splitType == SplitType.full
                        ? 'Total'
                        : (splitType == SplitType.byPerson
                            ? 'Total (\$${totalPrice.toStringAsFixed(2)})'
                            : 'Remaining Total'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '\$${(splitType == SplitType.full ? totalPrice : remainingTotalToPay).toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildSplitModeSelector(),
              const SizedBox(height: 12),
              // 订单类型选择
              Row(
                children: [
                  const Text('Order Type: ',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _toggleOrderType,
                    icon: Icon(
                        orderType == 'DINE IN'
                            ? Icons.restaurant
                            : Icons.takeout_dining,
                        size: 18),
                    label: Text(
                      orderType,
                      style:
                          const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: orderType == 'DINE IN'
                          ? Colors.blue[400]
                          : Colors.green[400],
                      foregroundColor: Colors.white,
                      elevation: 3,
                      shadowColor: orderType == 'DINE IN'
                          ? Colors.blue[200]
                          : Colors.green[200],
                      padding:
                          const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 支付方式
              Row(
                children: [
                  const Text('Payment Method: ',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isCash ? Colors.amber[100] : Colors.blue[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCash ? Colors.amber[400]! : Colors.blue[400]!,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isCash ? Icons.money : Icons.credit_card,
                          size: 18,
                          color: isCash ? Colors.amber[800] : Colors.blue[800],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isCash ? 'Cash' : 'POS',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color:
                                isCash ? Colors.amber[800] : Colors.blue[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // POS / Cash 按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        isCash = false;
                        updateReceivedAmount(currentPayableAmount);
                      });
                    },
                    child: const Text('POS'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        isCash = true;
                        updateReceivedAmount(currentPayableAmount);
                      });
                    },
                    child: const Text('Cash'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 实收金额 TextField
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        _SpaceToTogglePaymentFormatter(
                          onSpacePressed: _togglePaymentMethod,
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText:
                            '\$ Received Amount (Payable: \$${currentPayableAmount.toStringAsFixed(2)})',
                        border: const OutlineInputBorder(),
                        helperText:
                            'Ctrl: Switch DINE IN / TAKE AWAY, Space: Switch POS / Cash',
                      ),
                      controller: _controller,
                      focusNode: _amountInputFocusNode,
                      onChanged: (val) {
                        double value = double.tryParse(val) ?? 0.0;
                        final rounded = double.parse(value.toStringAsFixed(2));
                        setState(() {
                          receivedAmount = rounded;
                          isCash = true;
                          if (receivedAmount - currentPayableAmount <= 0) {
                            keepChange = false;
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 订单备注输入框
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Order Note',
                  border: OutlineInputBorder(),
                  hintText: 'Enter order note (optional)',
                ),
                maxLines: 1,
                focusNode: _noteInputFocusNode,
              ),
              const SizedBox(height: 12),
              // Change 显示
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Change',
                    style: TextStyle(
                      fontSize: 17,
                      color: change < 0
                          ? Colors.red
                          : (change > 0 ? Colors.black : Colors.grey),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (change > 0.009) ...[
                        SizedBox(
                          height: 26,
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                keepChange = !keepChange;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: keepChange
                                  ? Colors.grey[600]
                                  : Colors.deepOrange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 0),
                              textStyle: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            child: Text(keepChange ? 'Kept' : 'Keep'),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        keepChange
                            ? '\$0.00 (\$${change.toStringAsFixed(2)} Kept)'
                            : (change < 0
                                ? '-\$${change.abs().toStringAsFixed(2)}'
                                : '\$${change.toStringAsFixed(2)}'),
                        style: TextStyle(
                          fontSize: keepChange ? 16 : 20,
                          color: keepChange
                              ? Colors.grey[700]
                              : (change < 0
                                  ? Colors.red
                                  : (change > 0 ? Colors.black : Colors.grey)),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 下单按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: (isPlacingOrder ||
                            (splitType == SplitType.byItem &&
                                currentPayableAmount <= 0))
                        ? null
                        : () {
                            _placeOrder();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPlacingOrder
                          ? Colors.grey
                          : (splitType == SplitType.full
                              ? Colors.green
                              : Colors.indigo),
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 16, horizontal: 28),
                      textStyle:
                          const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shopping_cart_checkout, size: 20),
                        const SizedBox(width: 8),
                        Text(placeOrderButtonText),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  /// Show order success dialog
  void _showOrderSuccessDialog(String orderId, double totalAmount) {
    if (widget.diningTable != null) {
      DiningTableService().releaseTableOnCheckout(
        widget.diningTable!.id,
        reservationId: widget.reservationId,
      );
    }

    final continueButtonFocusNode = FocusNode();
    int countdownSeconds = 3;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (continueButtonFocusNode.canRequestFocus) {
                continueButtonFocusNode.requestFocus();
              }
            });

            if (countdownSeconds > 0) {
              Future.delayed(const Duration(seconds: 1), () {
                if (context.mounted) {
                  setDialogState(() {
                    countdownSeconds--;
                  });
                  if (countdownSeconds == 0) {
                    Navigator.of(dialogContext).pop();
                    Navigator.of(context).pop(true);
                  }
                }
              });
            }

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 32),
                  SizedBox(width: 8),
                  Text('Order Placed Successfully'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hasOnlineOrder
                      ? 'Online Order ID: $orderId - $orderType'
                      : 'Order ID: $orderId - $orderType'),
                  const SizedBox(height: 8),
                  Text(
                      'Note: ${_noteController.text.trim().isEmpty ? 'None' : _noteController.text.trim()}'),
                  const SizedBox(height: 8),
                  Text('Paid By: ${isCash ? 'Cash' : 'POS'}'),
                  const SizedBox(height: 8),
                  Text('Total Amount: \$${totalAmount.toStringAsFixed(2)}'),
                  const SizedBox(height: 8),
                  Text(
                      'Change: \$${keepChange ? '0.00 (Kept)' : change < 0 ? '${change.toStringAsFixed(2)} (Insufficient！)' : change.toStringAsFixed(2)}'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: Colors.green, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              hasOnlineOrder
                                  ? 'Order completed'
                                  : 'Order saved locally',
                              style:
                                  const TextStyle(color: Colors.green, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Builder(builder: (context) {
                          final settings = SettingsService().getSettings();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.sync,
                                      color: settings.enableAutoSync
                                          ? Colors.deepOrangeAccent
                                          : Colors.grey,
                                      size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    hasOnlineOrder
                                        ? (onlineOrderItemsChanged
                                            ? 'Server updated, completing order'
                                            : 'Server update not needed')
                                        : (settings.enableAutoSync
                                            ? 'Syncing to server'
                                            : 'Sync skipped'),
                                    style: TextStyle(
                                        color: settings.enableAutoSync
                                            ? Colors.deepOrangeAccent
                                            : Colors.grey,
                                        fontSize: 12),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              FutureBuilder<bool>(
                                future: PrintService().isAutoPrintEnabled(),
                                builder: (context, snapshot) {
                                  final isPrinting = snapshot.data ?? settings.enableAutoPrint;
                                  return Row(
                                    children: [
                                      Icon(Icons.print,
                                          color: isPrinting ? Colors.blue : Colors.grey,
                                          size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        isPrinting
                                            ? 'Sending to printer'
                                            : 'Printing skipped',
                                        style: TextStyle(
                                            color: isPrinting ? Colors.blue : Colors.grey,
                                            fontSize: 12),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  focusNode: continueButtonFocusNode,
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    Navigator.of(context).pop(true);
                  },
                  child: Text(
                      'Continue${countdownSeconds > 0 ? ' ($countdownSeconds)' : ''}'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const OrderListPage()),
                    );
                  },
                  child: const Text('View Orders'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 32),
            SizedBox(width: 8),
            Text('Order Failed'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _showMissingAmountDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('Missing Amount'),
        content: const Text(
            'Please input received amount or press Space to use POS payment.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// 下单执行方法
  void _placeOrder() async {
    if (isPlacingOrder) return;

    double payable = currentPayableAmount;
    if (payable <= 0) {
      _showErrorDialog('Payable amount must be greater than \$0.00');
      return;
    }

    if (receivedAmount == 0.0) {
      _showMissingAmountDialog();
      return;
    }

    setState(() {
      isPlacingOrder = true;
    });

    try {
      final orderService = OrderService();
      final databaseService = DatabaseService();
      final printService = PrintService();

      // 构建本次结算的商品项
      List<SelectedProduct> targetProducts;
      if (splitType == SplitType.byItem) {
        targetProducts = [];
        for (int i = 0; i < remainingProducts.length; i++) {
          int qty = selectedSplitQuantities[i] ?? 0;
          if (qty > 0) {
            targetProducts.add(SelectedProduct(
              product: remainingProducts[i].product,
              options: remainingProducts[i].options,
              quantity: qty,
            ));
          }
        }
      } else {
        targetProducts = widget.orderedProducts;
      }

      final subItems = OnlineOrderMapper.toCheckoutItems(targetProducts);
      final allItems = OnlineOrderMapper.toCheckoutItems(widget.orderedProducts);

      final cashChangeValue = isCash
          ? (keepChange
              ? 0.0
              : double.parse((receivedAmount - payable).toStringAsFixed(2)))
          : 0.0;

      double thisCash = isCash ? receivedAmount : 0.0;
      double thisPos = isCash ? 0.0 : receivedAmount;

      _accumulatedCash += thisCash;
      _accumulatedPos += thisPos;
      _subBillCount++;

      String userNote = _noteController.text.trim();
      String tableNote = widget.diningTable != null
          ? '[桌台: ${widget.diningTable!.name}${widget.diningTable!.area != null && widget.diningTable!.area!.isNotEmpty ? " (${widget.diningTable!.area})" : ""}]'
          : '';

      String finalNote = tableNote.isEmpty
          ? userNote
          : (userNote.isEmpty ? tableNote : '$tableNote $userNote');

      String finalType = widget.diningTable != null
          ? 'dinein'
          : (orderType.contains('DINE IN') ? 'dinein' : 'takeaway');

      // 整单结算逻辑
      if (splitType == SplitType.full) {
        String orderId;
        if (hasOnlineOrder) {
          await orderService.completeOnlineOrderCheckout(
            order: widget.onlineOrder!,
            items: allItems,
            totalAmount: totalPrice,
            discountAmount: 0.0,
            taxRate: 10.0,
            serviceFee: 0.0,
            cashAmount: thisCash,
            posAmount: thisPos,
            note: finalNote,
            type: finalType,
            cashChange: cashChangeValue,
            voucherAmount: 0.0,
            itemsChanged: onlineOrderItemsChanged,
          );
          orderId = widget.onlineOrder!.id;
        } else {
          orderId = await orderService.placeOrder(
            items: allItems,
            totalAmount: totalPrice,
            discountAmount: 0.0,
            taxRate: 10.0,
            serviceFee: 0.0,
            cashAmount: thisCash,
            posAmount: thisPos,
            note: finalNote,
            type: finalType,
            cashChange: cashChangeValue,
            voucherAmount: 0.0,
          );
        }

        if (widget.diningTable != null) {
          await databaseService.insertLog(LogModel(
            orderId: orderId,
            action: 'table_settlement',
            status: 'success',
            message: '[Table Settlement] 桌台订单完成结算 [桌台: ${widget.diningTable!.name}${widget.diningTable!.area != null && widget.diningTable!.area!.isNotEmpty ? " (${widget.diningTable!.area})" : ""}]',
            timestamp: DateTime.now(),
          ));
        }

        setState(() {
          keepChange = false;
        });
        _showOrderSuccessDialog(orderId, totalPrice);
        return;
      }

      // 分餐结算（按人头均分 或 按菜品分单）- 确保全局只有一个主订单，不拆分为多单
      if (_masterOrderNo == null) {
        if (hasOnlineOrder) {
          _masterOrderId = widget.onlineOrder!.id;
          _masterOrderNo = widget.onlineOrder!.orderNo;
        } else {
          _masterOrderNo = await orderService.generateOrderNo();
          final now = DateTime.now();
          _masterOrderId =
              '$_masterOrderNo-${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
        }
      }

      final masterId = _masterOrderId!;
      final masterNo = _masterOrderNo!;

      // 判断本次支付是否为最后一笔支付
      bool isFinalPayment = false;
      if (splitType == SplitType.byPerson) {
        if (currentPersonIndex >= splitPersonCount) {
          isFinalPayment = true;
        }
      } else if (splitType == SplitType.byItem) {
        int totalRemainingQty = 0;
        for (int i = 0; i < remainingProducts.length; i++) {
          int paidQty = selectedSplitQuantities[i] ?? 0;
          totalRemainingQty += (remainingProducts[i].quantity - paidQty);
        }
        if (totalRemainingQty <= 0) {
          isFinalPayment = true;
        }
      }

      String splitNoteInfo = splitType == SplitType.byPerson
          ? '[Person $currentPersonIndex/$splitPersonCount]'
          : '[Sub-bill #$_subBillCount]';
      String currentNote =
          finalNote.isEmpty ? splitNoteInfo : '$finalNote $splitNoteInfo';

      // 在本地数据库中落单/更新同一个主订单 (累计支付金额与状态)
      final DateTime now = DateTime.now();
      final masterOrder = OrderModel(
        id: masterId,
        orderNo: masterNo,
        orderTime: widget.onlineOrder?.orderTime ?? now,
        createdAt: widget.onlineOrder?.createdAt ?? now,
        items: jsonEncode(allItems),
        totalAmount: totalPrice,
        discountAmount: 0.0,
        taxRate: 10.0,
        serviceFee: 0.0,
        cashAmount: _accumulatedCash,
        posAmount: _accumulatedPos,
        orderStatus:
            isFinalPayment ? OrderStatus.completed : OrderStatus.pending,
        syncStatus: SyncStatus.pending,
        printStatus: PrintStatus.pending,
        note: currentNote,
        type: finalType,
        cashChange: cashChangeValue,
        voucherAmount: 0.0,
      );

      final existingOrder = await databaseService.getOrder(masterId);
      if (existingOrder == null) {
        await databaseService.insertOrder(masterOrder);
      } else {
        await databaseService.updateOrder(masterOrder);
      }

      // 记录到订单日志 (LogModel)
      List<String> targetItemSummary = targetProducts
          .map((p) => '${p.product.title} x${p.quantity}')
          .toList();
      String logMessage = splitType == SplitType.byPerson
          ? '[Split Settlement] Person $currentPersonIndex/$splitPersonCount paid \$${payable.toStringAsFixed(2)} via ${isCash ? 'Cash' : 'POS'} (Order #$masterNo)'
          : '[Split Settlement] Sub-bill #$_subBillCount paid \$${payable.toStringAsFixed(2)} via ${isCash ? 'Cash' : 'POS'} for items: ${targetItemSummary.join(', ')} (Order #$masterNo)';

      await databaseService.insertLog(LogModel(
        orderId: masterId,
        action: 'split_settlement',
        status: 'success',
        message: logMessage,
        timestamp: DateTime.now(),
      ));

      // 按菜品分单则只打印对应的选择菜品
      final printOrderItems =
          splitType == SplitType.byItem ? subItems : allItems;
      final tempPrintOrder = OrderModel(
        id: '${masterId}_sub_$_subBillCount',
        orderNo: '$masterNo-$_subBillCount',
        orderTime: now,
        createdAt: now,
        items: jsonEncode(printOrderItems),
        totalAmount: payable,
        discountAmount: 0.0,
        taxRate: 10.0,
        serviceFee: 0.0,
        cashAmount: thisCash,
        posAmount: thisPos,
        orderStatus: OrderStatus.completed,
        syncStatus: SyncStatus.skipped,
        printStatus: PrintStatus.pending,
        note: currentNote,
        type: orderType == 'DINE IN' ? 'dinein' : 'takeaway',
        cashChange: cashChangeValue,
        voucherAmount: 0.0,
      );

      final settings = SettingsService().getSettings();
      if (settings.enableAutoPrint) {
        await printService.printOrderWithTemplates(tempPrintOrder);
      }

      setState(() {
        keepChange = false;
      });

      // 处理拆单后续步骤
      if (splitType == SplitType.byPerson) {
        totalPaidSoFar += payable;
        if (!isFinalPayment) {
          int paidIndex = currentPersonIndex;
          setState(() {
            currentPersonIndex++;
            updateReceivedAmount(currentPayableAmount);
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Person $paidIndex paid \$${payable.toStringAsFixed(2)}. Ready for Person $currentPersonIndex of $splitPersonCount (\$${currentPayableAmount.toStringAsFixed(2)}).'),
                backgroundColor: Colors.indigo[700],
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      } else if (splitType == SplitType.byItem) {
        List<SelectedProduct> updatedRemaining = [];
        for (int i = 0; i < remainingProducts.length; i++) {
          int paidQty = selectedSplitQuantities[i] ?? 0;
          int remainingQty = remainingProducts[i].quantity - paidQty;
          if (remainingQty > 0) {
            updatedRemaining.add(SelectedProduct(
              product: remainingProducts[i].product,
              options: remainingProducts[i].options,
              quantity: remainingQty,
            ));
          }
        }
        setState(() {
          remainingProducts = updatedRemaining;
          selectedSplitQuantities.clear();
          updateReceivedAmount(currentPayableAmount);
        });

        if (!isFinalPayment) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Sub-bill paid \$${payable.toStringAsFixed(2)}. Remaining balance: \$${remainingTotalToPay.toStringAsFixed(2)}.'),
                backgroundColor: Colors.teal[700],
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      // 如果是最后一笔支付，且开启了自动同步，则推送同步主订单
      if (settings.enableAutoSync) {
        await orderService.retrySyncOrder(masterId);
      }

      // 所有账单结算完成，显示最终成功弹窗
      _showOrderSuccessDialog(masterNo, totalPrice);
    } catch (e) {
      _showErrorDialog('Order placement failed: $e');
    } finally {
      setState(() {
        isPlacingOrder = false;
      });
    }
  }
}
