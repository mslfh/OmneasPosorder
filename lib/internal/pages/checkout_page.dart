import 'package:flutter/material.dart';
import 'order_page.dart';
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

  @override
  void initState() {
    super.initState();
    _controller.text = '';
  }

  @override
  void dispose() {
    _controller.dispose();
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

  double get change => receivedAmount > totalPrice ? receivedAmount - totalPrice : 0.0;

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
    return PopScope(
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
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
                  Text('\$${totalPrice.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
              // Card and Quick Cash area (side by side, left aligned)
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              updateReceivedAmount(totalPrice);
                            },
                            child: Text('Pos'),
                          ),
                          Text('Quick Cash', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          SizedBox(width: 8),
                          for (var cash in [5, 10, 20, 50])
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ElevatedButton(
                                onPressed: () {
                                  updateReceivedAmount(receivedAmount + cash);
                                },
                                child: Text('\$$cash'),
                              ),
                            ),
                        ],
                      ),
                     ],
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
                        labelText: 'Received Amount',
                        border: OutlineInputBorder(),
                      ),
                      controller: _controller,
                      onChanged: (val) {
                        double value = double.tryParse(val) ?? 0.0;
                        setState(() {
                          receivedAmount = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Change', style: TextStyle(fontSize: 16)),
                  Text('\$${change.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, color: Colors.green)),
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
                        // Use local transaction order service instead of direct API call
                        final orderService = OrderService();

                        // Prepare order items for local transaction
                        final orderItems = widget.orderedProducts.map((p) => {
                          'id': p.product.id,
                          'name': p.product.title, // 使用title而不是name
                          'price': p.product.sellingPrice, // 使用sellingPrice而不是price
                          'quantity': p.quantity,
                          'options': p.options.map((o) => {
                            'type': o.type,
                            'option_id': o.option.id,
                            'option_name': o.option.name,
                          }).toList(),
                          'note': '', // Add notes if needed
                        }).toList();

                        // Calculate total amount
                        double totalAmount = 0;
                        for (var product in widget.orderedProducts) {
                          totalAmount += product.product.sellingPrice * product.quantity; // 使用sellingPrice
                          // Add option prices if any
                          for (var option in product.options) {
                            totalAmount += option.option.extraCost * product.quantity; // 使用extraCost而不是price
                          }
                        }

                        // Place order using local transaction system
                        final orderId = await orderService.placeOrder(
                          items: orderItems,
                          totalAmount: totalAmount,
                        );

                        // Show success dialog
                        _showOrderSuccessDialog(orderId, totalAmount);

                      } catch (e) {
                        // Show error dialog
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
