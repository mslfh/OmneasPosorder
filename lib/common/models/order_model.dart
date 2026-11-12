import 'dart:convert';

// 订单主状态枚举 (遵循 POS 与 后厨 KDS 统一规范)
enum OrderStatus {
  pending, // 待付款 / 待接单
  confirmed, // 已接单 / 已确认
  preparing, // 制作中 / 备餐中
  readyForPickup, // 待取餐 / 已出餐 (ready_for_pickup)
  completed, // 已完成
  cancelled, // 已取消 (统一双 l 拼写)
  refunded, // 已退款
}

extension OrderStatusX on OrderStatus {
  /// 获取标准的 API 字符串值
  String get apiValue {
    switch (this) {
      case OrderStatus.pending:
        return 'pending';
      case OrderStatus.confirmed:
        return 'confirmed';
      case OrderStatus.preparing:
        return 'preparing';
      case OrderStatus.readyForPickup:
        return 'ready_for_pickup';
      case OrderStatus.completed:
        return 'completed';
      case OrderStatus.cancelled:
        return 'cancelled';
      case OrderStatus.refunded:
        return 'refunded';
    }
  }

  /// 转换与归一化云端/本地状态字符串（含兜底容错处理）
  static OrderStatus parse(dynamic raw) {
    if (raw == null) return OrderStatus.pending;
    if (raw is int) {
      if (raw >= 0 && raw < OrderStatus.values.length) {
        return OrderStatus.values[raw];
      }
      return OrderStatus.pending;
    }
    final s = raw.toString().trim().toLowerCase();
    switch (s) {
      case 'ready':
      case 'ready_for_pickup':
      case 'readyforpickup':
        return OrderStatus.readyForPickup;
      case 'processing':
      case 'in_progress':
      case 'preparing':
        return OrderStatus.preparing;
      case 'paid':
      case 'confirmed':
        return OrderStatus.confirmed;
      case 'canceled':
      case 'cancelled':
        return OrderStatus.cancelled;
      case 'finished':
      case 'completed':
        return OrderStatus.completed;
      case 'refunded':
        return OrderStatus.refunded;
      case 'pending':
      default:
        return OrderStatus.pending;
    }
  }
}

// 终端同步状态枚举 
enum SyncStatus {
  pending, // 待同步
  synced, // 已同步
  syncFailed, // 同步失败 (failed)
  skipped, // 已跳过
}

extension SyncStatusX on SyncStatus {
  /// 获取标准的 API 字符串值 (synced / pending / failed / skipped)
  String get apiValue {
    switch (this) {
      case SyncStatus.pending:
        return 'pending';
      case SyncStatus.synced:
        return 'synced';
      case SyncStatus.syncFailed:
        return 'failed';
      case SyncStatus.skipped:
        return 'skipped';
    }
  }

  static SyncStatus parse(dynamic raw) {
    if (raw == null) return SyncStatus.pending;
    if (raw is int) {
      if (raw >= 0 && raw < SyncStatus.values.length) {
        return SyncStatus.values[raw];
      }
      return SyncStatus.pending;
    }
    final s = raw.toString().trim().toLowerCase();
    switch (s) {
      case 'synced':
      case 'success':
        return SyncStatus.synced;
      case 'failed':
      case 'syncfailed':
      case 'sync_failed':
      case 'error':
        return SyncStatus.syncFailed;
      case 'skipped':
        return SyncStatus.skipped;
      case 'pending':
      default:
        return SyncStatus.pending;
    }
  }
}

// 打印状态枚举 (遵循规范：禁止上传 "success"，统一为 "printed")
enum PrintStatus {
  pending, // 待打印
  printed, // 已打印 (printed)
  printFailed, // 打印失败 (failed)
  skipped, // 跳过打印
}

extension PrintStatusX on PrintStatus {
  /// 获取标准的 API 字符串值 (printed / pending / failed / skipped)
  String get apiValue {
    switch (this) {
      case PrintStatus.pending:
        return 'pending';
      case PrintStatus.printed:
        return 'printed';
      case PrintStatus.printFailed:
        return 'failed';
      case PrintStatus.skipped:
        return 'skipped';
    }
  }

  static PrintStatus parse(dynamic raw) {
    if (raw == null) return PrintStatus.pending;
    if (raw is int) {
      if (raw >= 0 && raw < PrintStatus.values.length) {
        return PrintStatus.values[raw];
      }
      return PrintStatus.pending;
    }
    final s = raw.toString().trim().toLowerCase();
    switch (s) {
      case 'printed':
      case 'success':
        return PrintStatus.printed;
      case 'failed':
      case 'printfailed':
      case 'print_failed':
      case 'error':
        return PrintStatus.printFailed;
      case 'skipped':
        return PrintStatus.skipped;
      case 'pending':
      default:
        return PrintStatus.pending;
    }
  }
}

