import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:logger/logger.dart';
import '../models/order_model.dart';
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
      version: 1, // 只需全新建表即可
      onCreate: _onCreate,
      // 不再需要 onUpgrade
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
        items TEXT,
        additions TEXT
      )
    ''');

    // 创建索引
    await db.execute('CREATE INDEX idx_orders_status ON orders(order_status, print_status)');
    await db.execute('CREATE INDEX idx_orders_time ON orders(order_time)');
    await db.execute('CREATE INDEX idx_orders_no ON orders(order_no)');
    await db.execute('CREATE INDEX idx_logs_order_id ON logs(order_id)');
    // 注意：不再为 server_orders 创建 remote_order_id 索引
    _logger.i('数据库表创建完成');
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
        where: 'order_status IN (?, ?)',
        whereArgs: [OrderStatus.pending.index, OrderStatus.pendingSync.index],
        orderBy: 'order_time ASC',
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
        orderBy: 'order_time ASC',
      );

      return maps.map((map) => OrderModel.fromMap(map)).toList();
    } catch (e) {
      _logger.e('获取待打印订单失败: $e');
      throw e;
    }
  }

  // 获取所有订单（分页）
  Future<List<OrderModel>> getAllOrders({int limit = 50, int offset = 0}) async {
    final db = await database;
    try {
      final maps = await db.query(
        'orders',
        orderBy: 'order_time DESC',
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
  Future<List<OrderModel>> getOrdersByDateRange(DateTime startDate, DateTime endDate) async {
    final db = await database;
    try {
      final maps = await db.query(
        'orders',
        where: 'order_time >= ? AND order_time <= ?',
        whereArgs: [
          startDate.toIso8601String(),
          endDate.toIso8601String(),
        ],
        orderBy: 'order_time DESC',
      );

      return maps.map((map) => OrderModel.fromMap(map)).toList();
    } catch (e) {
      _logger.e('获取日期范围订单失败: $e');
      throw e;
    }
  }

  /// 获取指定日期的所有订单
  Future<List<OrderModel>> getOrdersByDate(DateTime date) async {
    final db = await database;
    final startDate = DateTime(date.year, date.month, date.day).toIso8601String();
    final endDate = DateTime(date.year, date.month, date.day, 23, 59, 59, 999).toIso8601String();

    try {
      final List<Map<String, dynamic>> results = await db.query(
        'orders',
        where: 'order_time BETWEEN ? AND ?',
        whereArgs: [startDate, endDate],
        orderBy: 'order_time ASC',
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

  // 获取订单统计
  Future<Map<String, int>> getOrderStats() async {
    final db = await database;
    try {
      // 今日订单数
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final todayCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM orders WHERE order_time >= ?',
        [startOfDay.toIso8601String()],
      )) ?? 0;

      // 待同步订单数
      final pendingSyncCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM orders WHERE order_status IN (?, ?)',
        [OrderStatus.pending.index, OrderStatus.pendingSync.index],
      )) ?? 0;

      // 待打印订单数
      final pendingPrintCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM orders WHERE print_status IN (?, ?)',
        [PrintStatus.pending.index, PrintStatus.printFailed.index],
      )) ?? 0;

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
    final result = await db.rawQuery('SELECT MAX(remote_order_id) as maxId FROM orders');
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

    await db.insert('server_orders', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 判断本地 orders 表是否已存在指定 remote_order_number
  Future<bool> existsOrderByRemoteNumber(String remoteOrderNumber) async {
    final db = await database;
    final result = await db.query('orders', where: 'remote_order_number = ?', whereArgs: [remoteOrderNumber]);
    return result.isNotEmpty;
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
