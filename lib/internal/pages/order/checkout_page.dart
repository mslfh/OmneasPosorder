import 'package:flutter/material.dart';
import 'order_page.dart';
import '../../../common/services/api_service.dart';
import '../../../common/services/print_service.dart';
import 'dart:io';
import 'dart:convert';

class CheckoutPage extends StatefulWidget {
  final List<SelectedProduct> orderedProducts;
  const CheckoutPage({Key? key, required this.orderedProducts}) : super(key: key);

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  double receivedAmount = 0.0;
  bool isCash = false;
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
      double optionsTotal = p.options.fold(0.0, (s, o) => s + o.option.extraCost);
      sum += p.product.sellingPrice + optionsTotal;
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // 禁止系统返回
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
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(p.product.title, style: TextStyle(fontWeight: FontWeight.bold)),
                                Text('¥${p.product.sellingPrice.toStringAsFixed(2)}'),
                              ],
                            ),
                            ...p.options.map((opt) => Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${opt.type}: ${opt.option.name}', style: TextStyle(fontSize: 13)),
                                if (opt.option.extraCost > 0)
                                  Text('Extra: ¥${opt.option.extraCost.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, color: Colors.red)),
                              ],
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
                  Text('¥${totalPrice.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                                child: Text('¥$cash'),
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
                  Text('¥${change.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, color: Colors.green)),
                ],
              ),
              SizedBox(height: 8),
              // Order button
              ElevatedButton(
                onPressed: () async {
                  // 1. Call order/place API
                  final api = ApiService();
                  final orderData = widget.orderedProducts.map((p) => {
                    'product_id': p.product.id,
                    'options': p.options.map((o) => {
                      'type': o.type,
                      'option_id': o.option.id,
                    }).toList(),
                  }).toList();
                  await api.post('orders/place', {
                    'items': orderData,
                  });
                  // 2. Call print service
                  final printer = PrintService();
                  await printer.printReceipt(
                    orderData: orderData,
                    totalPrice: totalPrice,
                    receivedAmount: receivedAmount,
                    change: change,
                  );
                },
                child: Text('Order'),
              ),
              SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