bool _isTruthy(dynamic value) {
  return value == 1 || value == true || value == '1';
}

int _readIndex(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

OrderStatus _readOrderStatus(Map<String, dynamic> map) {
  final raw = map['order_status'] ?? map['status'];
  if (raw is String) {
    return OrderStatusX.parse(raw);
  }

  final index = _readIndex(raw);
  final hasSyncStatus =
      map.containsKey('sync_status') && map['sync_status'] != null;
  if (hasSyncStatus) {
    switch (index) {
      case 0:
        return OrderStatus.pending;
      case 1:
        return OrderStatus.confirmed;
      case 2:
        return OrderStatus.preparing;
      case 3:
        return OrderStatus.readyForPickup;
      case 4:
        return OrderStatus.completed;
      case 5:
        return OrderStatus.cancelled;
      case 6:
        return OrderStatus.refunded;
    }
  }

  final isOnlineOrder = _isTruthy(map['is_online_order']) ||
      map['remote_order_id'] != null ||
      (map['remote_order_number']?.toString().isNotEmpty ?? false);

  switch (index) {
    case 0:
      return OrderStatus.pending;
    case 1:
      return OrderStatus.completed;
    case 2:
      return OrderStatus.confirmed;
    case 3:
      return OrderStatus.completed;
    case 4:
      return OrderStatus.cancelled;
    case 5:
      return isOnlineOrder ? OrderStatus.confirmed : OrderStatus.completed;
    default:
      return OrderStatus.pending;
  }
}

SyncStatus _readSyncStatus(Map<String, dynamic> map) {
  final raw = map['sync_status'];
  if (raw is String) {
    return SyncStatusX.parse(raw);
  }

  if (raw != null) {
    switch (_readIndex(raw)) {
      case 0:
        return SyncStatus.pending;
      case 1:
        return SyncStatus.synced;
      case 2:
        return SyncStatus.syncFailed;
      case 3:
        return SyncStatus.skipped;
      default:
        return SyncStatus.pending;
    }
  }

  final legacyOrderStatus = _readIndex(map['order_status']);
  if (legacyOrderStatus == 5) {
    return SyncStatus.synced;
  }
  if (_isTruthy(map['is_online_order']) ||
      map['remote_order_id'] != null ||
      (map['remote_order_number']?.toString().isNotEmpty ?? false)) {
    return SyncStatus.synced;
  }

  return SyncStatus.pending;
}

// 订单模型
class OrderModel {
  final String id; // UUID
  final String orderNo; // 订单编号 (当天第几单)
  final DateTime orderTime; // 订单预计时间 (Expected Time)
  final DateTime createdAt; // 下单时间 (Creation Time)
  final String items; // 菜品详情 JSON
  final double totalAmount; // 总金额
  final double discountAmount; // 折扣金额
  final double taxRate; // 税率
  final double serviceFee; // 服务费
  final double cashAmount; // 现金金额
  final double posAmount; // POS金额
  final double cashChange; // 现金找零
  final double voucherAmount; // 券金额
  final OrderStatus orderStatus; // 订单状态
  final SyncStatus syncStatus; // 同步状态
  final PrintStatus printStatus; // 打印状态
  final String? errorMessage; // 错误信息
  final int retryCount; // 重试次数
  final DateTime? lastRetryTime; // 最后重试时间
  final DateTime? syncedTime; // 同步时间
  final DateTime? printedTime; // 打印时间
  final String? note; // 订单备注
  final String? type; // 订单类型（takeaway/dinein）
  final int? remoteOrderId; // 服务器订单id
  final String? remoteOrderNumber; // 服务器订单号
  final bool isOnlineOrder; // 是否为服务器拉取订单

  OrderModel({
    required this.id,
    required this.orderNo,
    required this.orderTime,
    required this.createdAt,
    required this.items,
    required this.totalAmount,
    this.discountAmount = 0.0,
    this.taxRate = 10.0,
    this.serviceFee = 0.0,
    this.cashAmount = 0.0,
    this.posAmount = 0.0,
    this.orderStatus = OrderStatus.pending,
    this.syncStatus = SyncStatus.pending,
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
    this.isOnlineOrder = false,
  });

  // 从数据库转换
  factory OrderModel.fromMap(Map<String, dynamic> map) {
    return OrderModel(
      id: map['id'],
      orderNo: map['order_no'],
      orderTime: DateTime.parse(map['order_time']),
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.parse(map['order_time']),
      items: map['items'],
      totalAmount: map['total_amount'],
      discountAmount: map['discount_amount']?.toDouble() ?? 0.0,
      taxRate: map['tax_rate']?.toDouble() ?? 10.0,
      serviceFee: map['service_fee']?.toDouble() ?? 0.0,
      cashAmount: map['cash_amount']?.toDouble() ?? 0.0,
      posAmount: map['pos_amount']?.toDouble() ?? 0.0,
      orderStatus: _readOrderStatus(map),
      syncStatus: _readSyncStatus(map),
      printStatus: PrintStatusX.parse(map['print_status']),
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
      isOnlineOrder:
          map['is_online_order'] == 1 || map['is_online_order'] == true,
    );
  }

  /// 是否已支付（对比已收款项总额与应收总额）
  bool get isPaid {
    if (orderStatus == OrderStatus.completed) return true;

    final paidTotal = cashAmount + posAmount + voucherAmount;
    final total = totalAmount;

    // 免费订单场景
    if (total <= 0.0001 && paidTotal >= 0.0) {
      return true;
    }

    // 正常订单场景：已付金额 >= 应付金额 (允许 0.01 浮点计算误差)
    if (total > 0.0 && paidTotal >= (total - 0.01)) {
      return true;
    }

    return false;
  }

  /// 是否为堂食类型
  bool get isDineIn {
    if (isTableOrder) return true;
    final rawType = type?.toLowerCase() ?? '';
    return rawType.contains('dine') || rawType.contains('table');
  }

  /// 归一化为标准的后端 API 就餐类型字符串 ("dine_in" 或 "takeaway")
  String get normalizedApiType {
    return isDineIn ? 'dine_in' : 'takeaway';
  }

  /// 展现订单来源 / 场景 (优先处理 isOnlineOrder)
  String get displayOrderSource {
    if (isOnlineOrder) {
      return 'ONLINE (在线网单)';
    }
    if (isTableOrder) {
      return tableName != null ? '堂食坐台 ($tableName)' : '堂食坐台';
    }
    return isDineIn ? 'Dine In (堂食)' : 'Takeaway (外带/自提)';
  }

  /// 简短展现订单来源 (适用于列表 Chip 标签)
  String get displayOrderSourceShort {
    if (isOnlineOrder) {
      return 'ONLINE';
    }
    if (isTableOrder) {
      return tableName ?? '坐台';
    }
    return isDineIn ? 'DINE IN' : 'TAKEAWAY';
  }

  /// 是否为堂食坐台单
  bool get isTableOrder =>
      (type != null && (type == 'table' || type == 'dinein_table' || type == 'dinein')) &&
      (note?.contains('桌台') == true || note?.contains('Table') == true);

  /// 提取关联的桌台名称
  String? get tableName {
    if (note != null) {
      final reg = RegExp(r'\[(?:桌台|Table):\s*([^\]]+)\]');
      final match = reg.firstMatch(note!);
      if (match != null && match.groupCount >= 1) {
        return match.group(1);
      }
    }
    return null;
  }

  // 转换到数据库
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_no': orderNo,
      'order_time': orderTime.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'items': items,
      'total_amount': totalAmount,
      'discount_amount': discountAmount,
      'tax_rate': taxRate,
      'service_fee': serviceFee,
      'cash_amount': cashAmount,
      'pos_amount': posAmount,
      'order_status': orderStatus.index,
      'sync_status': syncStatus.index,
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
      'is_online_order': isOnlineOrder ? 1 : 0,
    };
  }

  // 复制并更新
  OrderModel copyWith({
    String? id,
    String? orderNo,
    DateTime? orderTime,
    DateTime? createdAt,
    String? items,
    double? totalAmount,
    double? discountAmount,
    double? taxRate,
    double? serviceFee,
    double? cashAmount,
    double? posAmount,
    OrderStatus? orderStatus,
    SyncStatus? syncStatus,
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
    bool? isOnlineOrder,
  }) {
    return OrderModel(
      id: id ?? this.id,
      orderNo: orderNo ?? this.orderNo,
      orderTime: orderTime ?? this.orderTime,
      createdAt: createdAt ?? this.createdAt,
      items: items ?? this.items,
      totalAmount: totalAmount ?? this.totalAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      taxRate: taxRate ?? this.taxRate,
      serviceFee: serviceFee ?? this.serviceFee,
      cashAmount: cashAmount ?? this.cashAmount,
      posAmount: posAmount ?? this.posAmount,
      orderStatus: orderStatus ?? this.orderStatus,
      syncStatus: syncStatus ?? this.syncStatus,
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
      isOnlineOrder: isOnlineOrder ?? this.isOnlineOrder,
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
  final String action; // 'order', 'sync', 'print'
  final String status; // 'success', 'error'
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
