import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:logger/logger.dart';
import '../models/order_model.dart';
import '../models/printer_station_model.dart';
import '../models/dining_table.dart';
import 'dart:convert';

// 添加平台检测导入
import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  static Database? _database;
  static final Logger _logger = Logger();

  // 单例模式
  static DatabaseService? _instance;
  DatabaseService._internal();

  factory DatabaseService() {
    _instance ??= DatabaseService._internal();
    return _instance!;
  }

  // 获取数据库实例
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  // 初始化数据库
  Future<Database> _initDatabase() async {
    // 初始化数据库工厂（桌面平台需要）
    await _initializeDatabaseFactory();

    String path = join(await getDatabasesPath(), 'omneas_orders.db');

    return await openDatabase(
      path,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // 初始化数据库工厂
  Future<void> _initializeDatabaseFactory() async {
    try {
      // 检查是否是桌面平台
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // 桌面平台使用 FFI
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        _logger.i('使用FFI数据库工厂（桌面平台）');
      } else {
        _logger.i('使用默认数据库工厂（移动平台）');
      }
    } catch (e) {
      _logger.e('数据库工厂初始化失败: $e');
      rethrow;
    }
  }

  // 创建表
  Future<void> _onCreate(Database db, int version) async {
    // 创建订单表
    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        order_no TEXT NOT NULL,
        order_time TEXT NOT NULL,
        items TEXT NOT NULL,
        total_amount REAL NOT NULL,
        discount_amount REAL NOT NULL DEFAULT 0,
        tax_rate REAL NOT NULL DEFAULT 10,
        service_fee REAL NOT NULL DEFAULT 0,
        cash_amount REAL NOT NULL DEFAULT 0,
        pos_amount REAL NOT NULL DEFAULT 0,
        order_status INTEGER NOT NULL DEFAULT 0,
        sync_status INTEGER NOT NULL DEFAULT 0,
        print_status INTEGER NOT NULL DEFAULT 0,
        error_message TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_retry_time TEXT,
        synced_time TEXT,
        printed_time TEXT,
        note TEXT,
        type TEXT,
        cash_change REAL NOT NULL DEFAULT 0,
        voucher_amount REAL NOT NULL DEFAULT 0,
        remote_order_id INTEGER,
        remote_order_number TEXT,
        is_online_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // 创建日志表
    await db.execute('''
      CREATE TABLE logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id TEXT NOT NULL,
        action TEXT NOT NULL,
        status TEXT NOT NULL,
        message TEXT,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders (id)
      )
    ''');

    // 创建服务器订单表（完整字段）
    await db.execute('''
      CREATE TABLE server_orders (
        id INTEGER PRIMARY KEY, -- 服务器订单id
        order_number TEXT NOT NULL,
        order_no TEXT,
        type TEXT,
        print_status TEXT,
        sync_status TEXT,
        status TEXT,
        total_amount TEXT,
        tax_rate TEXT,
        tax_amount TEXT,
        discount_amount TEXT,
        final_amount TEXT,
        paid_amount TEXT,
        note TEXT,
        remark TEXT,
        synced_at TEXT,
        created_at TEXT,
        updated_at TEXT,
        order_time TEXT,
        items TEXT,
        additions TEXT
      )
    ''');

    // 创建设置表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 创建打印位表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS printer_stations (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        content_type TEXT NOT NULL,
        connection_type TEXT NOT NULL,
        ip TEXT,
        port INTEGER NOT NULL DEFAULT 9100,
        device_address TEXT,
        enable_auto_print INTEGER NOT NULL DEFAULT 1,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    // 创建桌台表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS dining_tables (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT,
        area TEXT,
        capacity INTEGER DEFAULT 0,
        min_capacity INTEGER DEFAULT 0,
        status TEXT DEFAULT 'available',
        is_active INTEGER DEFAULT 1,
        is_reserved INTEGER DEFAULT 0,
        reservations_count INTEGER DEFAULT 0,
        sort_order INTEGER DEFAULT 0,
        qr_code TEXT,
        description TEXT,
        reservations_json TEXT,
        active_order_json TEXT,
        updated_at TEXT
      )
    ''');

    // 创建索引
    await db.execute(
        'CREATE INDEX idx_orders_status ON orders(order_status, sync_status, print_status)');
    await db.execute('CREATE INDEX idx_orders_time ON orders(order_time)');
    await db.execute('CREATE INDEX idx_orders_created_at ON orders(created_at)');
    await db.execute('CREATE INDEX idx_orders_no ON orders(order_no)');
    await db.execute('CREATE INDEX idx_logs_order_id ON logs(order_id)');
    // 注意：不再为 server_orders 创建 remote_order_id 索引
    _logger.i('数据库表创建完成');
  }

  // 数据库升级处理
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    _logger.i('数据库从版本 $oldVersion 升级到版本 $newVersion');

    // 从版本 1 升级到版本 2
    if (oldVersion < 2) {
      try {
        await db.execute(
          'ALTER TABLE orders ADD COLUMN sync_status INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}

      try {
        await db.execute(
          'ALTER TABLE orders ADD COLUMN is_online_order INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}

      try {
        await db.rawUpdate('''
          UPDATE orders
          SET sync_status = CASE
            WHEN order_status = 5 THEN 1
            WHEN is_online_order = 1
              OR remote_order_id IS NOT NULL
              OR remote_order_number IS NOT NULL
            THEN 1
            WHEN order_status = 4 THEN 3
            ELSE 0
          END
        ''');
      } catch (_) {}
    }

    // 从版本 2 升级到版本 3：完善时间字段和 server_orders 表
    if (oldVersion < 3) {
      // 1. 确保 orders 表有 created_at 字段
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN created_at TEXT');
        // 将旧订单的 order_time 视为创建时间
        await db.execute('UPDATE orders SET created_at = order_time WHERE created_at IS NULL');
      } catch (e) {
        _logger.w('Upgrade orders.created_at error: $e');
      }

      // 2. 确保 server_orders 有 order_time 字段
      try {
        await db.execute('ALTER TABLE server_orders ADD COLUMN order_time TEXT');
      } catch (e) {
        _logger.w('Upgrade server_orders.order_time error: $e');
      }

      // 3. 创建索引
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at)');
      } catch (_) {}
    }

    // 从版本 3 升级到版本 4：添加 settings 表
    if (oldVersion < 4) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      } catch (e) {
        _logger.w('Upgrade settings table error: $e');
      }
    }

    // 从版本 4 升级到版本 5：添加 printer_stations 表
    if (oldVersion < 5) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS printer_stations (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            role TEXT NOT NULL,
            content_type TEXT NOT NULL,
            connection_type TEXT NOT NULL,
            ip TEXT,
            port INTEGER NOT NULL DEFAULT 9100,
            device_address TEXT,
            enable_auto_print INTEGER NOT NULL DEFAULT 1,
            is_enabled INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL
          )
        ''');
      } catch (e) {
        _logger.w('Create printer_stations table error: $e');
      }
    }

    // 从版本 5 升级到版本 6：添加 dining_tables 表
    if (oldVersion < 6) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS dining_tables (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            code TEXT,
            area TEXT,
            capacity INTEGER DEFAULT 0,
            min_capacity INTEGER DEFAULT 0,
            status TEXT DEFAULT 'available',
            is_active INTEGER DEFAULT 1,
            is_reserved INTEGER DEFAULT 0,
            reservations_count INTEGER DEFAULT 0,
            sort_order INTEGER DEFAULT 0,
            qr_code TEXT,
            description TEXT,
            reservations_json TEXT,
            active_order_json TEXT,
            updated_at TEXT
          )
        ''');
      } catch (e) {
        _logger.w('Create dining_tables table error: $e');
      }
    }
  }

  // ========== 设置项操作 ==========

  /// 获取单个设置项
  Future<String?> getSetting(String key) async {
    final db = await database;
    try {
      final maps = await db.query(
        'settings',
        where: 'key = ?',
        whereArgs: [key],
      );
      if (maps.isNotEmpty) {
        return maps.first['value'] as String?;
      }
      return null;
    } catch (e) {
      _logger.e('获取设置项失败 ($key): $e');
      return null;
    }
  }

  /// 获取所有设置项
  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    try {
      final maps = await db.query('settings');
      final result = <String, String>{};
      for (final map in maps) {
        final k = map['key'] as String?;
        final v = map['value'] as String?;
        if (k != null && v != null) {
          result[k] = v;
        }
      }
      return result;
    } catch (e) {
      _logger.e('获取所有设置项失败: $e');
      return {};
    }
  }

  /// 保存单个设置项
  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    try {
      await db.insert(
        'settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      _logger.e('保存设置项失败 ($key): $e');
      rethrow;
    }
  }

  /// 批量保存设置项
  Future<void> saveSettingsMap(Map<String, String> settingsMap) async {
    final db = await database;
    try {
      final batch = db.batch();
      settingsMap.forEach((key, value) {
        batch.insert(
          'settings',
          {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      await batch.commit(noResult: true);
    } catch (e) {
      _logger.e('批量保存设置项失败: $e');
      rethrow;
    }
  }

  // ========== 订单操作 ==========

  // 插入订单
  Future<void> insertOrder(OrderModel order) async {
    final db = await database;
    try {
      await db.insert('orders', order.toMap());
      _logger.i('订单插入成功: ${order.id}');

      // 记录日志
      await insertLog(LogModel(
        orderId: order.id,
        action: 'order',
        status: 'success',
        message: '订单创建成功',
        timestamp: DateTime.now(),
      ));
    } catch (e) {
      _logger.e('订单插入失败: ${order.id}, 错误: $e');
      throw e;
    }
  }

  // 更新订单
  Future<void> updateOrder(OrderModel order) async {
    final db = await database;
    try {
      await db.update(
        'orders',
        order.toMap(),
        where: 'id = ?',
        whereArgs: [order.id],
      );
      _logger.i('订单更新成功: ${order.id}');
    } catch (e) {
      _logger.e('订单更新失败: ${order.id}, 错误: $e');
      throw e;
    }
  }

  // 获取订单
  Future<OrderModel?> getOrder(String id) async {
    final db = await database;
    try {
      final maps = await db.query(
        'orders',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (maps.isNotEmpty) {
        return OrderModel.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      _logger.e('获取订单失败: $id, 错误: $e');
      throw e;
    }
  }

  // 获取待同步订单
  Future<List<OrderModel>> getPendingSyncOrders() async {
    final db = await database;
    try {
      final maps = await db.query(
        'orders',
        where: 'sync_status IN (?, ?)',
        whereArgs: [SyncStatus.pending.index, SyncStatus.syncFailed.index],
        orderBy: 'created_at ASC',
      );

      return maps.map((map) => OrderModel.fromMap(map)).toList();
    } catch (e) {
      _logger.e('获取待同步订单失败: $e');
      throw e;
    }
  }

  // 获取待打印订单
  Future<List<OrderModel>> getPendingPrintOrders() async {
    final db = await database;
    try {
      final maps = await db.query(
        'orders',
        where: 'print_status IN (?, ?)',
        whereArgs: [PrintStatus.pending.index, PrintStatus.printFailed.index],
        orderBy: 'created_at ASC',
      );

      return maps.map((map) => OrderModel.fromMap(map)).toList();
    } catch (e) {
      _logger.e('获取待打印订单失败: $e');
      throw e;
    }
  }

  /// 获取当天待完成的在线订单
  Future<List<OrderModel>> getPendingOnlineOrders({DateTime? date}) async {
    final db = await database;
    try {
      final now = date ?? DateTime.now();
      final start = DateTime(now.year, now.month, now.day).toIso8601String();
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999)
          .toIso8601String();
      final maps = await db.query(
        'orders',
        where:
            'is_online_order = 1 AND order_status IN (?, ?) AND order_time BETWEEN ? AND ?',
        whereArgs: [
          OrderStatus.pending.index,
          OrderStatus.confirmed.index,
          start,
          end
        ],
        orderBy: 'order_time ASC',
      );

      return maps.map((map) => OrderModel.fromMap(map)).toList();
    } catch (e) {
      _logger.e('获取待完成在线订单失败: $e');
      throw e;
    }
  }

  // 获取所有订单（分页）
  Future<List<OrderModel>> getAllOrders(
      {int limit = 50, int offset = 0}) async {
    final db = await database;
    try {
      final maps = await db.query(
        'orders',
        orderBy: 'created_at DESC',
        limit: limit,
        offset: offset,
      );

      return maps.map((map) => OrderModel.fromMap(map)).toList();
    } catch (e) {
      _logger.e('获取所有订单失败: $e');
      throw e;
    }
  }

  // 获取日期范围内的订单
  Future<List<OrderModel>> getOrdersByDateRange(
      DateTime startDate, DateTime endDate,
      {int? limit, int? offset}) async {
    final db = await database;
    try {
      final startIso =
          DateTime(startDate.year, startDate.month, startDate.day)
              .toIso8601String();
      final endIso = DateTime(
              endDate.year, endDate.month, endDate.day, 23, 59, 59, 999)
          .toIso8601String();

      final maps = await db.query(
        'orders',
        where: '(created_at >= ? AND created_at <= ?) OR (order_time >= ? AND order_time <= ?)',
        whereArgs: [startIso, endIso, startIso, endIso],
        orderBy: 'created_at DESC',
        limit: limit,
        offset: offset,
      );

      return maps.map((map) => OrderModel.fromMap(map)).toList();
    } catch (e) {
      _logger.e('获取日期范围订单失败: $e');
      throw e;
    }
  }

  /// 获取指定日期的所有订单（基于创建时间或订单时间）
  Future<List<OrderModel>> getOrdersByDate(DateTime date) async {
    final db = await database;
    final startDate =
        DateTime(date.year, date.month, date.day).toIso8601String();
    final endDate = DateTime(date.year, date.month, date.day, 23, 59, 59, 999)
        .toIso8601String();

    try {
      final List<Map<String, dynamic>> results = await db.query(
        'orders',
        where: '(created_at BETWEEN ? AND ?) OR (order_time BETWEEN ? AND ?)',
        whereArgs: [startDate, endDate, startDate, endDate],
        orderBy: 'created_at ASC',
      );

      return results.map((map) => OrderModel.fromMap(map)).toList();
    } catch (e) {
      _logger.e('获取日期订单失败: $e');
      return [];
    }
  }

  // 删除订单
  Future<void> deleteOrder(String id) async {
    final db = await database;
    try {
      await db.delete('orders', where: 'id = ?', whereArgs: [id]);
      _logger.i('订单删除成功: $id');
    } catch (e) {
      _logger.e('订单删除失败: $id, 错误: $e');
      throw e;
    }
  }

  // 删除所有订单（测试/管理用途）
  Future<void> deleteAllOrders() async {
    final db = await database;
    try {
      await db.delete('orders');
      await db.delete('logs');
      await db.delete('server_orders');
      _logger.i('所有本地订单、服务器订单缓存及日志已清空');
    } catch (e) {
      _logger.e('删除所有订单失败: $e');
      rethrow;
    }
  }

  // ========== 日志操作 ==========

  // 插入日志
  Future<void> insertLog(LogModel log) async {
    final db = await database;
    try {
      await db.insert('logs', log.toMap());
    } catch (e) {
      _logger.e('日志插入失败: $e');
      // 日志插入失败不抛出异常，避免影响主流程
    }
  }

  // 获取订单日志
  Future<List<LogModel>> getOrderLogs(String orderId) async {
    final db = await database;
    try {
      final maps = await db.query(
        'logs',
        where: 'order_id = ?',
        whereArgs: [orderId],
        orderBy: 'timestamp DESC',
      );

      return maps.map((map) => LogModel.fromMap(map)).toList();
    } catch (e) {
      _logger.e('获取订单日志失败: $orderId, 错误: $e');
      throw e;
    }
  }

  // 清理旧日志（保留最近7天）
  Future<void> cleanOldLogs() async {
    final db = await database;
    try {
      final sevenDaysAgo = DateTime.now().subtract(Duration(days: 7));
      await db.delete(
        'logs',
        where: 'timestamp < ?',
        whereArgs: [sevenDaysAgo.toIso8601String()],
      );
      _logger.i('旧日志清理完成');
    } catch (e) {
      _logger.e('清理旧日志失败: $e');
    }
  }

  // ========== 统计查询 ==========

  // 获取订单统计，支持按日期/日期范围统计（如果传入 date/dateRange，则 todayCount 基于该范围，否则全库）
  Future<Map<String, int>> getOrderStats(
      {DateTime? date, dynamic dateRange}) async {
    final db = await database;
    try {
      int todayCount = 0;
      if (dateRange != null) {
        final startIso = DateTime(dateRange.start.year, dateRange.start.month,
                dateRange.start.day)
            .toIso8601String();
        final endIso = DateTime(dateRange.end.year, dateRange.end.month,
                dateRange.end.day, 23, 59, 59, 999)
            .toIso8601String();
        todayCount = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM orders WHERE created_at BETWEEN ? AND ?',
              [startIso, endIso],
            )) ??
            0;
      } else if (date != null) {
        final startOfDay = DateTime(date.year, date.month, date.day);
        final endOfDay =
            DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
        todayCount = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM orders WHERE created_at BETWEEN ? AND ?',
              [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
            )) ??
            0;
      } else {
        todayCount = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM orders',
            )) ??
            0;
      }

      // 待同步订单数（全库）
      final pendingSyncCount = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM orders WHERE sync_status IN (?, ?)',
            [SyncStatus.pending.index, SyncStatus.syncFailed.index],
          )) ??
          0;

      // 待打印订单数（全库）
      final pendingPrintCount = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM orders WHERE print_status IN (?, ?)',
            [PrintStatus.pending.index, PrintStatus.printFailed.index],
          )) ??
          0;

      return {
        'todayCount': todayCount,
        'pendingSyncCount': pendingSyncCount,
        'pendingPrintCount': pendingPrintCount,
      };
    } catch (e) {
      _logger.e('获取订单统计失败: $e');
      throw e;
    }
  }

  // ========== 服务器订单相关 ==========

  /// 获取本地已同步的最大 remote_order_id
  Future<int?> getMaxRemoteOrderId() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT MAX(remote_order_id) as maxId FROM orders');
    if (result.isNotEmpty && result.first['maxId'] != null) {
      return result.first['maxId'] as int;
    }
    return null;
  }

  /// 插入服务器订单到 server_orders 表（完整字段）
  Future<void> insertServerOrder(Map<String, dynamic> serverOrder) async {
    final db = await database;

    // 明确构建数据映射，避免直接复制包含 List 的原始数据
    final data = <String, dynamic>{
      'id': serverOrder['id'],
      'order_number': serverOrder['order_number'],
      'order_no': serverOrder['order_no'],
      'type': serverOrder['type'],
      'print_status': serverOrder['print_status'],
      'sync_status': serverOrder['sync_status'],
      'status': serverOrder['status'],
      'total_amount': serverOrder['total_amount'],
      'tax_rate': serverOrder['tax_rate'],
      'tax_amount': serverOrder['tax_amount'],
      'discount_amount': serverOrder['discount_amount'],
      'final_amount': serverOrder['final_amount'],
      'paid_amount': serverOrder['paid_amount'],
      'note': serverOrder['note'],
      'remark': serverOrder['remark'],
      'synced_at': serverOrder['synced_at'],
      'created_at': serverOrder['created_at'],
      'updated_at': serverOrder['updated_at'],
      'order_time': serverOrder['order_time']?.toString(), // 新增
    };

    // items 字段处理
    final items = serverOrder['items'];
    if (items is String) {
      data['items'] = items;
    } else if (items is List) {
      data['items'] = jsonEncode(items);
    } else {
      data['items'] = '[]';
    }

    // additions 字段处理
    final additions = serverOrder['additions'];
    if (additions is String) {
      data['additions'] = additions;
    } else if (additions is List) {
      data['additions'] = jsonEncode(additions);
    } else {
      data['additions'] = '[]';
    }

    await db.insert('server_orders', data,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 判断本地 orders 表是否已存在指定 remote_order_number
  Future<bool> existsOrderByRemoteNumber(String remoteOrderNumber) async {
    final db = await database;
    final result = await db.query('orders',
        where: 'remote_order_number = ?', whereArgs: [remoteOrderNumber]);
    return result.isNotEmpty;
  }

  /// 判断本地 orders 表是否已存在指定 remote_order_id
  Future<bool> existsOrderByRemoteId(int remoteOrderId) async {
    final db = await database;
    final result = await db.query(
      'orders',
      where: 'remote_order_id = ?',
      whereArgs: [remoteOrderId],
    );
    return result.isNotEmpty;
  }

  /// 根据 remote_order_id 获取本地订单
  Future<OrderModel?> getOrderByRemoteId(int remoteOrderId) async {
    final db = await database;
    final results = await db.query(
      'orders',
      where: 'remote_order_id = ?',
      whereArgs: [remoteOrderId],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return OrderModel.fromMap(results.first);
    }
    return null;
  }

  /// 根据 remote_order_number 获取本地订单
  Future<OrderModel?> getOrderByRemoteNumber(String remoteOrderNumber) async {
    final db = await database;
    final results = await db.query(
      'orders',
      where: 'remote_order_number = ?',
      whereArgs: [remoteOrderNumber],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return OrderModel.fromMap(results.first);
    }
    return null;
  }

  // ========== 打印位 (PrinterStation) 操作 ==========

  /// 插入打印位
  Future<void> insertPrinterStation(PrinterStationModel station) async {
    final db = await database;
    await db.insert(
      'printer_stations',
      station.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 更新打印位
  Future<void> updatePrinterStation(PrinterStationModel station) async {
    final db = await database;
    await db.update(
      'printer_stations',
      station.toMap(),
      where: 'id = ?',
      whereArgs: [station.id],
    );
  }

  /// 删除打印位
  Future<void> deletePrinterStation(String id) async {
    final db = await database;
    await db.delete('printer_stations', where: 'id = ?', whereArgs: [id]);
  }

  /// 获取所有打印位（为空则返回空列表，由用户手动创建）
  Future<List<PrinterStationModel>> getPrinterStations() async {
    final db = await database;
    final maps = await db.query('printer_stations', orderBy: 'created_at ASC');
    return maps.map((m) => PrinterStationModel.fromMap(m)).toList();
  }

  /// 获取已启用的打印位
  Future<List<PrinterStationModel>> getEnabledPrinterStations() async {
    final allStations = await getPrinterStations();
    return allStations.where((s) => s.isEnabled).toList();
  }

  // ========== 桌台 (DiningTable) 本地缓存操作 ==========

  /// 清空本地所有桌台缓存（用于彻底清除历史不兼容数据并全量重新同步）
  Future<void> clearAllDiningTablesCache() async {
    final db = await database;
    try {
      await db.delete('dining_tables');
      _logger.i('已清空本地所有桌台 SQLite 缓存');
    } catch (e) {
      _logger.e('清空桌台缓存失败: $e');
    }
  }

  /// 清理 SQLite 本地桌台的所有暂存菜品数据与预约状态，将所有桌台恢复为空闲
  Future<void> clearDiningTableItemsCache() async {
    final db = await database;
    try {
      await db.update(
        'dining_tables',
        {
          'status': 'available',
          'is_reserved': 0,
          'active_order_json': null,
          'reservations_json': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );
      _logger.i('已彻底清理 SQLite 数据库中所有桌台暂存菜品数据与状态');
    } catch (e) {
      _logger.e('清理 SQLite 桌台菜品缓存失败: $e');
    }
  }

  /// 批量保存桌台列表至本地数据库（事务更新，自动保护本地已保存的菜品项）
  Future<void> saveDiningTables(List<DiningTable> tables) async {
    final db = await database;
    final existingMaps = await db.query('dining_tables');
    final existingMapById = <int, Map<String, dynamic>>{};
    for (var m in existingMaps) {
      if (m['id'] is int) {
        existingMapById[m['id'] as int] = m;
      }
    }

    await db.transaction((txn) async {
      for (final table in tables) {
        var dbMap = table.toDbMap();
        final localMap = existingMapById[table.id];

        if (localMap != null &&
            localMap['active_order_json'] != null &&
            localMap['active_order_json'].toString().isNotEmpty) {
          final serverActiveOrder = table.activeOrder;
          final serverHasItems = serverActiveOrder != null &&
              serverActiveOrder['items'] is List &&
              (serverActiveOrder['items'] as List).isNotEmpty;

          if (!serverHasItems && (table.isOccupied || localMap['status'] == 'occupied')) {
            dbMap['active_order_json'] = localMap['active_order_json'];
            dbMap['status'] = 'occupied';

            // 同步保护 localMap 中已 seated 的预约项状态
            if (localMap['reservations_json'] != null &&
                dbMap['reservations_json'] != null) {
              try {
                final localAct = jsonDecode(localMap['active_order_json'].toString());
                if (localAct is Map && localAct['active_orders'] is Map) {
                  final activeOrders = localAct['active_orders'] as Map;
                  final serverResList = jsonDecode(dbMap['reservations_json'].toString());
                  if (serverResList is List) {
                    final updatedResList = serverResList.map((r) {
                      if (r is Map) {
                        final rMap = Map<String, dynamic>.from(r);
                        final rId = rMap['id']?.toString();
                        if (rId != null && activeOrders[rId] != null) {
                          rMap['status'] = 'seated';
                        }
                        return rMap;
                      }
                      return r;
                    }).toList();
                    dbMap['reservations_json'] = jsonEncode(updatedResList);
                  }
                }
              } catch (_) {}
            }
          }
        }

        await txn.insert(
          'dining_tables',
          dbMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// 获取本地缓存的所有桌台列表（按 sort_order 排序）
  Future<List<DiningTable>> getDiningTables() async {
    final db = await database;
    try {
      final maps = await db.query(
        'dining_tables',
        where: 'is_active = 1',
        orderBy: 'sort_order ASC, name ASC',
      );
      return maps.map((m) => DiningTable.fromDbMap(m)).toList();
    } catch (e) {
      _logger.e('获取本地桌台数据失败: $e');
      return [];
    }
  }

  /// 更新指定桌台状态
  Future<void> updateDiningTableStatus(
    int tableId,
    String status, {
    bool? isReserved,
    String? activeOrderJson,
    String? reservationsJson,
  }) async {
    final db = await database;
    try {
      final map = <String, dynamic>{
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (isReserved != null) {
        map['is_reserved'] = isReserved ? 1 : 0;
      }
      if (activeOrderJson != null) {
        map['active_order_json'] = activeOrderJson;
      }
      if (reservationsJson != null) {
        map['reservations_json'] = reservationsJson;
      }
      await db.update(
        'dining_tables',
        map,
        where: 'id = ?',
        whereArgs: [tableId],
      );
    } catch (e) {
      _logger.e('更新桌台状态失败: $e');
    }
  }

  // 关闭数据库
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
      _logger.i('数据库连接已关闭');
    }
  }
}
