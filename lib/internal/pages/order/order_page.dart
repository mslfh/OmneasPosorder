import 'package:flutter/material.dart';
import '../../../common/models/menu_item.dart';
import '../../../common/models/category.dart';
import '../../../common/services/api_service.dart';
import '../../../common/models/menu_option.dart';
import 'checkout_page.dart';

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
    fetchData();
    fetchOptions();
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
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> fetchOptions() async {
    try {
      final api = ApiService();
      final response = await api.get('attributes/group');
      final data = response.data['data'] as Map<String, dynamic>;
      setState(() {
        optionGroups = data.map((type, list) => MapEntry(
          type,
          (list as List).map((e) => MenuOption.fromJson(e)).toList(),
        ));
      });
    } catch (e) {
      // 可选：处理错误
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 已点菜品列表
        LayoutBuilder(
          builder: (context, constraints) {
            double minHeight = 80;
            double maxHeight = 240;
            int crossAxisCount = 2;
            double itemHeight = 60;
            // 计算所有菜品卡片实际高度（包含选项）
            List<double> cardHeights = orderedProducts.map((p) {
              int optionCount = p.options.length;
              return itemHeight + optionCount * 28.0;
            }).toList();
            int rowCount = (orderedProducts.length / crossAxisCount).ceil();
            double totalHeight = cardHeights.fold(0.0, (sum, h) => sum + h) / crossAxisCount;
            double calcHeight = totalHeight.clamp(minHeight, maxHeight).toDouble();
            return Container(
              height: calcHeight,
              color: Colors.blue[50],
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: 3.5,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: orderedProducts.length,
                    physics: calcHeight >= maxHeight
                        ? AlwaysScrollableScrollPhysics()
                        : NeverScrollableScrollPhysics(),
                    itemBuilder: (context, index) {
                      final ordered = orderedProducts[index];
                      return Card(
                        child: LayoutBuilder(
                          builder: (context, cardConstraints) {
                            return Container(
                              height: cardConstraints.maxHeight,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(ordered.product.title, style: TextStyle(fontWeight: FontWeight.bold)),
                                      Text('¥${ordered.product.sellingPrice.toStringAsFixed(2)}'),
                                    ],
                                  ),
                                  if (ordered.options.isNotEmpty)
                                    Expanded(
                                      child: ListView.builder(
                                        itemCount: ordered.options.length,
                                        itemBuilder: (ctx, optIdx) {
                                          final opt = ordered.options[optIdx];
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 2.0),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text('${opt.type}: ${opt.option.name}', style: TextStyle(fontSize: 13)),
                                                if (opt.option.extraCost > 0)
                                                  Text('Extra: ¥${opt.option.extraCost.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, color: Colors.red)),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        Expanded(
          child: Row(
            children: [
              // 分类侧边栏，与菜单选项栏对齐
              Container(
                width: 120,
                color: Colors.grey[200],
                child: Column(
                  children: [
                    SizedBox(height: 16),
                    Text('Categories', style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(
                      child: ListView.builder(
                        itemCount: categories.where((c) => c.parentId == null).length,
                        itemBuilder: (context, index) {
                          final parent = categories.where((c) => c.parentId == null).toList()[index];
                          final children = categories.where((c) => c.parentId == parent.id).toList();
                          return ExpansionTile(
                            title: Text(parent.title),
                            children: children.map((child) => ListTile(
                              title: Text(child.title),
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
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          children: [
                            Icon(Icons.search),
                            SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                decoration: InputDecoration(
                                  hintText: 'Search menu...',
                                  border: InputBorder.none,
                                ),
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
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: optionGroups.keys.map((type) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 12.0),
                                child: DropdownButton<String>(
                                  hint: Text(type),
                                  value: selectedProduct != null && selectedProduct!.title == orderedProducts.isNotEmpty ? selectedOptions[type] : null,
                                  items: optionGroups[type]!.map((opt) {
                                    return DropdownMenuItem<String>(
                                      value: opt.name,
                                      child: Row(
                                        children: [
                                          Text(opt.name),
                                          if (opt.extraCost > 0)
                                            Padding(
                                              padding: const EdgeInsets.only(left: 8.0),
                                              child: Text('Extra: ¥${opt.extraCost}', style: TextStyle(fontSize: 12, color: Colors.red)),
                                            ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (orderedProducts.isEmpty || selectedProduct == null) return;
                                    setState(() {
                                      selectedOptions[type] = val;
                                      // 更新最新已点菜品的选项
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
                    // 菜品网格
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
                                      childAspectRatio: 0.75,
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
                                          child: Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(item.code, style: TextStyle(fontWeight: FontWeight.bold)),
                                                SizedBox(height: 8),
                                                Text(item.title),
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
        // 结账按钮
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: SizedBox(
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
            ),
          ),
        ),
      ],
    );
  }
}

class SelectedProduct {
  final MenuItem product;
  List<SelectedOption> options;

  SelectedProduct({required this.product, required this.options});
}

class SelectedOption {
  final String type;
  final MenuOption option;

  SelectedOption({required this.type, required this.option});
}
