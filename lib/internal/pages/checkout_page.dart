import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../common/services/order_service.dart';
import 'order_list_page.dart';
import '../utils/order_selected.dart';

class CheckoutPage extends StatefulWidget {
  final List<SelectedProduct> orderedProducts;
  const CheckoutPage({Key? key, required this.orderedProducts}) : super(key: key);

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  double receivedAmount = 0.0;
  bool isCash = false;
  String orderType = 'TAKE AWAY'; // 添加订单类型状态
  final TextEditingController _controller = TextEditingController();
  final FocusNode _amountInputFocusNode = FocusNode(); // 金额输入框的焦点节点
  final TextEditingController _noteController = TextEditingController(); // 订单备注输入框
  bool keepChange = false; // 新增：是否放弃找零

  @override
  void initState() {
    super.initState();
    _controller.text = '';
    // 在页面加载后让金额输入框获得焦点
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _amountInputFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _amountInputFocusNode.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double get totalPrice {
    double sum = 0.0;
    for (var p in widget.orderedProducts) {
      double itemPrice = p.product.sellingPrice;
      double optionsTotal = p.options.fold(0.0, (s, o) => s + o.option.extraCost);
      sum += (itemPrice + optionsTotal) * p.quantity; // multiply by quantity
    }
    return sum;
  }
  double get change => receivedAmount - totalPrice;

  void updateReceivedAmount(double value) {
    setState(() {
      receivedAmount = value;
      _controller.text = value == 0.0 ? '' : value.toString();
      _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
    });
  }

  // 订单类型切换方法
  void _toggleOrderType() {
    setState(() {
      orderType = orderType == 'DINE IN' ? 'TAKE AWAY' : 'DINE IN';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      // 使用 Focus widget 包裹整个页面，捕获全局键盘事件
      onKeyEvent: (FocusNode node, KeyEvent event) {
        // 仅当金额输入框有焦点时才处理快捷键
        if (_amountInputFocusNode.hasFocus && event is KeyDownEvent) {
          // Ctrl 键：切换订单类型（Dine in/Take away）
          if (event.logicalKey == LogicalKeyboardKey.controlLeft || 
              event.logicalKey == LogicalKeyboardKey.controlRight) {
            _toggleOrderType();
            return KeyEventResult.handled; // 标记事件已处理
          }
          // 空格键：同 Pos 按钮功能，将 Received Amount 设为 Total
          if (event.logicalKey == LogicalKeyboardKey.space) {
            setState(() {
              isCash = false; // 设为 POS 支付
              updateReceivedAmount(totalPrice);
            });
            return KeyEventResult.handled; // 标记事件已处理
          }
        }
        return KeyEventResult.ignored; // 未处理的事件继续传递
      },
      child: PopScope(
        canPop: false, // disable system back navigation
        child: Scaffold(
          appBar: AppBar(
            title: Text('Checkout'),
            leading: IconButton(
              icon: Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ordered Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.orderedProducts.length,
                    itemBuilder: (context, idx) {
                      final p = widget.orderedProducts[idx];
                      double itemPrice = p.product.sellingPrice;
                      double optionsTotal = p.options.fold(0.0, (s, o) => s + o.option.extraCost);
                      double itemTotalPrice = (itemPrice + optionsTotal) * p.quantity;

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      p.product.title,
                                      style: TextStyle(fontWeight: FontWeight.bold)
                                    )
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[100],
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.blue[300]!, width: 1),
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
                                      SizedBox(width: 8),
                                      Text('\$${itemTotalPrice.toStringAsFixed(2)}',
                                        style: TextStyle(fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ],
                              ),
                              SizedBox(height: 4),
                              Row(
                                children: [
                                  Text('Unit price: \$${itemPrice.toStringAsFixed(2)}',
                                    style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                                ],
                              ),
                              ...p.options.map((opt) => Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('${opt.type}: ${opt.option.name}',
                                      style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                                    if (opt.option.extraCost > 0)
                                      Text('+\$${opt.option.extraCost.toStringAsFixed(2)}',
                                        style: TextStyle(fontSize: 12, color: Colors.red)),
                                  ],
                                ),
                              ))
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('\$${totalPrice.toStringAsFixed(2)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
                SizedBox(height: 16),
                // 订单类型选择区域 - 左右布局
                Row(
                  children: [
                    // 左侧：Order Type 标签
                    Text('Order Type: ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Spacer(), // 推送右侧内容到最右边
                    // 右侧：只有订单类型切换按钮
                    ElevatedButton.icon(
                      onPressed: _toggleOrderType,
                      icon: Icon(
                        orderType == 'DINE IN' ? Icons.restaurant : Icons.takeout_dining,
                        size: 18
                      ),
                      label: Text(
                        orderType,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: orderType == 'DINE IN' ? Colors.blue[400] : Colors.green[400],
                        foregroundColor: Colors.white,
                        elevation: 3,
                        shadowColor: orderType == 'DINE IN' ? Colors.blue[200] : Colors.green[200],
                        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                // 支付方式显示
                Row(
                  children: [
                    Text('Payment Method: ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Spacer(),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                          SizedBox(width: 8),
                          Text(
                            isCash ? 'Cash' : 'POS',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isCash ? Colors.amber[800] : Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                // Card area：仅保留左侧 Pos 按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          isCash = false; // POS 支付
                          updateReceivedAmount(totalPrice);
                        });
                      },
                      child: Text('POS'),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: '\$ Received Amount',
                          border: OutlineInputBorder(),
                          // 添加提示文本，告知用户快捷键
                          helperText: 'Ctrl: Switch DINE IN / TAKE AWAY, Blank: POS Payment',
                        ),
                        controller: _controller,
                        focusNode: _amountInputFocusNode,
                        onChanged: (val) {
                          double value = double.tryParse(val) ?? 0.0;
                          setState(() {
                            receivedAmount = value;
                            isCash = true; // 手动输入视为现金支付
                          });
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                // 订单备注输入框
                TextField(
                  controller: _noteController,
                  decoration: InputDecoration(
                    labelText: 'Order Note',
                    border: OutlineInputBorder(),
                    hintText: 'Enter order note (optional)',
                  ),
                  maxLines: 1,
                ),
                SizedBox(height: 16),
                // Change 显示（仅一处）
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
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
                        if (change > 0.009)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: ElevatedButton(
                              onPressed: keepChange
                                  ? null
                                  : () {
                                      setState(() {
                                        keepChange = true;
                                      });
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: keepChange ? Colors.grey : Colors.deepOrange,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                minimumSize: Size(0, 0),
                              ),
                              child: Text(keepChange ? 'Kept Change' : 'Keep'),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      keepChange
                        ? '\$0.00'
                        : (change < 0 ? '-\$${change.abs().toStringAsFixed(2)}' : '\$${change.toStringAsFixed(2)}'),
                      style: TextStyle(
                        fontSize: 20,
                        color: change < 0
                            ? Colors.red
                            : (change > 0 ? Colors.black : Colors.grey),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                // Place Order按钮放在右下角
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          final orderService = OrderService();

                          // 准备订单项目
                          final orderItems = widget.orderedProducts.map((p) {
                            // 计算选项的额外费用
                            final options = p.options.map((o) => {
                              'type': o.type,
                              'option_id': o.option.id,
                              'option_name': o.option.name,
                              'extra_price': o.option.extraCost, // 添加选项的额外费用
                            }).toList();

                            return {
                              'id': p.product.id,
                              'name': p.product.title,
                              'price': p.product.sellingPrice,
                              'quantity': p.quantity,
                              'options': options,
                            };
                          }).toList();

                          // 计算总金额
                          double totalAmount = 0;
                          for (var product in widget.orderedProducts) {
                            double itemTotal = product.product.sellingPrice;
                            for (var option in product.options) {
                              itemTotal += option.option.extraCost;
                            }
                            totalAmount += itemTotal * product.quantity;
                          }

                          // 下单，包含所有新增字段
                          final orderId = await orderService.placeOrder(
                            items: orderItems,
                            totalAmount: totalAmount,
                            discountAmount: 0.0, // 默认无折扣
                            taxRate: 10.0,      // 默认税率 10%
                            serviceFee: 0.0,    // 默认无服务费
                            cashAmount: isCash ? receivedAmount : 0.0,
                            posAmount: isCash ? 0.0 : receivedAmount,
                            note: _noteController.text.trim(),
                            type: orderType == 'DINE IN' ? 'dinein' : 'takeaway',
                            cashChange: isCash ? (keepChange ? 0.0 : double.parse((receivedAmount - totalAmount).toStringAsFixed(2))) : 0.0, // 放弃找零逻辑
                            voucherAmount: 0.0, // 新增券金额字段，默认为0.00
                          );
                          setState(() { keepChange = false; }); // 下单后重置

                          // 显示成功对话框
                          _showOrderSuccessDialog(orderId, totalAmount);

                        } catch (e) {
                          // 显示错误对话框
                          _showErrorDialog('Order placement failed: $e');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                        textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shopping_cart_checkout, size: 20),
                          SizedBox(width: 8),
                          Text('Place Order'),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Show order success dialog
  void _showOrderSuccessDialog(String orderId, double totalAmount) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
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
            Text('Order ID: ${orderId.substring(0, 8)}'),
            SizedBox(height: 8),
            Text('Total Amount: \$${totalAmount.toStringAsFixed(2)}'),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
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
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Order saved locally',
                        style: TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.sync, color: Colors.orange, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Syncing to server in background',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.print, color: Colors.blue, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Sending to printer in background',
                        style: TextStyle(color: Colors.blue, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Return to previous page
            },
            child: Text('Continue'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Return to previous page
              // Navigate to order management
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => OrderListPage()),
              );
            },
            child: Text('View Orders'),
          ),
        ],
      ),
    );
  }

  /// Show error dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
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
            child: Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Retry the order
              // You could implement retry logic here
            },
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }
}
