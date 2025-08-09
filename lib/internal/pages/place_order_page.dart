import 'package:flutter/material.dart';
import '../../common/services/order_service.dart';
import 'order_list_page.dart';

class PlaceOrderPage extends StatefulWidget {
  @override
  _PlaceOrderPageState createState() => _PlaceOrderPageState();
}

class _PlaceOrderPageState extends State<PlaceOrderPage> {
  final OrderService _orderService = OrderService();
  final List<Map<String, dynamic>> _cartItems = [];
  bool _isPlacingOrder = false;

  // 模拟菜品数据
  final List<Map<String, dynamic>> _menuItems = [
    {'id': '1', 'name': '宫保鸡丁', 'price': 28.0},
    {'id': '2', 'name': '麻婆豆腐', 'price': 18.0},
    {'id': '3', 'name': '鱼香肉丝', 'price': 25.0},
    {'id': '4', 'name': '白米饭', 'price': 3.0},
    {'id': '5', 'name': '紫菜蛋花汤', 'price': 12.0},
  ];

  void _addToCart(Map<String, dynamic> menuItem) {
    setState(() {
      final existingIndex = _cartItems.indexWhere(
        (item) => item['id'] == menuItem['id']
      );

      if (existingIndex >= 0) {
        _cartItems[existingIndex]['quantity']++;
      } else {
        _cartItems.add({
          ...menuItem,
          'quantity': 1,
          'note': '',
        });
      }
    });
  }

  void _removeFromCart(int index) {
    setState(() {
      if (_cartItems[index]['quantity'] > 1) {
        _cartItems[index]['quantity']--;
      } else {
        _cartItems.removeAt(index);
      }
    });
  }

  double get _totalAmount {
    return _cartItems.fold(0.0, (sum, item) =>
      sum + (item['price'] * item['quantity'])
    );
  }

  Future<void> _placeOrder() async {
    if (_cartItems.isEmpty) {
      _showErrorSnackBar('购物车为空，请先添加菜品');
      return;
    }

    setState(() => _isPlacingOrder = true);

    try {
      // 调用订单服务的下单方法
      final orderId = await _orderService.placeOrder(
        items: _cartItems,
        totalAmount: _totalAmount,
      );

      setState(() => _isPlacingOrder = false);

      _showSuccessDialog(orderId);

      // 清空购物车
      setState(() => _cartItems.clear());

    } catch (e) {
      setState(() => _isPlacingOrder = false);
      _showErrorSnackBar('下单失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('点餐下单'),
        actions: [
          IconButton(
            icon: Icon(Icons.list),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => OrderListPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 菜单区域
          Expanded(
            flex: 2,
            child: _buildMenuSection(),
          ),

          // 购物车区域
          if (_cartItems.isNotEmpty) ...[
            Divider(height: 1),
            Expanded(
              flex: 1,
              child: _buildCartSection(),
            ),
          ],

          // 下单按钮
          _buildOrderButton(),
        ],
      ),
    );
  }

  Widget _buildMenuSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '菜单',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _menuItems.length,
            itemBuilder: (context, index) {
              final item = _menuItems[index];
              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  title: Text(item['name']),
                  subtitle: Text('￥${item['price'].toStringAsFixed(2)}'),
                  trailing: IconButton(
                    icon: Icon(Icons.add_circle, color: Colors.green),
                    onPressed: () => _addToCart(item),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCartSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '购物车',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '总计: ￥${_totalAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _cartItems.length,
            itemBuilder: (context, index) {
              final item = _cartItems[index];
              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: ListTile(
                  title: Text(item['name']),
                  subtitle: Text('￥${item['price'].toStringAsFixed(2)} x ${item['quantity']}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '￥${(item['price'] * item['quantity']).toStringAsFixed(2)}',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.remove_circle, color: Colors.red),
                        onPressed: () => _removeFromCart(index),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOrderButton() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      child: ElevatedButton(
        onPressed: _cartItems.isEmpty || _isPlacingOrder ? null : _placeOrder,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 16),
          textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        child: _isPlacingOrder
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('正在下单...'),
                ],
              )
            : Text('下单 (${_cartItems.length}项)'),
      ),
    );
  }

  void _showSuccessDialog(String orderId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('下单成功'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('订单号: ${orderId.substring(0, 8)}'),
            SizedBox(height: 8),
            Text('总金额: ￥${_totalAmount.toStringAsFixed(2)}'),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '✅ 订单已保存到本地',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                  Text(
                    '🔄 正在后台同步到服务器',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                  Text(
                    '🖨️ 正在后台发送到打印机',
                    style: TextStyle(color: Colors.blue, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('继续点餐'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => OrderListPage()),
              );
            },
            child: Text('查看订单'),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}
