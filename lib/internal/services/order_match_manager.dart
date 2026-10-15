import 'dart:async';
import 'package:logger/logger.dart';
import '../../common/services/order_match_service.dart';
import '../../common/services/settings_service.dart';

/// 订单匹配状态管理器
class OrderMatchManager {
  static final Logger _logger = Logger();
  late Timer _checkTimer;
  OrderMatchResult? _lastResult;
  bool _isChecking = false;

  final OrderMatchService _orderMatchService = OrderMatchService();
  final SettingsService _settingsService = SettingsService();

  OrderMatchResult? get lastResult => _lastResult;
  bool get isChecking => _isChecking;

  /// 初始化定时检查
  void initialize(Function(OrderMatchResult) onResultUpdated) {
    try {
      final settings = _settingsService.getSettings();
      final intervalMinutes = settings.orderMatchCheckIntervalMinutes;

      _checkTimer = Timer.periodic(
        Duration(minutes: intervalMinutes),
        (_) => performCheck(onResultUpdated),
      );

      // 立即执行一次检查
      performCheck(onResultUpdated);
    } catch (e) {
      _logger.e('[OrderMatchManager] 初始化失败: $e');
    }
  }

  /// 执行订单匹配检查
  Future<void> performCheck(Function(OrderMatchResult) onResultUpdated) async {
    if (_isChecking) return;

    _isChecking = true;

    try {
      final result = await _orderMatchService.verifyOrdersMatch();
      _lastResult = result;
      onResultUpdated(result);
    } catch (e) {
      _logger.e('[OrderMatchManager] 检查异常: $e');
      _isChecking = false;
      rethrow;
    } finally {
      // 无论成功或失败，都要重置检查状态，防止一直处于 "检查中"。
      _isChecking = false;
    }
  }

  /// 清理资源
  void dispose() {
    _checkTimer.cancel();
  }
}
