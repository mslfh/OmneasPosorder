import 'dart:convert';

class ServerOrderModel {
  final int id; // 服务器订单主键
  final String orderNumber; // 服务器订单号
  final String orderNo; // 当天第几单
  final String type; // takeaway/dinein
  final String printStatus;
  final String syncStatus;
  final String status;
  final String totalAmount;
  final String taxRate;
  final String taxAmount;
  final String discountAmount;
  final String finalAmount;
  final String paidAmount;
  final String? note;
  final String? remark;
  final String? syncedAt;
  final String? createdAt;
  final String? updatedAt;
  final List<dynamic> items;
  final List<dynamic> additions;

  ServerOrderModel({
    required this.id,
    required this.orderNumber,
    required this.orderNo,
    required this.type,
    required this.printStatus,
    required this.syncStatus,
    required this.status,
    required this.totalAmount,
    required this.taxRate,
    required this.taxAmount,
    required this.discountAmount,
    required this.finalAmount,
    required this.paidAmount,
    this.note,
    this.remark,
    this.syncedAt,
    this.createdAt,
    this.updatedAt,
    required this.items,
    required this.additions,
  });

  factory ServerOrderModel.fromMap(Map<String, dynamic> map) {
    return ServerOrderModel(
      id: map['id'],
      orderNumber: map['order_number'],
      orderNo: map['order_no'],
      type: map['type'],
      printStatus: map['print_status'],
      syncStatus: map['sync_status'],
      status: map['status'],
      totalAmount: map['total_amount'],
      taxRate: map['tax_rate'],
      taxAmount: map['tax_amount'],
      discountAmount: map['discount_amount'],
      finalAmount: map['final_amount'],
      paidAmount: map['paid_amount'],
      note: map['note'],
      remark: map['remark'],
      syncedAt: map['synced_at'],
      createdAt: map['created_at'],
      updatedAt: map['updated_at'],
      items: map['items'] ?? [],
      additions: map['additions'] ?? [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_number': orderNumber,
      'order_no': orderNo,
      'type': type,
      'print_status': printStatus,
      'sync_status': syncStatus,
      'status': status,
      'total_amount': totalAmount,
      'tax_rate': taxRate,
      'tax_amount': taxAmount,
      'discount_amount': discountAmount,
      'final_amount': finalAmount,
      'paid_amount': paidAmount,
      'note': note,
      'remark': remark,
      'synced_at': syncedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'items': jsonEncode(items),
      'additions': jsonEncode(additions),
    };
  }
}

