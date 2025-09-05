import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import '../models/order_model.dart';
import '../models/report_models.dart';
import 'database_service.dart';
import 'settings_service.dart';

enum ReceiptType { customer, kitchen } /// 小票类型枚举（顾客用/后厨用）

class PrintService {
  static final Logger _logger = Logger();
  final DatabaseService _databaseService = DatabaseService();

  // 单例模式
  static PrintService? _instance;
  PrintService._internal();

  factory PrintService() {
    _instance ??= PrintService._internal();
    return _instance!;
  }

  /// 打印订单
  Future<void> printOrder(String orderId) async {
    try {
      final order = await _databaseService.getOrder(orderId);
      if (order == null) {
        throw Exception('订单不存在: $orderId');
      }

      _logger.i('开始打印订单: $orderId');

      // 生成打印内容
      final printContent = await _generatePrintContent(order);

      // 发送到打印机
      await _sendToPrinter(printContent);

      // 标记打印成功
      await _markPrintSuccess(order);

      _logger.i('订单打印成功: $orderId');
    } catch (e) {
      await _handlePrintError(orderId, e);
      rethrow;
    }
  }

  /// 生成打印内容
  Future<String> _generatePrintContent(OrderModel order) async {
    final items = jsonDecode(order.items) as List;
    final StringBuffer content = StringBuffer();

    // Print header (English only)
    content.writeln('================================');
    content.writeln('       RESTAURANT RECEIPT');
    content.writeln('================================');
    content.writeln();

    // Order information
    content.writeln('Order ID: ${order.id.substring(0, 8)}');
    content.writeln('Order Time: ${_formatDateTime(order.orderTime)}');
    content.writeln('--------------------------------');
    content.writeln();

    // Items detail
    content.writeln('Items:');
    content.writeln('--------------------------------');

    double totalAmount = 0;
    for (var item in items) {
      final name = item['name'] ?? '';
      final quantity = item['quantity'] ?? 1;
      final price = (item['price'] ?? 0).toDouble();
      final subtotal = quantity * price;
      totalAmount += subtotal;

      content.writeln('${name.padRight(20)} x${quantity}');
      content.writeln('${' ' * 16}\$${price.toStringAsFixed(2)} = \$${subtotal.toStringAsFixed(2)}');

      // Notes if any
      if (item['note'] != null && item['note'].toString().isNotEmpty) {
        content.writeln('${' ' * 4}Note: ${item['note']}');
      }
      content.writeln();
    }

    content.writeln('--------------------------------');
    content.writeln('Total: \$${totalAmount.toStringAsFixed(2)}');
    content.writeln('================================');
    content.writeln();

    // Print time
    content.writeln('Print Time: ${_formatDateTime(DateTime.now())}');
    content.writeln('--------------------------------');
    content.writeln('Thank you for your business!');
    content.writeln();
    content.writeln();
    content.writeln(); // Extra lines for easy tearing

    return content.toString();
  }

  /// 打印销售报告
  Future<void> printReport(OrderStats stats, DateTime startDate, DateTime endDate) async {
    try {
      _logger.i('开始打印销售报告');

      // 生成报告打印内容
      final printContent = _generateReportContent(stats, startDate, endDate);

      // 发送到打印机
      await _sendToPrinter(printContent);

      _logger.i('销售报告打印成功');
    } catch (e) {
      _logger.e('打印销售报告失败: $e');
      rethrow;
    }
  }

  /// 生成报告打印内容
  String _generateReportContent(OrderStats stats, DateTime startDate, DateTime endDate) {
    final StringBuffer content = StringBuffer();

    // 报告标题
    content.writeln('================================');
    content.writeln('       SALES REPORT');
    content.writeln('================================');
    content.writeln();

    // 报告时间段
    content.writeln('Report Period:');
    content.writeln('From: ${_formatDate(startDate)}');
    content.writeln('To:   ${_formatDate(endDate)}');
    content.writeln('Generated: ${_formatDateTime(DateTime.now())}');
    content.writeln('--------------------------------');
    content.writeln();

    // 销售总览
    content.writeln('SALES OVERVIEW:');
    content.writeln('--------------------------------');
    content.writeln('Total Revenue:     \$${stats.totalRevenue.toStringAsFixed(2)}');
    content.writeln('Total Orders:      ${stats.totalOrders}');
    content.writeln('Completed Orders:  ${stats.completedOrders}');
    content.writeln('Cancelled Orders:  ${stats.cancelledOrders}');
    content.writeln('Average Order:     \$${stats.averageOrderValue.toStringAsFixed(2)}');
    content.writeln('--------------------------------');
    content.writeln();

    // 热销商品
    if (stats.topSellingItems.isNotEmpty) {
      content.writeln('TOP SELLING ITEMS:');
      content.writeln('--------------------------------');
      for (int i = 0; i < stats.topSellingItems.length; i++) {
        final item = stats.topSellingItems[i];
        content.writeln('${i + 1}. ${item.name}');
        content.writeln('   Quantity: ${item.quantity}');
        content.writeln();
      }
      content.writeln('--------------------------------');
    }

    content.writeln();
    content.writeln('Thank you for using our system!');
    content.writeln();
    content.writeln();
    content.writeln(); // Extra lines for easy tearing

    return content.toString();
  }

