import 'menu_item.dart';

class Order {
  final int id;
  final List<MenuItem> items;
  final String status;
  final String? remark;
  final DateTime createdAt;

  Order({
    required this.id,
    required this.items,
    required this.status,
    this.remark,
    required this.createdAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'],
      items: (json['items'] as List)
          .map((e) => MenuItem.fromJson(e))
          .toList(),
      status: json['status'],
      remark: json['remark'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

