import 'dart:async';
import 'package:flutter/material.dart';

/// 顶部悬浮 Toast 提示组件（主流 App 风格，置顶显示不遮挡底部操作区，支持点按即刻消除）
class TopToastWidget extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final IconData? icon;
  final Duration duration;
  final VoidCallback onDismiss;

  const TopToastWidget({
    super.key,
    required this.message,
    required this.backgroundColor,
    this.icon,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<TopToastWidget> createState() => _TopToastWidgetState();
}

class _TopToastWidgetState extends State<TopToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -0.8),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    ));

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _controller.forward();

    _dismissTimer = Timer(widget.duration, () {
      _dismiss();
    });
  }

  void _dismiss() async {
    if (!mounted) return;
    _dismissTimer?.cancel();
    await _controller.reverse();
    if (mounted) {
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    IconData displayIcon = widget.icon ?? Icons.info_outline;
    if (widget.icon == null) {
      if (widget.backgroundColor == Colors.green ||
          widget.backgroundColor == Colors.green[800] ||
          widget.backgroundColor == Colors.teal) {
        displayIcon = Icons.check_circle_rounded;
      } else if (widget.backgroundColor == Colors.red ||
          widget.backgroundColor == Colors.deepOrange ||
          widget.backgroundColor == Colors.redAccent) {
        displayIcon = Icons.error_outline_rounded;
      } else if (widget.backgroundColor == Colors.orange ||
          widget.backgroundColor == Colors.amber ||
          widget.backgroundColor == Colors.orange[800]) {
        displayIcon = Icons.warning_amber_rounded;
      }
    }

    final topPadding = MediaQuery.of(context).padding.top + 14.0;

    return Positioned(
      top: topPadding,
      left: 0,
      right: 0,
      child: Material(
        type: MaterialType.transparency,
        child: Align(
          alignment: Alignment.topCenter,
          child: SlideTransition(
            position: _offsetAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: GestureDetector(
                onTap: _dismiss,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: widget.backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.22),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(displayIcon, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.close, color: Colors.white.withOpacity(0.7), size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
