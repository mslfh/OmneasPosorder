/// 全局安全的数值类型转化工具类
class NumberFormatUtils {
  /// 安全转为 int
  static int toInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim()) ?? fallback;
  }

  /// 安全转为 double
  static double toDouble(dynamic value, [double fallback = 0.0]) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim()) ?? fallback;
  }

  /// 格式化金额字符串（默认带 2 位小数）
  static String formatCurrency(double amount, {String symbol = '￥'}) {
    return '$symbol${amount.toStringAsFixed(2)}';
  }
}

/// DateTime 日期时间格式化扩展方法
extension DateTimeFormattingExtension on DateTime {
  /// 转换为标准日期时间字符串："2026-10-26 12:35:00"
  String toStandardDateTimeString() {
    return '${year}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} '
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
  }

  /// 转换为标准日期字符串："2026-10-26"
  String toStandardDateString() {
    return '${year}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }

  /// 转换为标准时间字符串："12:35"
  String toStandardTimeString() {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}

/// 服务器分页订单解析响应结果模型
class ParsedOrderPage {
  final List<Map<String, dynamic>> orders;
  final int currentPage;
  final int lastPage;
  final bool hasMore;

  ParsedOrderPage({
    required this.orders,
    required this.currentPage,
    required this.lastPage,
    required this.hasMore,
  });
}

/// 通用解析服务端返回的订单数据及分页信息 (兼容数组、Map 包装、Laravel 各种 Paginator 结构)
ParsedOrderPage parseOrderResponseData(dynamic payload) {
  List<Map<String, dynamic>> ordersList = [];
  int currentPage = 1;
  int lastPage = 1;
  bool hasMore = false;

  if (payload is Map<String, dynamic>) {
    final data = payload['data'];

    // 格式 B：payload['data'] 本身是一个分页对象 Map { "current_page": 1, "last_page": 3, "data": [...] }
    if (data is Map<String, dynamic>) {
      currentPage = NumberFormatUtils.toInt(data['current_page'] ?? data['page'], 1);
      lastPage = NumberFormatUtils.toInt(data['last_page'] ?? data['total_pages'], 1);
      hasMore = data['has_more'] == true || currentPage < lastPage;

      final innerList = data['data'] ?? data['items'] ?? data['records'];
      if (innerList is List) {
        ordersList = innerList.whereType<Map<String, dynamic>>().toList();
      }
    }
    // 格式 A 或 C：payload['data'] 是 List 数组
    else if (data is List) {
      ordersList = data.whereType<Map<String, dynamic>>().toList();

      final meta = payload['meta'] ?? payload['pagination'];
      if (meta is Map<String, dynamic>) {
        currentPage = NumberFormatUtils.toInt(meta['current_page'] ?? meta['page'], 1);
        lastPage = NumberFormatUtils.toInt(meta['last_page'] ?? meta['total_pages'], 1);
        hasMore = meta['has_more'] == true || currentPage < lastPage;
      } else if (payload.containsKey('has_more')) {
        hasMore = payload['has_more'] == true;
        currentPage = NumberFormatUtils.toInt(payload['page'], 1);
      }
    }
  } else if (payload is List) {
    ordersList = payload.whereType<Map<String, dynamic>>().toList();
  }

  return ParsedOrderPage(
    orders: ordersList,
    currentPage: currentPage,
    lastPage: lastPage,
    hasMore: hasMore || (currentPage < lastPage),
  );
}
