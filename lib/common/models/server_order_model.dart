import 'dart:convert';

// 服务器订单状态枚举
enum ServerSyncStatus {
  pending,      // 待同步
  synced,       // 已同步
  failed,       // 同步失败
}

enum ServerPrintStatus {
  pending,      // 待打印
  printed,      // 已打印
  failed,       // 打印失败
}

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
  final String? paymentMethod;
  final String? tag;
  final int? userId;
  final String placeIn;
  final DateTime? deletedAt;
  final DateTime? orderTime;
  final List<dynamic> payments;

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
    this.paymentMethod,
    this.tag,
    this.userId,
    this.placeIn = 'online',
    this.deletedAt,
    this.orderTime,
    this.payments = const [],
  });

  static List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded;
      } catch (_) {}
    }
    return const [];
  }

  static DateTime? _asDateTime(dynamic value) {
    if (value == null) return null;
    final text = value.toString();
    if (text.isEmpty) return null;
    try {
      return DateTime.parse(text);
    } catch (_) {
      return null;
    }
  }

  static String _asString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    return value.toString();
  }

  // 获取订单状态
  ServerSyncStatus getSyncStatus() {
    switch (syncStatus.toLowerCase()) {
      case 'synced':
        return ServerSyncStatus.synced;
      case 'failed':
        return ServerSyncStatus.failed;
      default:
        return ServerSyncStatus.pending;
    }
  }

  // 获取打印状态
  ServerPrintStatus getPrintStatus() {
    switch (printStatus.toLowerCase()) {
      case 'printed':
        return ServerPrintStatus.printed;
      case 'failed':
        return ServerPrintStatus.failed;
      default:
        return ServerPrintStatus.pending;
    }
  }

  factory ServerOrderModel.fromMap(Map<String, dynamic> map) {
    return ServerOrderModel(
      id: map['id'] is int ? map['id'] as int : int.tryParse(map['id']?.toString() ?? '') ?? 0,
      orderNumber: _asString(map['order_number']),
      orderNo: _asString(map['order_no']),
      type: _asString(map['type']),
      printStatus: _asString(map['print_status'], 'pending'),
      syncStatus: _asString(map['sync_status'], 'pending'),
      status: _asString(map['status'], 'pending'),
      totalAmount: _asString(map['total_amount'], '0.00'),
      taxRate: _asString(map['tax_rate'], '0.00'),
      taxAmount: _asString(map['tax_amount'], '0.00'),
      discountAmount: _asString(map['discount_amount'], '0.00'),
      finalAmount: _asString(map['final_amount'], '0.00'),
      paidAmount: _asString(map['paid_amount'], '0.00'),
      note: map['note'],
      remark: map['remark'],
      syncedAt: map['synced_at']?.toString(),
      createdAt: map['created_at']?.toString(),
      updatedAt: map['updated_at']?.toString(),
      items: _asList(map['items']),
      additions: _asList(map['additions']),
      paymentMethod: map['payment_method'],
      tag: map['tag'],
      userId: map['user_id'],
      placeIn: _asString(map['place_in'], 'online'),
      deletedAt: _asDateTime(map['deleted_at']),
      orderTime: _asDateTime(map['order_time']),
      payments: _asList(map['payments']),
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
      'payment_method': paymentMethod,
      'tag': tag,
      'user_id': userId,
      'place_in': placeIn,
      'deleted_at': deletedAt?.toIso8601String(),
      'order_time': orderTime?.toIso8601String(),
      'payments': payments,
    };
  }
}

