import 'dart:convert';

// 订单状态枚举
enum OrderStatus {
  pending,      // 待处理
  pendingSync,  // 待同步
  confirmed,    // 已确认
  completed,    // 已完成
  cancelled,    // 已取消
  synced,       // 已同步
}

// 打印状态枚举
enum PrintStatus {
  pending,      // 待打印
  printed,      // 已打印
  printFailed,  // 打印失败
}

// 订单模型
class OrderModel {
  final String id;           // UUID
  final String orderNo;      // 订单编号 (当天第几单)
  final DateTime orderTime;  // 下单时间
  final String items;        // 菜品详情 JSON
  final double totalAmount;  // 总金额
  final double discountAmount; // 折扣金额
  final double taxRate;      // 税率
  final double serviceFee;   // 服务费
  final double cashAmount;   // 现金金额
  final double posAmount;    // POS金额
  final double cashChange;    // 现金找零
  final double voucherAmount; // 券金额
  final OrderStatus orderStatus;  // 订单状态
  final PrintStatus printStatus;  // 打印状态
  final String? errorMessage;     // 错误信息
  final int retryCount;           // 重试次数
  final DateTime? lastRetryTime;  // 最后重试时间
  final DateTime? syncedTime;     // 同步时间
  final DateTime? printedTime;    // 打印时间
  final String? note;         // 订单备注
  final String? type;         // 订单类型（takeaway/dinein）
  final int? remoteOrderId;      // 服务器订单id
  final String? remoteOrderNumber; // 服务器订单号

  // 是否为服务器拉取订单
  bool get isOnlineOrder => remoteOrderId != null;

  OrderModel({
    required this.id,
    required this.orderNo,
    required this.orderTime,
    required this.items,
    required this.totalAmount,
    this.discountAmount = 0.0,
    this.taxRate = 10.0,
    this.serviceFee = 0.0,
    this.cashAmount = 0.0,
    this.posAmount = 0.0,
    this.orderStatus = OrderStatus.pending,
    this.printStatus = PrintStatus.pending,
    this.errorMessage,
    this.retryCount = 0,
    this.lastRetryTime,
    this.syncedTime,
    this.printedTime,
    this.note,
    this.type,
    this.cashChange = 0.0,
    this.voucherAmount = 0.0,
    this.remoteOrderId,
    this.remoteOrderNumber,
  });

  // 从数据库转换
  factory OrderModel.fromMap(Map<String, dynamic> map) {
    return OrderModel(
      id: map['id'],
      orderNo: map['order_no'],
      orderTime: DateTime.parse(map['order_time']),
      items: map['items'],
      totalAmount: map['total_amount'],
      discountAmount: map['discount_amount']?.toDouble() ?? 0.0,
      taxRate: map['tax_rate']?.toDouble() ?? 10.0,
      serviceFee: map['service_fee']?.toDouble() ?? 0.0,
      cashAmount: map['cash_amount']?.toDouble() ?? 0.0,
      posAmount: map['pos_amount']?.toDouble() ?? 0.0,
      orderStatus: OrderStatus.values[map['order_status']],
      printStatus: PrintStatus.values[map['print_status']],
      errorMessage: map['error_message'],
      retryCount: map['retry_count'] ?? 0,
      lastRetryTime: map['last_retry_time'] != null
          ? DateTime.parse(map['last_retry_time'])
          : null,
      syncedTime: map['synced_time'] != null
          ? DateTime.parse(map['synced_time'])
          : null,
      printedTime: map['printed_time'] != null
          ? DateTime.parse(map['printed_time'])
          : null,
      note: map['note'],
      type: map['type'],
      cashChange: map['cash_change']?.toDouble() ?? 0.0,
      voucherAmount: map['voucher_amount']?.toDouble() ?? 0.0,
      remoteOrderId: map['remote_order_id'],
      remoteOrderNumber: map['remote_order_number'],
    );
  }

  // 转换到数据库
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_no': orderNo,
      'order_time': orderTime.toIso8601String(),
      'items': items,
      'total_amount': totalAmount,
      'discount_amount': discountAmount,
      'tax_rate': taxRate,
      'service_fee': serviceFee,
      'cash_amount': cashAmount,
      'pos_amount': posAmount,
      'order_status': orderStatus.index,
      'print_status': printStatus.index,
      'error_message': errorMessage,
      'retry_count': retryCount,
      'last_retry_time': lastRetryTime?.toIso8601String(),
      'synced_time': syncedTime?.toIso8601String(),
      'printed_time': printedTime?.toIso8601String(),
      'note': note,
      'type': type,
      'cash_change': cashChange,
      'voucher_amount': voucherAmount,
      'remote_order_id': remoteOrderId,
      'remote_order_number': remoteOrderNumber,
    };
  }

  // 复制并更新
  OrderModel copyWith({
    String? id,
    String? orderNo,
    DateTime? orderTime,
    String? items,
    double? totalAmount,
    double? discountAmount,
    double? taxRate,
    double? serviceFee,
    double? cashAmount,
    double? posAmount,
    OrderStatus? orderStatus,
    PrintStatus? printStatus,
    String? errorMessage,
    int? retryCount,
    DateTime? lastRetryTime,
    DateTime? syncedTime,
    DateTime? printedTime,
    String? note,
    String? type,
    double? cashChange,
    double? voucherAmount,
    int? remoteOrderId,
    String? remoteOrderNumber,
  }) {
    return OrderModel(
      id: id ?? this.id,
      orderNo: orderNo ?? this.orderNo,
      orderTime: orderTime ?? this.orderTime,
      items: items ?? this.items,
      totalAmount: totalAmount ?? this.totalAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      taxRate: taxRate ?? this.taxRate,
      serviceFee: serviceFee ?? this.serviceFee,
      cashAmount: cashAmount ?? this.cashAmount,
      posAmount: posAmount ?? this.posAmount,
      orderStatus: orderStatus ?? this.orderStatus,
      printStatus: printStatus ?? this.printStatus,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
      lastRetryTime: lastRetryTime ?? this.lastRetryTime,
      syncedTime: syncedTime ?? this.syncedTime,
      printedTime: printedTime ?? this.printedTime,
      note: note ?? this.note,
      type: type ?? this.type,
      cashChange: cashChange ?? this.cashChange,
      voucherAmount: voucherAmount ?? this.voucherAmount,
      remoteOrderId: remoteOrderId ?? this.remoteOrderId,
      remoteOrderNumber: remoteOrderNumber ?? this.remoteOrderNumber,
    );
  }

  // 获取订单项目列表
  List<Map<String, dynamic>> getItemsList() {
    try {
      final List<dynamic> itemsJson = jsonDecode(items);
      return itemsJson.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }
}

// 日志模型
class LogModel {
  final int? id;
  final String orderId;
  final String action;        // 'order', 'sync', 'print'
  final String status;        // 'success', 'error'
  final String? message;
  final DateTime timestamp;

  LogModel({
    this.id,
    required this.orderId,
    required this.action,
    required this.status,
    this.message,
    required this.timestamp,
  });

  factory LogModel.fromMap(Map<String, dynamic> map) {
    return LogModel(
      id: map['id'],
      orderId: map['order_id'],
      action: map['action'],
      status: map['status'],
      message: map['message'],
      timestamp: DateTime.parse(map['timestamp']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_id': orderId,
      'action': action,
      'status': status,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