  /// 发送到打印机
  Future<void> _sendToPrinter(String content) async {
    try {
      // 获取打印机配置
      final settingsService = SettingsService();
      final settings = settingsService.getSettings();

      final printerIP = settings.printerAddress;
      final printerPort = settings.printerPort;

      if (printerIP.isEmpty) {
        throw Exception('打印机IP地址未配置');
      }

      _logger.i('连接打印机: $printerIP:$printerPort');

      // 实际发送到网络打印机
      await _sendToNetworkPrinter(content, printerIP, printerPort);
    } catch (e) {
      _logger.e('发送到打印机失败: $e');
      throw Exception('打印机通信失败: $e');
    }
  }

  /// 网络打印机发送（真实实现）
  Future<void> _sendToNetworkPrinter(String content, String printerIP, int port) async {
    Socket? socket;

    try {
      _logger.d('正在连接打印机: $printerIP:$port');

      // 建立TCP连接，设置超时时间
      socket = await Socket.connect(printerIP, port)
          .timeout(Duration(seconds: 10));

      _logger.d('打印机连接成功');

      // 生成ESC/POS命令
      final printData = _generateESCPOSCommands(content);

      // 发送数据到打印机
      socket.add(printData);
      await socket.flush();

      // 等待一小段时间确保数据发送完成
      await Future.delayed(Duration(milliseconds: 500));

      _logger.i('数据发送到打印��功，长度: ${printData.length} bytes');
    } catch (e) {
      _logger.e('网络打印机通信失败: $e');
      throw Exception('网络打印机连接失败: $e');
    } finally {
      // 确保关闭连接
      try {
        await socket?.close();
        _logger.d('打印机连接已关闭');
      } catch (e) {
        _logger.w('关闭打印机连接时出错: $e');
      }
    }
  }

  /// 发送原始ESC/POS命令到打印机
  Future<void> _sendToPrinterRaw(List<int> printData) async {
    try {
      final settingsService = SettingsService();
      final settings = settingsService.getSettings();
      final printerIP = settings.printerAddress;
      final printerPort = settings.printerPort;

      if (printerIP.isEmpty) {
        throw Exception('打印机IP地址未配置');
      }

      _logger.i('连接打印机: $printerIP:$printerPort');

      Socket? socket;
      try {
        socket = await Socket.connect(printerIP, printerPort)
            .timeout(Duration(seconds: 10));

        socket.add(printData);
        await socket.flush();
        await Future.delayed(Duration(milliseconds: 500));

        _logger.i('数据发送到打印成功，长度: ${printData.length} bytes');
      } catch (e) {
        _logger.e('网络打印机通信失败: $e');
        throw Exception('网络打印机连接失败: $e');
      } finally {
        try {
          await socket?.close();
          _logger.d('打印机连接已��闭');
        } catch (e) {
          _logger.w('关闭打印机连接时出错: $e');
        }
      }
    } catch (e) {
      _logger.e('发送到打印机失败: $e');
      throw Exception('打印机通信失败: $e');
    }
  }

