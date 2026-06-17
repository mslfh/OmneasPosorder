import 'package:flutter/material.dart';
import 'dart:async';
import '../../common/services/order_match_service.dart';
import '../../common/services/settings_service.dart';

/// 订单匹配状态管理器
class OrderMatchManager {
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
      print('[OrderMatchManager] 初始化失败: $e');
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
      print('[OrderMatchManager] 检查异常: $e');
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

/// 订单匹配UI渲染器
class OrderMatchUIBuilder {
  /// 构建数据行
  static Widget buildDataRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value.isEmpty ? '-' : value,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建数据卡片
  static Widget buildDataCard({
    required String title,
    required OrderMatchData data,
    required Color accentColor,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: accentColor),
          ),
          SizedBox(height: 10),
          buildDataRow('订单数量', data.onlineCount.toString()),
          buildDataRow('已同步数', data.onlineSyncedCount.toString()),
          buildDataRow('最新订单号', data.onlineLastOrderNo),
          if (data.latestOrderId != null) buildDataRow('最新 order_id', data.latestOrderId.toString()),
          if (data.latestRemoteOrderId != null) buildDataRow('最新 remote_order_id', data.latestRemoteOrderId.toString()),
          Divider(height: 16),
          buildDataRow('Terminal订单数', data.terminalCount.toString()),
          buildDataRow('Terminal已同步数', data.terminalSyncedCount.toString()),
          buildDataRow('Terminal最新号', data.terminalLastOrderNo),
        ],
      ),
    );
  }

  /// 构建悬浮按钮组
  static Widget buildFloatingActions({
    required OrderMatchResult? result,
    required bool isChecking,
    required VoidCallback onShowDetails,
    required VoidCallback onCheckNow,
  }) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(right: 16, bottom: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 只显示“匹配详情”按钮。将“立即检查”按钮移动到匹配详情对话框内，
            // 以避免屏幕上同时出现重复的检查入口。
            if (result != null) ...[
              FloatingActionButton.extended(
                heroTag: 'order_match_details_button',
                backgroundColor: result.isMatched ? Colors.green : Colors.red,
                foregroundColor: Colors.white,
                elevation: 4,
                onPressed: onShowDetails,
                icon: Icon(result.isMatched ? Icons.verified : Icons.info_outline),
                label: Text(result.isMatched ? '匹配详情' : 'X'),
              ),
              SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建详情头部
  static Widget buildDetailsHeader(OrderMatchResult result) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: result.isMatched ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: result.isMatched ? Colors.green[200]! : Colors.red[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.isMatched ? Icons.check_circle : Icons.error,
                color: result.isMatched ? Colors.green : Colors.red,
                size: 18,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.isMatched ? '当前订单数据已匹配' : '当前订单数据存在不匹配',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: result.isMatched ? Colors.green[700] : Colors.red[700],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '检查时间: ${result.lastCheckTime?.toString().split('.')[0] ?? '-'}',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          if (result.errorMessage != null) ...[
            SizedBox(height: 8),
            Text(
              result.errorMessage!,
              style: TextStyle(fontSize: 12, color: Colors.red[700]),
            ),
          ],
        ],
      ),
    );
  }
}

