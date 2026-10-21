import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../models/dining_table.dart';
import 'api_service.dart';
import 'database_service.dart';

class DiningTableService {
  static final Logger _logger = Logger();
  final ApiService _apiService = ApiService();
  final DatabaseService _databaseService = DatabaseService();

  static final DiningTableService _instance = DiningTableService._internal();
  factory DiningTableService() => _instance;
  DiningTableService._internal();

  /// 获取所有桌台状态信息（优先调 API GET /api/dining-tables/active）
  Future<List<DiningTable>> getTables({
    bool forceRefresh = false,
    String? date,
  }) async {
    // 1. 优先读取本地数据库数据
    if (!forceRefresh) {
      final localTables = await _databaseService.getDiningTables();
      if (localTables.isNotEmpty) {
        _logger.i('使用本地缓存桌台数据 (${localTables.length} 个)');
        return localTables;
      }
    }

    // 2. 调 API 获取最新桌台数据 (轻量纯净桌态看板 API)
    try {
      final queryDate = date ??
          DateTime.now().toIso8601String().split('T').first; // yyyy-MM-dd

      Response response;
      try {
        response = await _apiService.get('dining-tables/active');
      } catch (_) {
        try {
          response = await _apiService.get(
            'dining-tables/terminal-tables',
            params: {'date': queryDate},
          );
        } catch (_) {
          response = await _apiService.get(
            'terminal/dining-tables',
            params: {'date': queryDate},
          );
        }
      }

      final List<DiningTable> fetchedTables = [];
      if (response.data != null) {
        dynamic rawData = response.data;
        if (rawData is Map && rawData.containsKey('data')) {
          rawData = rawData['data'];
        }
        if (rawData is Map && rawData.containsKey('tables')) {
          rawData = rawData['tables'];
        }

        if (rawData is List) {
          for (final item in rawData) {
            if (item is Map<String, dynamic>) {
              fetchedTables.add(DiningTable.fromJson(item));
            } else if (item is Map) {
              fetchedTables.add(
                DiningTable.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
      }

      if (fetchedTables.isNotEmpty) {
        // 存入本地数据库并读取和本地暂存合并后的最新数据
        await _databaseService.saveDiningTables(fetchedTables);
        _logger.i('从服务端更新桌台数据成功 (${fetchedTables.length} 个)');
        return await _databaseService.getDiningTables();
      }
    } catch (e) {
      _logger.e('获取远程桌台数据失败: $e');
    }

    // 发生异常且需要刷新时，退回读取本地数据
    return await _databaseService.getDiningTables();
  }

  /// 获取接待/预约列表 (优先 GET /api/table-reservations/terminal)
  Future<TodayReservationsData?> getTodayReservations({String? date}) async {
    try {
      Response response;
      final queryParams = <String, dynamic>{};
      if (date != null && date.isNotEmpty) {
        queryParams['date'] = date;
      }

      try {
        response = await _apiService.get(
          'table-reservations/terminal',
          params: queryParams,
        );
      } catch (_) {
        try {
          response = await _apiService.get(
            'table-reservations/today',
            params: queryParams,
          );
        } catch (_) {
          response = await _apiService.get(
            'table-reservations',
            params: {'date': date ?? 'today', 'status': 'confirmed'},
          );
        }
      }

      if (response.data != null && response.data is Map) {
        final resMap = Map<String, dynamic>.from(response.data);
        final dataObj = resMap['data'] ?? resMap;
        if (dataObj is Map<String, dynamic>) {
          return TodayReservationsData.fromJson(dataObj);
        } else if (dataObj is Map) {
          return TodayReservationsData.fromJson(
            Map<String, dynamic>.from(dataObj),
          );
        }
      }
    } catch (e) {
      _logger.e('获取预约数据失败 ($date): $e');
    }
    return null;
  }

  /// 顾客到店一键入座指定桌台
  /// 接口: POST /api/table-reservations/{reservation_id}/seat  Body: {"table_id": 1}
  /// 降级: POST /api/dining-tables/{table_id}/seat  Body: {"reservation_id": 101}
  Future<bool> seatReservation({
    required int reservationId,
    required int tableId,
    String? notes,
  }) async {
    try {
      final payload = <String, dynamic>{
        'table_id': tableId,
        'reservation_id': reservationId,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      };

      Response response;
      try {
        response = await _apiService.post(
          'table-reservations/$reservationId/seat',
          data: {'table_id': tableId},
        );
      } catch (_) {
        try {
          response = await _apiService.post(
            'dining-tables/$tableId/seat',
            data: {'reservation_id': reservationId},
          );
        } catch (_) {
          response = await _apiService.post(
            'dining-tables/$tableId/occupy',
            data: payload,
          );
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.i('预约 $reservationId 成功入座桌台 $tableId');
        await _databaseService.updateDiningTableStatus(tableId, 'occupied');
        return true;
      }
    } catch (e) {
      _logger.e('预约入座 API 失败 ($reservationId -> $tableId): $e');
    }

    // 即使 API 无法连接，依然更新本地 DB 为 occupied 保证流畅体验
    await _databaseService.updateDiningTableStatus(tableId, 'occupied');
    return false;
  }

  /// 获取桌台预约信息与预选菜品
  Future<Map<String, dynamic>?> getReservationAndPreorder(
    int tableId, {
    String? date,
  }) async {
    try {
      final queryDate = date ?? DateTime.now().toIso8601String().split('T').first;
      final response = await _apiService.get(
        'terminal/dining-tables/$tableId/reservation-and-preorder',
        params: {'date': queryDate},
      );

      if (response.data != null && response.data is Map) {
        final resMap = Map<String, dynamic>.from(response.data);
        if (resMap['data'] != null && resMap['data'] is Map) {
          return Map<String, dynamic>.from(resMap['data']);
        }
        return resMap;
      }
    } catch (e) {
      _logger.e('获取桌台 $tableId 预约和预点单失败: $e');
    }
    return null;
  }

  /// 终端占用/开台桌台 API (POST /api/dining-tables/{id}/occupy)
  Future<bool> occupyTable(
    int tableId, {
    int? reservationId,
    bool force = true,
    String? notes,
  }) async {
    try {
      final payload = <String, dynamic>{
        'table_id': tableId,
        if (reservationId != null) 'reservation_id': reservationId,
        'force': force,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      };

      Response response;
      try {
        response = await _apiService.post(
          'dining-tables/$tableId/occupy',
          data: payload,
        );
      } catch (_) {
        try {
          response = await _apiService.post(
            'dining-tables/$tableId/seat',
            data: payload,
          );
        } catch (_) {
          try {
            response = await _apiService.post(
              'dining-tables/occupy',
              data: payload,
            );
          } catch (_) {
            response = await _apiService.post(
              'terminal/dining-tables/$tableId/occupy',
              data: payload,
            );
          }
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.i('桌台已在服务器成功占用 (occupied): $tableId (预约: $reservationId)');
        await _databaseService.updateDiningTableStatus(tableId, 'occupied');
        return true;
      }
    } catch (e) {
      _logger.e('调用占用桌台 API 失败 ($tableId): $e');
    }
    // 即使 API 网络异常，本地依然更新为 occupied 保证流畅开台
    await _databaseService.updateDiningTableStatus(tableId, 'occupied');
    return false;
  }

  /// 终端结账释放桌台 API (POST /api/dining-tables/{id}/checkout)
  Future<bool> releaseTableOnCheckout(
    int tableId, {
    int? reservationId,
  }) async {
    try {
      final payload = <String, dynamic>{
        'table_id': tableId,
        if (reservationId != null) 'reservation_id': reservationId,
      };

      Response response;
      try {
        response = await _apiService.post(
          'dining-tables/$tableId/checkout',
          data: payload,
        );
      } catch (_) {
        try {
          response = await _apiService.post(
            'dining-tables/checkout',
            data: payload,
          );
        } catch (_) {
          response = await _apiService.post(
            'terminal/dining-tables/$tableId/checkout',
            data: payload,
          );
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.i('桌台已在服务器成功结账释放 (checkout/available): $tableId (预约: $reservationId)');
        await clearLocalTableItems(tableId, reservationId: reservationId);
        return true;
      }
    } catch (e) {
      _logger.e('调用结账释放桌台 API 失败 ($tableId): $e');
    }
    // 即使 API 网络异常，依然清理本地缓存恢复可用
    await clearLocalTableItems(tableId, reservationId: reservationId);
    return false;
  }

  /// 开台点餐并生成坐台单
  Future<Map<String, dynamic>?> createTableOrder(
    int tableId, {
    int? guestCount,
    String? notes,
    bool importPreorder = false,
    String staffName = 'Terminal-01',
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final payload = <String, dynamic>{
        'guest_count': guestCount ?? 1,
        'notes': notes ?? '',
        'import_preorder': importPreorder,
        'staff_name': staffName,
        'items': items,
      };

      final response = await _apiService.post(
        'terminal/dining-tables/$tableId/orders',
        data: payload,
      );

      if (response.data != null && response.data is Map) {
        final resMap = Map<String, dynamic>.from(response.data);
        await _databaseService.updateDiningTableStatus(
          tableId,
          'occupied',
          activeOrderJson: jsonEncode(resMap['data'] ?? resMap),
        );
        if (resMap['data'] != null && resMap['data'] is Map) {
          return Map<String, dynamic>.from(resMap['data']);
        }
        return resMap;
      }
    } catch (e) {
      _logger.e('生成桌台 $tableId 坐台单 API 异常, 尝试保存本地快照: $e');
      final localActiveOrder = {
        'id': 'LOCAL-$tableId',
        'order_no': 'B-LOCAL',
        'items': items,
      };
      await _databaseService.updateDiningTableStatus(
        tableId,
        'occupied',
        activeOrderJson: jsonEncode(localActiveOrder),
      );
      return localActiveOrder;
    }
    return null;
  }

  /// 追加菜品 / 修改坐台单菜品（加菜）
  Future<Map<String, dynamic>?> updateTableOrderItems(
    int tableId, {
    required List<Map<String, dynamic>> items,
    String mode = 'append',
    String? notes,
    String staffName = 'Terminal-01',
    int? orderId,
  }) async {
    try {
      final payload = <String, dynamic>{
        'mode': mode,
        'staff_name': staffName,
        'notes': notes ?? '',
        'items': items,
      };

      final path = orderId != null
          ? 'terminal/orders/$orderId/table-items'
          : 'terminal/dining-tables/$tableId/order-items';

      final response = await _apiService.put(path, data: payload);

      if (response.data != null && response.data is Map) {
        final resMap = Map<String, dynamic>.from(response.data);
        await _databaseService.updateDiningTableStatus(
          tableId,
          'occupied',
          activeOrderJson: jsonEncode(resMap['data'] ?? resMap),
        );
        if (resMap['data'] != null && resMap['data'] is Map) {
          return Map<String, dynamic>.from(resMap['data']);
        }
        return resMap;
      }
    } catch (e) {
      _logger.e('桌台 $tableId 追加菜品 API 异常, 尝试保存本地快照: $e');
      final localActiveOrder = {
        'id': orderId ?? 'LOCAL-$tableId',
        'order_no': 'B-LOCAL',
        'items': items,
      };
      await _databaseService.updateDiningTableStatus(
        tableId,
        'occupied',
        activeOrderJson: jsonEncode(localActiveOrder),
      );
      return localActiveOrder;
    }
    return null;
  }

  /// 彻底清理 SQLite 本地所有桌台暂存菜品与状态缓存
  Future<void> clearAllTableCaches() async {
    await _databaseService.clearDiningTableItemsCache();
  }

  /// 暂存/更新指定桌台/预约单的已点菜品数据至本地（支持按预约 ID 独立维护）
  Future<void> saveLocalTableItems(
    int tableId,
    List<Map<String, dynamic>> items, {
    int? reservationId,
    double totalAmount = 0.0,
  }) async {
    final localTables = await _databaseService.getDiningTables();
    final matchingTable = localTables.where((t) => t.id == tableId).toList();

    Map<String, dynamic> mainActiveOrder = {
      'id': reservationId != null ? 'RES-$reservationId' : 'LOCAL-$tableId',
      'table_id': tableId,
      'reservation_id': reservationId,
      'order_no': reservationId != null ? 'RES-$reservationId' : 'TABLE-$tableId',
      'total_amount': totalAmount,
      'items': items,
    };

    Map<String, dynamic> activeOrdersMap = {};
    String? updatedReservationsJson;

    if (matchingTable.isNotEmpty) {
      final t = matchingTable.first;
      if (t.activeOrder != null && t.activeOrder!['active_orders'] is Map) {
        activeOrdersMap = Map<String, dynamic>.from(t.activeOrder!['active_orders']);
      }

      if (reservationId != null && t.todayReservations != null) {
        final updatedRes = t.todayReservations!.map((r) {
          if (r.id == reservationId) {
            return DiningTableReservation(
              id: r.id,
              customerName: r.customerName,
              customerPhone: r.customerPhone,
              reservationTime: r.reservationTime,
              guestCount: r.guestCount,
              status: 'seated', // 更新该预约状态为 seated
              hasPreOrder: r.hasPreOrder,
              preorder: r.preorder,
            );
          }
          return r;
        }).toList();
        updatedReservationsJson = jsonEncode(updatedRes.map((r) => r.toJson()).toList());
      }
    }

    if (reservationId != null) {
      activeOrdersMap[reservationId.toString()] = {
        'id': 'RES-$reservationId',
        'reservation_id': reservationId,
        'order_no': 'RES-$reservationId',
        'status': 'seated',
        'total_amount': totalAmount,
        'items': items,
      };
    }
    mainActiveOrder['active_orders'] = activeOrdersMap;

    // 只要有任意一个活跃订单存在菜品，即置为 occupied 状态
    final bool hasAnyItems = items.isNotEmpty || activeOrdersMap.values.any((val) {
      return val is Map && val['items'] is List && (val['items'] as List).isNotEmpty;
    });

    final status = hasAnyItems ? 'occupied' : 'available';
    await _databaseService.updateDiningTableStatus(
      tableId,
      status,
      activeOrderJson: hasAnyItems ? jsonEncode(mainActiveOrder) : '',
      reservationsJson: updatedReservationsJson,
    );
    _logger.i('已暂存桌台 $tableId (预约: $reservationId) 本地菜品数据 (${items.length}项)');
  }

  /// 辅助方法：提取桌台针对特定预约单的已点菜品数据
  static List<Map<String, dynamic>> extractItemsForReservation(
    DiningTable table,
    int? reservationId,
  ) {
    if (table.activeOrder != null) {
      final activeOrder = table.activeOrder!;
      if (reservationId != null && activeOrder['active_orders'] is Map) {
        final ordersMap = activeOrder['active_orders'] as Map;
        final resOrder = ordersMap[reservationId.toString()];
        if (resOrder is Map && resOrder['items'] is List) {
          return (resOrder['items'] as List)
              .map((i) => i is Map<String, dynamic> ? i : Map<String, dynamic>.from(i as Map))
              .toList();
        }
      }
      if (activeOrder['items'] is List) {
        return (activeOrder['items'] as List)
            .map((i) => i is Map<String, dynamic> ? i : Map<String, dynamic>.from(i as Map))
            .toList();
      }
    }
    return [];
  }

  /// 结账完成后清理指定桌台/预约单的暂存菜品数据
  Future<void> clearLocalTableItems(int tableId, {int? reservationId}) async {
    final localTables = await _databaseService.getDiningTables();
    final matchingTable = localTables.where((t) => t.id == tableId).toList();

    if (matchingTable.isNotEmpty &&
        matchingTable.first.activeOrder != null &&
        reservationId != null) {
      final mainActiveOrder =
          Map<String, dynamic>.from(matchingTable.first.activeOrder!);
      if (mainActiveOrder['active_orders'] is Map) {
        final activeOrdersMap =
            Map<String, dynamic>.from(mainActiveOrder['active_orders']);
        activeOrdersMap.remove(reservationId.toString());
        mainActiveOrder['active_orders'] = activeOrdersMap;

        if (activeOrdersMap.isNotEmpty) {
          // 仍有其它预约在服务中，更新主列表并保留 occupied 状态
          await _databaseService.updateDiningTableStatus(
            tableId,
            'occupied',
            activeOrderJson: jsonEncode(mainActiveOrder),
          );
          _logger.i('已清理桌台 $tableId 预约 $reservationId 暂存，保留其它预约');
          return;
        }
      }
    }

    // 全量清理，恢复空闲状态
    await _databaseService.updateDiningTableStatus(
      tableId,
      'available',
      activeOrderJson: '',
    );
    _logger.i('已清空桌台 $tableId 本地暂存菜品并恢复空闲');
  }

  /// 取消桌台预订预约 (POST /api/table-reservations/{id}/cancel)
  Future<bool> cancelReservation(
    int reservationId, {
    String? reason,
  }) async {
    try {
      final payload = <String, dynamic>{
        'id': reservationId,
        'reservation_id': reservationId,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (reason != null && reason.trim().isNotEmpty) 'cancel_reason': reason.trim(),
      };

      Response response;
      try {
        response = await _apiService.post(
          'table-reservations/$reservationId/cancel',
          data: payload,
        );
      } catch (_) {
        try {
          response = await _apiService.post(
            'table-reservations/cancel',
            data: payload,
          );
        } catch (_) {
          try {
            response = await _apiService.post(
              'terminal/reservations/$reservationId/cancel',
              data: payload,
            );
          } catch (_) {
            response = await _apiService.delete('terminal/reservations/$reservationId');
          }
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.i('取消预约成功: $reservationId');

        // 若返回了最新桌台信息，同步更新本地数据库桌台状态
        if (response.data != null && response.data is Map) {
          final resMap = Map<String, dynamic>.from(response.data);
          final dataObj = resMap['data'] ?? resMap;
          if (dataObj is Map && dataObj['dining_table'] != null && dataObj['dining_table'] is Map) {
            final tableData = Map<String, dynamic>.from(dataObj['dining_table']);
            final tableId = tableData['id'];
            final status = tableData['status']?.toString() ?? 'available';
            if (tableId is int) {
              await _databaseService.updateDiningTableStatus(tableId, status);
            }
          }
        }
        return true;
      }
    } catch (e) {
      _logger.e('取消预约失败 ($reservationId): $e');
    }
    return false;
  }

  /// 更新桌台预约信息（换桌、改时间、改人数、改姓名电话及备注）
  Future<bool> updateReservation(
    int reservationId, {
    int? tableId,
    String? reservationTime,
    int? guestCount,
    String? customerName,
    String? customerPhone,
    String? reservationDate,
    String? notes,
  }) async {
    try {
      final payload = <String, dynamic>{
        'id': reservationId,
        'reservation_id': reservationId,
        if (tableId != null) 'table_id': tableId,
        if (reservationTime != null && reservationTime.isNotEmpty) ...{
          'reservation_time': reservationTime,
          'time': reservationTime,
        },
        if (guestCount != null) ...{
          'guests_count': guestCount,
          'guests': guestCount,
        },
        if (customerName != null && customerName.isNotEmpty) ...{
          'customer_name': customerName,
          'name': customerName,
        },
        if (customerPhone != null && customerPhone.isNotEmpty) ...{
          'customer_phone': customerPhone,
          'phone': customerPhone,
        },
        if (reservationDate != null && reservationDate.isNotEmpty) ...{
          'reservation_date': reservationDate,
          'date': reservationDate,
        },
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      };

      Response response;
      try {
        response = await _apiService.post(
          'table-reservations/$reservationId/update',
          data: payload,
        );
      } catch (_) {
        try {
          response = await _apiService.post(
            'table-reservations/update',
            data: payload,
          );
        } catch (_) {
          try {
            response = await _apiService.put(
              'terminal/reservations/$reservationId',
              data: payload,
            );
          } catch (_) {
            response = await _apiService.post(
              'terminal/reservations/$reservationId',
              data: payload,
            );
          }
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.i('更新预约成功: $reservationId (换桌: $tableId, 时间: $reservationTime)');
        return true;
      }
    } catch (e) {
      _logger.e('更新预约信息失败 ($reservationId): $e');
    }
    return false;
  }
}