  /// 生成ESC/POS打印命令
  List<int> _generateESCPOSCommands(String content) {
    List<int> commands = [];

    // ESC/POS 初始化命令
    commands.addAll([0x1B, 0x40]); // ESC @ - 初始化打印机

    // 设置字符集为UTF-8
    commands.addAll([0x1B, 0x74, 0x06]); // ESC t 6 - 设置字符集

    // 设置字体大小（正常）
    commands.addAll([0x1D, 0x21, 0x00]); // GS ! 0 - 正常字体

    // 设置���对齐
    commands.addAll([0x1B, 0x61, 0x00]); // ESC a 0 - 左对齐

    // 添加打印内容
    commands.addAll(utf8.encode(content));

    // 切纸命令（部分切纸）
    commands.addAll([0x1D, 0x56, 0x01]); // GS V 1 - 部分切纸

    // 或者使用全切纸（如果打印机支持���
    // commands.addAll([0x1D, 0x56, 0x00]); // GS V 0 - 全切纸

    return commands;
  }

  /// 标记打印成功
  Future<void> _markPrintSuccess(OrderModel order) async {
    final updatedOrder = order.copyWith(
      printStatus: PrintStatus.printed,
      printedTime: DateTime.now(),
    );

    await _databaseService.updateOrder(updatedOrder);

    // 记录成功日志
    await _databaseService.insertLog(LogModel(
      orderId: order.id,
      action: 'print',
      status: 'success',
      message: '打印成功',
      timestamp: DateTime.now(),
    ));
  }

  /// 处理打印错误
  Future<void> _handlePrintError(String orderId, dynamic error) async {
    final order = await _databaseService.getOrder(orderId);
    if (order == null) return;

    String errorMessage = error.toString();

    // 更新订单打印状态
    final updatedOrder = order.copyWith(
      printStatus: PrintStatus.printFailed,
      errorMessage: errorMessage,
      retryCount: order.retryCount + 1,
      lastRetryTime: DateTime.now(),
    );

    await _databaseService.updateOrder(updatedOrder);

    // 记录错误日志
    await _databaseService.insertLog(LogModel(
      orderId: orderId,
      action: 'print',
      status: 'error',
      message: errorMessage,
      timestamp: DateTime.now(),
    ));
  }

  /// 批量重试打印失败的订单
  Future<void> retryFailedPrintOrders() async {
    try {
      final failedOrders = await _databaseService.getPendingPrintOrders();

      if (failedOrders.isEmpty) {
        _logger.i('没有待打印的订单');
        return;
      }

      _logger.i('开始重试 ${failedOrders.length} 个打印任务');

      int successCount = 0;
      int failCount = 0;

      for (final order in failedOrders) {
        try {
          // 检查重试间隔
          if (order.lastRetryTime != null) {
            final timeDiff = DateTime.now().difference(order.lastRetryTime!);
            if (timeDiff.inMinutes < 2) {
              continue; // 跳过频繁重试
            }
          }

          // 检查重试次数
          if (order.retryCount >= 5) {
            _logger.w('打印重试次数超限，跳过: ${order.id}');
            failCount++;
            continue;
          }

          await printOrder(order.id);
          successCount++;

          // 控制打印频率，避免打印机过载
          await Future.delayed(Duration(seconds: 1));
        } catch (e) {
          _logger.e('重试打印失败: ${order.id}, 错误: $e');
          failCount++;
        }
      }

      _logger.i('批量重试打印完成 - 成功: $successCount, 失败: $failCount');
    } catch (e) {
      _logger.e('批量重试打印过程出错: $e');
    }
  }

  /// 检查打印机状态
  Future<bool> checkPrinterStatus() async {
    try {
      final settingsService = SettingsService();
      final settings = settingsService.getSettings();

      final printerIP = settings.printerAddress;
      final printerPort = settings.printerPort;

      if (printerIP.isEmpty) {
        _logger.w('打印机IP地址未配置');
        return false;
      }

      _logger.d('检查打印机状态: $printerIP:$printerPort');

      // 尝试连接打印机
      Socket? socket;
      try {
        socket = await Socket.connect(printerIP, printerPort)
            .timeout(Duration(seconds: 5));

        // 发送状态查询命令
        socket.add([0x10, 0x04, 0x01]); // DLE EOT 1 - 查询打印机状态
        await socket.flush();

        // 等待响应
        final response = await socket.first.timeout(Duration(seconds: 3));

        _logger.d('打印机状态响应: $response');

        await socket.close();
        return true;
      } catch (e) {
        _logger.w('打印机状态检查失败: $e');
        await socket?.close();
        return false;
      }
    } catch (e) {
      _logger.e('检查打印机状态失败: $e');
      return false;
    }
  }

