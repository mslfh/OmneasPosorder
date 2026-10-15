import 'package:flutter/material.dart';

/// 标准化日期范围筛选工具栏
class DateRangeFilterBar extends StatelessWidget {
  /// 当前选中的日期范围
  final DateTimeRange selectedDateRange;

  /// 是否处于全部日期 (ALL) 模式
  final bool isAllDateMode;

  /// 当日期范围变更时的回调（由组件内部处理前/后天、前/后周、日历范围后触发）
  final ValueChanged<DateTimeRange> onDateRangeChanged;

  /// 当切换到全部日期 (ALL) 模式时的回调
  final VoidCallback onAllDateModeSelected;

  /// 日历可选最早日期，默认 2020-01-01
  final DateTime? firstDate;

  /// 日历可选最晚日期，默认 2100-01-01
  final DateTime? lastDate;

  const DateRangeFilterBar({
    Key? key,
    required this.selectedDateRange,
    required this.isAllDateMode,
    required this.onDateRangeChanged,
    required this.onAllDateModeSelected,
    this.firstDate,
    this.lastDate,
  }) : super(key: key);

  bool get _isSingleDay {
    if (isAllDateMode) return false;
    final start = selectedDateRange.start;
    final end = selectedDateRange.end;
    return start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
  }

  String _getDisplayText() {
    if (isAllDateMode) {
      return '全部订单 (ALL)';
    }

    final start = selectedDateRange.start;
    final end = selectedDateRange.end;
    final now = DateTime.now();
    final isToday = start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;

    if (_isSingleDay) {
      final dateStr =
          '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
      return isToday ? '$dateStr (今天)' : dateStr;
    }

    return '${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')} ~ ${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
  }

  void _shiftDay(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final anchor = isAllDateMode ? today : selectedDateRange.start;

    final target = anchor.add(Duration(days: days));
    final cleanTarget = DateTime(target.year, target.month, target.day);
    onDateRangeChanged(DateTimeRange(start: cleanTarget, end: cleanTarget));
  }

  void _shiftWeek({required bool isPrevious}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (isAllDateMode) {
      if (isPrevious) {
        onDateRangeChanged(DateTimeRange(
          start: today.subtract(const Duration(days: 7)),
          end: today,
        ));
      } else {
        onDateRangeChanged(DateTimeRange(
          start: today,
          end: today.add(const Duration(days: 7)),
        ));
      }
    } else {
      if (isPrevious) {
        final anchor = selectedDateRange.start;
        final start = anchor.subtract(const Duration(days: 7));
        onDateRangeChanged(DateTimeRange(
          start: DateTime(start.year, start.month, start.day),
          end: DateTime(anchor.year, anchor.month, anchor.day),
        ));
      } else {
        final anchor = selectedDateRange.end;
        final end = anchor.add(const Duration(days: 7));
        onDateRangeChanged(DateTimeRange(
          start: DateTime(anchor.year, anchor.month, anchor.day),
          end: DateTime(end.year, end.month, end.day),
        ));
      }
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: selectedDateRange,
      firstDate: firstDate ?? DateTime(2020),
      lastDate: lastDate ?? DateTime(2100),
      helpText: '选择订单日期范围',
      cancelText: '取消',
      confirmText: '确定',
      saveText: '确定',
    );

    if (picked != null) {
      final start =
          DateTime(picked.start.year, picked.start.month, picked.start.day);
      final end = DateTime(picked.end.year, picked.end.month, picked.end.day);
      onDateRangeChanged(DateTimeRange(start: start, end: end));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 前一周 (-1w)
          _buildNavBtn(
            label: '-1w',
            tooltip: '前一周(7天)',
            onPressed: () => _shiftWeek(isPrevious: true),
          ),
          const SizedBox(width: 4),
          // 前一天 (-1d)
          _buildNavBtn(
            label: '-1d',
            tooltip: '前一天',
            onPressed: () => _shiftDay(-1),
          ),
          const SizedBox(width: 6),

          // 中间: 日历范围选择按钮
          Expanded(
            child: InkWell(
              onTap: () => _selectDateRange(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                decoration: BoxDecoration(
                  color: isAllDateMode
                      ? Colors.blue.withOpacity(0.08)
                      : Colors.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isAllDateMode
                        ? Colors.blue.withOpacity(0.3)
                        : Colors.green.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.calendar_month,
                      size: 16,
                      color: isAllDateMode ? Colors.blue : Colors.green[800],
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _getDisplayText(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isAllDateMode
                              ? Colors.blue[900]
                              : Colors.green[900],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),
          // 后一天 (+1d)
          _buildNavBtn(
            label: '+1d',
            tooltip: '后一天',
            onPressed: () => _shiftDay(1),
          ),
          const SizedBox(width: 4),
          // 后一周 (+1w)
          _buildNavBtn(
            label: '+1w',
            tooltip: '后一周(7天)',
            onPressed: () => _shiftWeek(isPrevious: false),
          ),
          const SizedBox(width: 6),

          // ALL (全部) 按钮
          InkWell(
            onTap: onAllDateModeSelected,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isAllDateMode ? Colors.blue : Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'ALL',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isAllDateMode ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavBtn({
    required String label,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
