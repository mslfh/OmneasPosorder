import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

/// UI工具类
class UIHelper {
  static final UIHelper _instance = UIHelper._internal();

  late AudioPlayer _audioPlayer;

  factory UIHelper() => _instance;

  UIHelper._internal() {
    _audioPlayer = AudioPlayer();
  }

  /// 播放点击声音
  Future<void> playClickSound() async {
    try {
      await _audioPlayer.play(AssetSource('audio/click.mp3'));
    } catch (e) {
      // 忽略音效错误
    }
  }

  /// 显示确认对话框
  static Future<bool> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String content,
    String confirmText = '确认',
    String cancelText = '取消',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 显示提示消息
  static void showSnackBar(
    BuildContext context,
    String message, {
    Color backgroundColor = const Color.fromARGB(255, 32, 32, 32),
    int durationMillis = 2000,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: Duration(milliseconds: durationMillis),
      ),
    );
  }

  /// 动态计算标题字体大小
  static double calculateTitleFontSize(String title, double containerWidth) {
    final baseSize = 16.0;
    final maxSize = 18.0;
    final minSize = 10.0;

    final estimatedCharWidth = baseSize * 0.6;
    final availableWidth = containerWidth - 40;
    final maxCharsPerLine = (availableWidth / estimatedCharWidth).floor();

    if (title.length <= maxCharsPerLine) {
      return baseSize;
    } else if (title.length <= maxCharsPerLine * 2) {
      return (baseSize - 1).clamp(minSize, maxSize);
    } else {
      return (baseSize - 3).clamp(minSize, maxSize);
    }
  }

  /// 清理资源（由于UIHelper是单例，通常不需要手动清理，除非应用关闭）
  void dispose() {
    try {
      _audioPlayer.dispose();
    } catch (e) {
      // 忽略清理时的错误
    }
  }
}

/// 对话框工具类
class DialogHelper {
  /// 清空订单确认对话框
  static Future<bool> showClearOrderDialog(BuildContext context) async {
    return await UIHelper.showConfirmDialog(
      context,
      title: '清空订单',
      content: '确定要清空所有已点菜品吗？',
      confirmText: '确认',
      cancelText: '取消',
    );
  }

  /// 数量选择对话框
  static Future<int?> showQuantitySelectorDialog(BuildContext context) async {
    return await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('设置数量'),
        content: Text('选择要应用到最后添加菜品的数量：'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ...([1, 2, 3, 4, 6].map((quantity) => TextButton(
            onPressed: () => Navigator.pop(context, quantity),
            child: Text('x$quantity'),
          ))).toList(),
        ],
      ),
    );
  }
}