  /// 手动重置订单打印状态
  Future<void> resetOrderPrintStatus(String orderId) async {
    final order = await _databaseService.getOrder(orderId);
    if (order == null) return;

    final resetOrder = order.copyWith(
      printStatus: PrintStatus.pending,
      retryCount: 0,
      lastRetryTime: null,
    );

    await _databaseService.updateOrder(resetOrder);

    // 记录重置日志
    await _databaseService.insertLog(LogModel(
      orderId: orderId,
      action: 'print',
      status: 'reset',
      message: '手动重置打印状态',
      timestamp: DateTime.now(),
    ));

    _logger.i('订单打印状态已重置: $orderId');
  }

  /// 获取打印队列统计
  Future<Map<String, int>> getPrintQueueStats() async {
    final pendingOrders = await _databaseService.getPendingPrintOrders();

    int pendingCount = 0;
    int failedCount = 0;

    for (final order in pendingOrders) {
      if (order.printStatus == PrintStatus.pending) {
        pendingCount++;
      } else if (order.printStatus == PrintStatus.printFailed) {
        failedCount++;
      }
    }

    return {
      'pendingCount': pendingCount,
      'failedCount': failedCount,
      'totalCount': pendingOrders.length,
    };
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  /// 格式化日期（仅日期）
  String _formatDate(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  /// 配置打印��设置
  void configurePrinter({
    String? printerIP,
    int? printerPort,
    String? encoding,
  }) {
    // 保存打印机配置到本地存�����������
    _logger.i('打印机配置已更新');
  }

  /// 按模板打印订单（支持顾客用和后厨用）
  Future<void> printOrderWithTemplate(OrderModel order, {required ReceiptType receiptType}) async {
    try {
      String printContent = '';
      // 预留：可通过API获取模板内容
      switch (receiptType) {
        case ReceiptType.customer:
          printContent = await _generateCustomerReceiptTemplate(order);
          break;
        case ReceiptType.kitchen:
          printContent = await _generateKitchenReceiptTemplate(order);
          break;
      }
      await _sendToPrinter(printContent);
      await _markPrintSuccess(order);
      _logger.i('订单${order.id} ${receiptType == ReceiptType.customer ? "顾客用" : "后厨用"}小票打印成功');
    } catch (e) {
      await _handlePrintError(order.id, e);
      rethrow;
    }
  }

  /// 合并打印顾客用和后厨用小票（一次性发送，切纸分隔）
  Future<void> printOrderWithTemplates(OrderModel order) async {
    try {
      // 生成顾客用小票内容
      final customerContent = await _generateCustomerReceiptTemplate(order);
      // 生成后厨用小票内容
      final kitchenContent = await _generateKitchenReceiptTemplate(order);
      // 生成ESC/POS命令（合并两段内容，中���切纸）
      final printData = _generateCombinedESCPOSCommands(customerContent, kitchenContent);
      // 发送到打印机
      await _sendToPrinterRaw(printData);
      // 标记打印成功
      await _markPrintSuccess(order);
      _logger.i('订单${order.id} 顾客用+后厨用小票打印成功');
    } catch (e) {
      await _handlePrintError(order.id, e);
      rethrow;
    }
  }

  /// 生成合并的ESC/POS命令（分块处理，精确控制每部分样式）
  List<int> _generateCombinedESCPOSCommands(String customerContent, String kitchenContent) {
    List<int> commands = [];

    // ========== 顾客用小票 ==========
    commands.addAll([0x1B, 0x40]); // ESC @ 初始化
    
    // 解析顾客用小票内容
    final customerOrder = _parseCustomerReceipt(customerContent);
    
    // 块1: 店铺信息 - 居中对齐，正常字体
    commands.addAll([0x1B, 0x61, 0x01]); // ESC a 1 居中
    for (String line in customerOrder['header'] ?? []) {
      commands.addAll(utf8.encode(line));
      commands.add(0x0A); // LF
    }
    
    // 块2: 订单号和分割线 - 左对齐，加粗字体
    commands.addAll([0x1B, 0x61, 0x00]); // ESC a 0 左对齐
    for (String line in customerOrder['orderInfo'] ?? []) {
      commands.addAll([0x1B, 0x45, 0x01]); // ESC E 1 加粗
      commands.addAll([0x1D, 0x21, 0x08]);
      commands.addAll(utf8.encode(line));
      commands.add(0x0A); // LF
      commands.addAll([0x1B, 0x45, 0x00]); // ESC E 0 取消加粗
    }
    
    // 块3: 菜品项目 - 左对齐
    commands.addAll([0x1B, 0x61, 0x00]); // ESC a 0 左对齐
    for (String line in customerOrder['items'] ?? []) {
      commands.addAll([0x1B, 0x45, 0x01]); // ESC E 1 加粗
      commands.addAll([0x1D, 0x21, 0x08]);
      commands.addAll(utf8.encode(line));
      commands.add(0x0A); // LF
      commands.addAll([0x1B, 0x45, 0x00]); // ESC E 0 取消加粗
    }
    
    // 块4: Note信息 - 左对齐，只加粗标准字体（12号）
    final notes = customerOrder['notes'] ?? [];
    if (notes.isNotEmpty) {
      commands.addAll([0x1B, 0x61, 0x00]); // ESC a 0 左对齐
      for (String line in notes) {
        commands.addAll([0x1B, 0x45, 0x01]); // ESC E 1 加粗
        commands.addAll([0x1D, 0x21, 0x09]);
        commands.addAll(utf8.encode(line));
        commands.add(0x0A); // LF
        commands.addAll([0x1B, 0x45, 0x00]); // ESC E 0 取消加粗
      }
    }
    
    // 块5: 总计和税费信息 - 左对齐，加粗字体
    for (String line in customerOrder['totals'] ?? []) {
      commands.addAll([0x1B, 0x61, 0x00]); // ESC a 0 左对齐
      commands.addAll([0x1B, 0x45, 0x01]); // ESC E 1 加粗
      commands.addAll([0x1D, 0x21, 0x08]);
      commands.addAll(utf8.encode(line));
      commands.add(0x0A); // LF
      commands.addAll([0x1B, 0x45, 0x00]); // ESC E 0 取消加粗
    }
    
    // 块6: 时间和结尾 - 左对齐，正常字体
    commands.addAll([0x1B, 0x61, 0x00]); // ESC a 0 左对齐
    for (String line in customerOrder['footer'] ?? []) {
      commands.addAll(utf8.encode(line));
      commands.add(0x0A); // LF
    }

    // 走纸和切纸
    commands.addAll([0x0A, 0x0A, 0x0A, 0x0A, 0x0A]); // 5行走纸
    commands.addAll([0x1D, 0x56, 0x01]); // GS V 1 切纸

    // ========== 后厨用小票 ==========
    commands.addAll([0x1B, 0x40]); // ESC @ 初始化
    
    // 解析后厨用小票内容
    final kitchenOrder = _parseKitchenReceipt(kitchenContent);
    
    // 块1: 标题和订单号 - 左对齐，正常字体
    commands.addAll([0x1B, 0x61, 0x00]); // ESC a 0 左对齐
    for (String line in kitchenOrder['header'] ?? []) {
      commands.addAll(utf8.encode(line));
      commands.add(0x0A); // LF
    }
    
    // 块2: 菜品项目 - 左对齐，倍高显示
    commands.addAll([0x1B, 0x61, 0x00]); // ESC a 0 左对齐
    for (String line in kitchenOrder['items'] ?? []) {
      commands.addAll([0x1D, 0x21, 0x11]); // GS ! 16 倍高
      commands.addAll(utf8.encode(line));
      commands.add(0x0A); // LF
      commands.addAll([0x1D, 0x21, 0x00]); // GS ! 0 还原字体
    }
    
    // 块3: 时间和结尾 - 左对齐，正常字体
    commands.addAll([0x1B, 0x61, 0x00]); // ESC a 0 左对齐
    for (String line in kitchenOrder['footer'] ?? []) {
      commands.addAll(utf8.encode(line));
      commands.add(0x0A); // LF
    }

    // 走纸和切纸
    commands.addAll([0x0A, 0x0A, 0x0A, 0x0A, 0x0A]); // 5行走纸
    commands.addAll([0x1D, 0x56, 0x01]); // GS V 1 切纸

    return commands;
  }

  /// 解析顾客用小票内容��分块返回
  Map<String, List<String>> _parseCustomerReceipt(String content) {
    final lines = content.split('\n');
    final result = {
      'header': <String>[],
      'orderInfo': <String>[],
      'items': <String>[],
      'notes': <String>[],
      'totals': <String>[],
      'footer': <String>[],
    };
    
    String currentSection = 'header';
    
    for (String line in lines) {
      if (line.trim().isEmpty) continue;
      
      if (line.contains('ORDER #')) {
        currentSection = 'orderInfo';
        result[currentSection]!.add(line);
      } else if (line.contains('--------------------------------') && currentSection == 'orderInfo') {
        result[currentSection]!.add(line);
        currentSection = 'items';
      } else if (line.contains('Note:')) {
        currentSection = 'notes';
        result[currentSection]!.add(line);
      } else if (line.contains('--------------------------------') && currentSection == 'items') {
        currentSection = 'totals';
        result[currentSection]!.add(line);
      } else if (line.contains('Order Time:')) {
        currentSection = 'footer';
        result[currentSection]!.add(line);
      } else if (line.contains('================================') && currentSection == 'totals') {
        result[currentSection]!.add(line);
        currentSection = 'footer';
      } else {
        result[currentSection]!.add(line);
      }
    }
    
    return result;
  }

  /// 解析后厨用小票内容，分块返回
  Map<String, List<String>> _parseKitchenReceipt(String content) {
    final lines = content.split('\n');
    final result = {
      'header': <String>[],
      'items': <String>[],
      'footer': <String>[],
    };
    
    String currentSection = 'header';
    
    for (String line in lines) {
      if (line.trim().isEmpty) continue;
      
      if (line.contains('ORDER #')) {
        result[currentSection]!.add(line);
      } else if (line.contains('--------------------------------') && currentSection == 'header') {
        result[currentSection]!.add(line);
        currentSection = 'items';
      } else if (line.contains('--------------------------------') && currentSection == 'items') {
        currentSection = 'footer';
        result[currentSection]!.add(line);
      } else if (line.contains('Order Time:') || line.contains('CLERK')) {
        currentSection = 'footer';
        result[currentSection]!.add(line);
      } else {
        result[currentSection]!.add(line);
      }
    }
    
    return result;
  }

  /// 测试打印样式命令（用于调试）
  Future<void> testPrintStyles() async {
    try {
      List<int> testCommands = [];

      // 基本初始化
      testCommands.addAll([0x1B, 0x40]); // ESC @ 初始化

      // 测试加粗命令
      testCommands.addAll([0x1B, 0x45, 0x01]); // ESC E 1 加粗开
      testCommands.addAll(utf8.encode("BOLD TEXT TEST\n"));
      testCommands.addAll([0x1B, 0x45, 0x00]); // ESC E 0 加粗关

      // 测试倍宽命令
      testCommands.addAll([0x1D, 0x21, 0x20]); // GS ! 32 倍宽
      testCommands.addAll(utf8.encode("DOUBLE WIDTH\n"));
      testCommands.addAll([0x1D, 0x21, 0x00]); // GS ! 0 还原

      // 测试倍高命令
      testCommands.addAll([0x1D, 0x21, 0x10]); // GS ! 16 倍高
      testCommands.addAll(utf8.encode("DOUBLE HEIGHT\n"));
      testCommands.addAll([0x1D, 0x21, 0x00]); // GS ! 0 还原

      // 正常内容
      testCommands.addAll(utf8.encode("Normal text\n"));

      // 测试走纸
      testCommands.addAll([0x0A, 0x0A, 0x0A, 0x0A, 0x0A]); // 5个换行

      // 切纸
      testCommands.addAll([0x1D, 0x56, 0x01]); // GS V 1 切纸

      await _sendToPrinterRaw(testCommands);
      _logger.i('样式测试打印发送成功');
    } catch (e) {
      _logger.e('样式测试打印失败: $e');
      rethrow;
    }
  }

  /// 专门测试走纸效果的方法（测试多种走纸命令）
  Future<void> testPaperFeed() async {
    try {
      List<int> testCommands = [];

      // 基本初始化
      testCommands.addAll([0x1B, 0x40]); // ESC @ 初始化

      // 测试内容1 - 普通换行
      testCommands.addAll(utf8.encode("=== 测试1: 普通换行 ===\n"));
      testCommands.addAll(utf8.encode("这是普通换行测���\n"));
      testCommands.addAll(utf8.encode("Line 1\n"));
      testCommands.addAll(utf8.encode("Line 2\n"));
      testCommands.addAll(utf8.encode("Line 3\n"));

      // 测试内容2 - 多个LF走纸
      testCommands.addAll(utf8.encode("=== 测试2: 5个LF走纸 ===\n"));
      testCommands.addAll([0x0A, 0x0A, 0x0A, 0x0A, 0x0A]); // 5个LF

      // 测试内容3 - ESC J n 走纸命令（如果支持）
      testCommands.addAll(utf8.encode("=== 测试3: ESC J 走纸命令 ===\n"));
      testCommands.addAll([0x1B, 0x4A, 60]); // ESC J 60 走纸约6mm

      // 测试内容4 - 更多LF走纸
      testCommands.addAll(utf8.encode("=== 测试4: 10个LF走纸 ===\n"));
      testCommands.addAll([0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A]); // 10个LF

      // 测试内容5 - ESC d n 走纸命令（另一种走纸命令）
      testCommands.addAll(utf8.encode("=== 测试5: ESC d 走纸命令 ===\n"));
      testCommands.addAll([0x1B, 0x64, 5]); // ESC d 5 走纸5行

      // 测试内容6 - 组合走纸
      testCommands.addAll(utf8.encode("=== 测试6: 组合走纸 ===\n"));
      testCommands.addAll([0x0A, 0x0A, 0x0A]); // 3个LF
      testCommands.addAll([0x1B, 0x4A, 40]); // ESC J 40
      testCommands.addAll([0x0A, 0x0A]); // 2个LF

      // 结束标记
      testCommands.addAll(utf8.encode("=== 走纸测试结束 ===\n"));

      // 最后大量走纸便于撕纸
      testCommands.addAll([0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A]); // 10个LF

      // 切纸
      testCommands.addAll([0x1D, 0x56, 0x01]); // GS V 1 切纸

      await _sendToPrinterRaw(testCommands);
      _logger.i('走纸测试打印发送成功');
    } catch (e) {
      _logger.e('走纸测试打印失败: $e');
      rethrow;
    }
  }

  /// 顾客用小票模板（默认实现，后续可通过API获取模板）
  Future<String> _generateCustomerReceiptTemplate(OrderModel order) async {
    final items = jsonDecode(order.items) as List;
    final StringBuffer content = StringBuffer();
    // 店铺信息（可扩展为从设置或API获取）
    content.writeln("----------Customer Rep---------");
    content.writeln("DAVE'S NOODLES");
    content.writeln("Shop 2/129 Wilson St");
    content.writeln("Burnie Tas. 7320");
    content.writeln("Phone -03 6431 8818");
    content.writeln("ABN 76 147 759 135");
    content.writeln("Tax Invoice /Receipt");
    content.writeln("================================");
    content.writeln("ORDER #${order.id}");
    content.writeln("--------------------------------");
    for (var item in items) {
      final name = item['name'] ?? '';
      final quantity = item['quantity'] ?? 1;
      final price = (item['price'] ?? 0).toDouble();
      final subtotal = quantity * price;
      content.writeln('${name.padRight(20)} x${quantity}  \$${price.toStringAsFixed(2)} = \$${subtotal.toStringAsFixed(2)}');

    }
    content.writeln("--------------------------------");
    content.writeln("CASH"); // 可扩展为实际支付方式
    content.writeln(" \$${order.totalAmount.toStringAsFixed(2)}");
    content.writeln("TAX SALES: \$${(order.totalAmount * 0.91).toStringAsFixed(2)}");
    content.writeln("G.S.T.: \$${(order.totalAmount * 0.09).toStringAsFixed(2)}");
    if (order.note != null) {
      content.writeln('Note: ${order.note}');
    }
    content.writeln("Order Time: ${_formatDateTime(order.orderTime)}");
    content.writeln("================================");
    return content.toString();
  }

  /// 后厨用小票模板（默认实现，后续可通过API获取模板���
  Future<String> _generateKitchenReceiptTemplate(OrderModel order) async {
    final items = jsonDecode(order.items) as List;
    final StringBuffer content = StringBuffer();
    content.writeln("----------Kitchen Rep-----------");
    content.writeln("ORDER #${order.id}");
    content.writeln("--------------------------------");
    for (var item in items) {
      final name = item['name'] ?? '';
      final quantity = item['quantity'] ?? 1;
      content.writeln('${name.toUpperCase()} x${quantity}');
    }
    content.writeln("--------------------------------");
    content.writeln("Order Time: ${_formatDateTime(order.orderTime)}");
    content.writeln("CLERK 001"); // 可扩展为实际操作员
    return content.toString();
  }
}
