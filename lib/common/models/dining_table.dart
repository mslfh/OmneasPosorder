import 'dart:convert';

/// 桌台模型类
class DiningTable {
  final int id;
  final String name;
  final String? code;
  final String? area;
  final int capacity;
  final int minCapacity;
  final String status; // available | occupied | reserved | disabled
  final bool isActive;
  final bool isReserved;
  final bool canReserve;
  final int reservationsCount;
  final int sortOrder;
  final String? qrCode;
  final String? description;
  final DiningTableReservation? currentReservation;
  final List<DiningTableReservation>? todayReservations;
  final List<DiningTableReservation>? reservations;
  final Map<String, dynamic>? activeOrder;

  DiningTable({
    required this.id,
    required this.name,
    this.code,
    this.area,
    this.capacity = 0,
    this.minCapacity = 0,
    this.status = 'available',
    this.isActive = true,
    this.isReserved = false,
    this.canReserve = true,
    this.reservationsCount = 0,
    this.sortOrder = 0,
    this.qrCode,
    this.description,
    this.currentReservation,
    this.todayReservations,
    this.reservations,
    this.activeOrder,
  });

  bool get hasActiveOrder {
    if (activeOrder == null) return false;
    if (activeOrder!['items'] is List && (activeOrder!['items'] as List).isNotEmpty) {
      return true;
    }
    if (activeOrder!['active_orders'] is Map) {
      final map = activeOrder!['active_orders'] as Map;
      for (var val in map.values) {
        if (val is Map && val['items'] is List && (val['items'] as List).isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  bool get isOccupied =>
      status.toLowerCase() == 'occupied' ||
      status.toLowerCase() == 'seated' ||
      hasActiveOrder;

  bool get isAvailable => !isOccupied && status.toLowerCase() == 'available';

  bool get isDisabled => status.toLowerCase() == 'disabled';

  /// 提取特定预约 ID 的落地暂存菜品
  List<Map<String, dynamic>> getItemsForReservation(int? reservationId) {
    if (activeOrder != null && activeOrder!['active_orders'] is Map) {
      final ordersMap = activeOrder!['active_orders'] as Map;
      final key = reservationId != null ? reservationId.toString() : 'walkin';
      if (ordersMap[key] is Map && ordersMap[key]['items'] is List) {
        return (ordersMap[key]['items'] as List)
            .map((i) => i is Map<String, dynamic> ? i : Map<String, dynamic>.from(i as Map))
            .toList();
      }
    }
    if (activeOrder != null && activeOrder!['items'] is List) {
      return (activeOrder!['items'] as List)
          .map((i) => i is Map<String, dynamic> ? i : Map<String, dynamic>.from(i as Map))
          .toList();
    }
    return [];
  }

  /// 判断特定预约单是否已在本地开台入座
  bool isReservationSeated(int reservationId) {
    if (activeOrder != null && activeOrder!['active_orders'] is Map) {
      final ordersMap = activeOrder!['active_orders'] as Map;
      final key = reservationId.toString();
      if (ordersMap[key] is Map) {
        final resObj = ordersMap[key] as Map;
        return resObj['status'] == 'seated' ||
            (resObj['items'] is List && (resObj['items'] as List).isNotEmpty);
      }
    }
    return false;
  }

  bool get hasUnservedReservation {
    final list = todayReservations ??
        (currentReservation != null ? [currentReservation!] : (reservations ?? []));
    return list.any((r) =>
        r.status?.toLowerCase() != 'seated' &&
        r.status?.toLowerCase() != 'completed' &&
        r.status?.toLowerCase() != 'cancelled');
  }

  bool get hasReservation =>
      !isOccupied &&
      (isReserved ||
          status.toLowerCase() == 'reserved' ||
          hasUnservedReservation);

  factory DiningTable.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? actOrder;
    if (json['active_order'] != null && json['active_order'] is Map) {
      actOrder = Map<String, dynamic>.from(json['active_order']);
    }

    DiningTableReservation? curRes;
    if (json['current_reservation'] != null && json['current_reservation'] is Map) {
      curRes = DiningTableReservation.fromJson(
        Map<String, dynamic>.from(json['current_reservation']),
      );
    }

    List<DiningTableReservation>? todayRes;
    if (json['today_reservations'] != null && json['today_reservations'] is List) {
      todayRes = (json['today_reservations'] as List).map((r) {
        final resMap = r is Map<String, dynamic>
            ? Map<String, dynamic>.from(r)
            : Map<String, dynamic>.from(r as Map);
        final resId = resMap['id']?.toString();
        if (actOrder != null &&
            actOrder['active_orders'] is Map &&
            resId != null &&
            actOrder['active_orders'][resId] != null) {
          resMap['status'] = 'seated';
        }
        return DiningTableReservation.fromJson(resMap);
      }).toList();
    }

    List<DiningTableReservation>? resList = todayRes;
    if (json['reservations'] != null && json['reservations'] is List) {
      resList = (json['reservations'] as List).map((r) {
        final resMap = r is Map<String, dynamic>
            ? Map<String, dynamic>.from(r)
            : Map<String, dynamic>.from(r as Map);
        final resId = resMap['id']?.toString();
        if (actOrder != null &&
            actOrder['active_orders'] is Map &&
            resId != null &&
            actOrder['active_orders'][resId] != null) {
          resMap['status'] = 'seated';
        }
        return DiningTableReservation.fromJson(resMap);
      }).toList();
    }

    final isResBool = json['is_reserved'] == true ||
        json['is_reserved'] == 1 ||
        curRes != null ||
        json['status']?.toString().toLowerCase() == 'reserved';

    return DiningTable(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString(),
      area: json['area']?.toString(),
      capacity: json['capacity'] is int
          ? json['capacity']
          : int.tryParse(json['capacity']?.toString() ?? '0') ?? 0,
      minCapacity: json['min_capacity'] is int
          ? json['min_capacity']
          : int.tryParse(json['min_capacity']?.toString() ?? '0') ?? 0,
      status: json['status']?.toString() ?? 'available',
      isActive: json['is_active'] != false && json['is_active'] != 0,
      isReserved: isResBool,
      canReserve: json['can_reserve'] != false,
      reservationsCount: json['reservations_count'] is int
          ? json['reservations_count']
          : (resList?.length ?? (curRes != null ? 1 : 0)),
      sortOrder: json['sort_order'] is int
          ? json['sort_order']
          : int.tryParse(json['sort_order']?.toString() ?? '0') ?? 0,
      qrCode: json['qr_code']?.toString(),
      description: json['description']?.toString(),
      currentReservation: curRes,
      todayReservations: todayRes,
      reservations: resList,
      activeOrder: actOrder,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'area': area,
      'capacity': capacity,
      'min_capacity': minCapacity,
      'status': status,
      'is_active': isActive,
      'is_reserved': isReserved,
      'can_reserve': canReserve,
      'reservations_count': reservationsCount,
      'sort_order': sortOrder,
      'qr_code': qrCode,
      'description': description,
      'current_reservation': currentReservation?.toJson(),
      'today_reservations': todayReservations?.map((r) => r.toJson()).toList(),
      'reservations': reservations?.map((r) => r.toJson()).toList(),
      'active_order': activeOrder,
    };
  }

  factory DiningTable.fromDbMap(Map<String, dynamic> map) {
    Map<String, dynamic>? actOrder;
    if (map['active_order_json'] != null &&
        map['active_order_json'].toString().isNotEmpty) {
      try {
        final decoded = jsonDecode(map['active_order_json']);
        if (decoded is Map) {
          actOrder = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    DiningTableReservation? curRes;
    List<DiningTableReservation>? resList;

    if (map['reservations_json'] != null &&
        map['reservations_json'].toString().isNotEmpty) {
      try {
        final decoded = jsonDecode(map['reservations_json']);
        if (decoded is List && decoded.isNotEmpty) {
          resList = decoded.map((r) {
            final resMap = r is Map<String, dynamic>
                ? Map<String, dynamic>.from(r)
                : Map<String, dynamic>.from(r as Map);
            final resId = resMap['id']?.toString();
            if (actOrder != null &&
                actOrder['active_orders'] is Map &&
                resId != null &&
                actOrder['active_orders'][resId] != null) {
              resMap['status'] = 'seated';
            }
            return DiningTableReservation.fromJson(resMap);
          }).toList();
          curRes = resList.first;
        }
      } catch (_) {}
    }

    final isRes = map['is_reserved'] == 1 || curRes != null || map['status'] == 'reserved';

    return DiningTable(
      id: map['id'] is int
          ? map['id']
          : int.tryParse(map['id']?.toString() ?? '0') ?? 0,
      name: map['name']?.toString() ?? '',
      code: map['code']?.toString(),
      area: map['area']?.toString(),
      capacity: map['capacity'] is int ? map['capacity'] : 0,
      minCapacity: map['min_capacity'] is int ? map['min_capacity'] : 0,
      status: map['status']?.toString() ?? 'available',
      isActive: map['is_active'] == 1,
      isReserved: isRes,
      canReserve: map['can_reserve'] == 1,
      reservationsCount: map['reservations_count'] is int
          ? map['reservations_count']
          : (resList?.length ?? 0),
      sortOrder: map['sort_order'] is int ? map['sort_order'] : 0,
      qrCode: map['qr_code']?.toString(),
      description: map['description']?.toString(),
      currentReservation: curRes,
      todayReservations: resList,
      reservations: resList,
      activeOrder: actOrder,
    );
  }

  Map<String, dynamic> toDbMap() {
    List<Map<String, dynamic>> resJsonList = [];
    if (currentReservation != null) {
      resJsonList.add(currentReservation!.toJson());
    }
    if (todayReservations != null) {
      for (var r in todayReservations!) {
        if (currentReservation == null || r.id != currentReservation!.id) {
          resJsonList.add(r.toJson());
        }
      }
    } else if (reservations != null) {
      for (var r in reservations!) {
        if (currentReservation == null || r.id != currentReservation!.id) {
          resJsonList.add(r.toJson());
        }
      }
    }

    return {
      'id': id,
      'name': name,
      'code': code,
      'area': area,
      'capacity': capacity,
      'min_capacity': minCapacity,
      'status': status,
      'is_active': isActive ? 1 : 0,
      'is_reserved': isReserved ? 1 : 0,
      'reservations_count': reservationsCount,
      'sort_order': sortOrder,
      'qr_code': qrCode,
      'description': description,
      'reservations_json':
          resJsonList.isNotEmpty ? jsonEncode(resJsonList) : null,
      'active_order_json':
          activeOrder != null ? jsonEncode(activeOrder) : null,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  DiningTable copyWith({
    int? id,
    String? name,
    String? code,
    String? area,
    int? capacity,
    int? minCapacity,
    String? status,
    bool? isActive,
    bool? isReserved,
    bool? canReserve,
    int? reservationsCount,
    int? sortOrder,
    String? qrCode,
    String? description,
    DiningTableReservation? currentReservation,
    List<DiningTableReservation>? todayReservations,
    List<DiningTableReservation>? reservations,
    Map<String, dynamic>? activeOrder,
  }) {
    return DiningTable(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      area: area ?? this.area,
      capacity: capacity ?? this.capacity,
      minCapacity: minCapacity ?? this.minCapacity,
      status: status ?? this.status,
      isActive: isActive ?? this.isActive,
      isReserved: isReserved ?? this.isReserved,
      canReserve: canReserve ?? this.canReserve,
      reservationsCount: reservationsCount ?? this.reservationsCount,
      sortOrder: sortOrder ?? this.sortOrder,
      qrCode: qrCode ?? this.qrCode,
      description: description ?? this.description,
      currentReservation: currentReservation ?? this.currentReservation,
      todayReservations: todayReservations ?? this.todayReservations,
      reservations: reservations ?? this.reservations,
      activeOrder: activeOrder ?? this.activeOrder,
    );
  }
}

/// 桌台预约模型
class DiningTableReservation {
  final int id;
  final String? customerName;
  final String? customerPhone;
  final String? reservationTime;
  final int? guestCount;
  final String? status; // confirmed | seated | completed | cancelled
  final bool hasPreOrder;
  final DiningTablePreorder? preorder;

  DiningTableReservation({
    required this.id,
    this.customerName,
    this.customerPhone,
    this.reservationTime,
    this.guestCount,
    this.status,
    this.hasPreOrder = false,
    this.preorder,
  });

  factory DiningTableReservation.fromJson(Map<String, dynamic> json) {
    DiningTablePreorder? pre;
    final preRaw = json['pre_order'] ?? json['preorder'];
    if (preRaw != null && preRaw is Map) {
      pre = DiningTablePreorder.fromJson(
        Map<String, dynamic>.from(preRaw),
      );
    }

    final hasPreBool = json['has_pre_order'] == true ||
        json['has_preorder'] == true ||
        pre != null;

    return DiningTableReservation(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      customerName: json['customer_name']?.toString() ?? json['name']?.toString(),
      customerPhone: json['customer_phone']?.toString() ?? json['phone']?.toString(),
      reservationTime: json['reservation_time']?.toString() ?? json['time']?.toString(),
      guestCount: json['guests_count'] is int
          ? json['guests_count']
          : (json['guest_count'] is int
              ? json['guest_count']
              : int.tryParse(json['guests_count']?.toString() ?? json['guest_count']?.toString() ?? '')),
      status: json['status']?.toString(),
      hasPreOrder: hasPreBool,
      preorder: pre,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'reservation_time': reservationTime,
      'guests_count': guestCount,
      'status': status,
      'has_pre_order': hasPreOrder,
      'pre_order': preorder?.toJson(),
    };
  }
}

/// 预约预点单模型
class DiningTablePreorder {
  final String? orderNumber;
  final double? finalAmount;
  final List<Map<String, dynamic>> items;

  DiningTablePreorder({
    this.orderNumber,
    this.finalAmount,
    required this.items,
  });

  factory DiningTablePreorder.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> itemList = [];
    if (json['items'] != null && json['items'] is List) {
      itemList = (json['items'] as List).map((i) {
        final map = i is Map<String, dynamic> ? i : Map<String, dynamic>.from(i as Map);
        return {
          'product_id': map['product_id'] ?? map['id'],
          'name': map['product_title'] ?? map['name'] ?? map['title'],
          'price': map['unit_price'] ?? map['price'] ?? map['selling_price'],
          'quantity': map['quantity'] ?? 1,
          'options': map['customization'] ?? map['options'] ?? [],
        };
      }).toList();
    }

    return DiningTablePreorder(
      orderNumber: json['order_number']?.toString() ?? json['order_no']?.toString(),
      finalAmount: json['final_amount'] is num
          ? (json['final_amount'] as num).toDouble()
          : double.tryParse(json['final_amount']?.toString() ?? ''),
      items: itemList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'order_number': orderNumber,
      'final_amount': finalAmount,
      'items': items,
    };
  }
}
