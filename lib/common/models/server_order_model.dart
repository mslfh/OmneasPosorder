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
    if (value == null) return const [];
    if (value is List) return value;
    if (value is Map) return [value];
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded;
        if (decoded is Map) return [decoded];
      } catch (_) {}
    }
    return const [];
  }

  static DateTime? _asDateTime(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    try {
      final normalized = text.contains('T') ? text : text.replaceFirst(' ', 'T');
      final parsed = DateTime.parse(normalized);
      return parsed.isUtc ? parsed.toLocal() : parsed;
    } catch (_) {
      return null;
    }
  }

  static String _asString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    return value.toString();
  }

  /// 是否为堂食类型
  bool get isDineIn {
    final rawType = type.toLowerCase();
    final rawPlaceIn = placeIn.toLowerCase();
    return rawType.contains('dine') || rawType.contains('table') || rawPlaceIn == 'table';
  }

  /// 归一化为标准的后端 API 就餐类型字符串 ("dine_in" 或 "takeaway")
  String get normalizedApiType {
    return isDineIn ? 'dine_in' : 'takeaway';
  }

  /// 判断服务器订单是否已付清款项（对比应付金额 finalAmount 与已付金额 paidAmount）
  bool get isPaid {
    final statusLower = status.toLowerCase();
    if (statusLower == 'completed' || statusLower == 'paid') {
      return true;
    }

    final finalAmt = double.tryParse(finalAmount) ?? 0.0;
    final paidAmt = double.tryParse(paidAmount) ?? 0.0;

    // 免费订单场景：应付金额 <= 0 且 已付金额 >= 0
    if (finalAmt <= 0.0001 && paidAmt >= 0.0) {
      return true;
    }

    // 正常订单场景：已付金额 >= 应付金额 (允许 0.01 浮点计算误差)
    if (finalAmt > 0.0 && paidAmt >= (finalAmt - 0.01)) {
      return true;
    }

    return false;
  }

  // 提取顾客元数据 Map 的便捷 Getter
  Map<String, dynamic>? get customerMetadata {
    for (final a in additions) {
      if (a is Map) {
        final map = Map<String, dynamic>.from(a);
        if (map.containsKey('customer_name') ||
            map.containsKey('customer_phone') ||
            map.containsKey('pickup_time') ||
            map.containsKey('extend_info')) {
          return map;
        }
      }
    }
    return null;
  }

  String? get customerName {
    final meta = customerMetadata;
    return meta?['customer_name']?.toString().trim();
  }

  String? get customerPhone {
    final meta = customerMetadata;
    return meta?['customer_phone']?.toString().trim();
  }

  String? get pickupTime {
    final meta = customerMetadata;
    return meta?['pickup_time']?.toString().trim();
  }

  String? get extendInfo {
    final meta = customerMetadata;
    return meta?['extend_info']?.toString().trim();
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
    List<dynamic> parsedAdditions = _asList(map['additions']);

    // 容错处理：若 additions 字段为空，但后端响应顶级字段中包含顾客信息，则合成为 additions 项
    if (parsedAdditions.isEmpty) {
      final topCustomerName = map['customer_name']?.toString();
      final topCustomerPhone = map['customer_phone']?.toString();
      final topPickupTime = map['pickup_time']?.toString();
      final topExtendInfo = map['extend_info']?.toString();

      if ((topCustomerName != null && topCustomerName.trim().isNotEmpty) ||
          (topCustomerPhone != null && topCustomerPhone.trim().isNotEmpty) ||
          (topPickupTime != null && topPickupTime.trim().isNotEmpty) ||
          (topExtendInfo != null && topExtendInfo.trim().isNotEmpty)) {
        parsedAdditions = [
          {
            if (topCustomerName != null) 'customer_name': topCustomerName,
            if (topCustomerPhone != null) 'customer_phone': topCustomerPhone,
            if (topPickupTime != null) 'pickup_time': topPickupTime,
            if (topExtendInfo != null) 'extend_info': topExtendInfo,
          }
        ];
      }
    }

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
      additions: parsedAdditions,
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

