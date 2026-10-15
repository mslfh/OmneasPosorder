import 'package:flutter/material.dart';

import '../../common/services/order_match_service.dart';
import '../../common/services/language_service.dart';
import '../../common/services/sync_service.dart';

List<Widget> buildServiceStatusActions({
  required int selectedIndex,
  required OrderMatchResult? orderMatchResult,
  required VoidCallback onShowOrderMatchDetails,
  required bool isPrinterConnected,
  required VoidCallback onOpenPrinterConfig,
  required bool isServerConnected,
  required VoidCallback onOpenServerConfig,
}) {
  Widget buildStatusIconButton({
    required IconData icon,
    required bool isOnline,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: isOnline ? Colors.greenAccent : Colors.red),
    );
  }

  final printerTooltip = isPrinterConnected
      ? '${'printer_status'.tr}: ${'connected'.tr}'
      : '${'printer_status'.tr}: ${'disconnected'.tr}';
  final serverTooltip = isServerConnected
      ? '${'server_status'.tr}: ${'connected'.tr}'
      : '${'server_status'.tr}: ${'disconnected'.tr}';

  IconData matchIcon = Icons.verified;
  Color matchColor = Colors.greenAccent;
  String matchTooltip = 'match_details'.tr;

  if (orderMatchResult != null) {
    switch (orderMatchResult.severity) {
      case OrderMatchSeverity.green:
        matchIcon = Icons.verified;
        matchColor = Colors.greenAccent;
        matchTooltip = '订单对比：完全匹配';
        break;
      case OrderMatchSeverity.orange:
        matchIcon = Icons.warning_amber_rounded;
        matchColor = Colors.amberAccent;
        matchTooltip = '订单对比：存在未同步数据 (点击前往订单管理)';
        break;
      case OrderMatchSeverity.red:
        matchIcon = Icons.error_outline;
        matchColor = Colors.redAccent;
        matchTooltip = '订单对比：存在未落单或数据异常 (点击前往订单管理)';
        break;
    }
  }

  return [
    if (orderMatchResult != null)
      IconButton(
        tooltip: matchTooltip,
        onPressed: onShowOrderMatchDetails,
        icon: Icon(
          matchIcon,
          color: matchColor,
        ),
      ),
    buildStatusIconButton(
      icon: Icons.print,
      isOnline: isPrinterConnected,
      tooltip: printerTooltip,
      onPressed: onOpenPrinterConfig,
    ),
    ServiceConfigIconButton(
      isServerConnected: isServerConnected,
      tooltip: serverTooltip,
      onPressed: onOpenServerConfig,
    ),
  ];
}

class ServiceConfigIconButton extends StatefulWidget {
  final bool isServerConnected;
  final String tooltip;
  final VoidCallback onPressed;

  const ServiceConfigIconButton({
    super.key,
    required this.isServerConnected,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<ServiceConfigIconButton> createState() => _ServiceConfigIconButtonState();
}

class _ServiceConfigIconButtonState extends State<ServiceConfigIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;
  FetchOrdersStatus? _lastFetchStatus;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _blinkAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.1), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 0.1, end: 1.0), weight: 50),
    ]).animate(_blinkController);

    SyncService().fetchOrdersEventNotifier.addListener(_onFetchOrdersEvent);
  }

  @override
  void dispose() {
    SyncService().fetchOrdersEventNotifier.removeListener(_onFetchOrdersEvent);
    _blinkController.dispose();
    super.dispose();
  }

  void _onFetchOrdersEvent() {
    final event = SyncService().fetchOrdersEventNotifier.value;
    if (event == null || !mounted) return;

    setState(() {
      _lastFetchStatus = event.status;
    });

    if (event.status == FetchOrdersStatus.success) {
      _blinkController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    Color indicatorColor;
    if (_lastFetchStatus == FetchOrdersStatus.error) {
      indicatorColor = Colors.red;
    } else if (_lastFetchStatus == FetchOrdersStatus.success) {
      indicatorColor = Colors.greenAccent;
    } else {
      indicatorColor = widget.isServerConnected ? Colors.greenAccent : Colors.red;
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: widget.tooltip,
          onPressed: widget.onPressed,
          icon: Icon(
            Icons.cloud,
            color: widget.isServerConnected ? Colors.greenAccent : Colors.red,
          ),
        ),
        Positioned(
          right: 6,
          top: 6,
          child: AnimatedBuilder(
            animation: _blinkAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _blinkAnimation.value,
                child: child,
              );
            },
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: indicatorColor,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: indicatorColor.withOpacity(0.8),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
