import 'package:flutter/material.dart';

import '../../common/services/order_match_service.dart';

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

  return [
    if (selectedIndex == 0 && orderMatchResult != null)
      IconButton(
        tooltip: '匹配详情',
        onPressed: onShowOrderMatchDetails,
        icon: Icon(
          orderMatchResult.isMatched ? Icons.verified : Icons.error_outline,
          color: orderMatchResult.isMatched ? Colors.greenAccent : Colors.red,
        ),
      ),
    buildStatusIconButton(
      icon: Icons.print,
      isOnline: isPrinterConnected,
      tooltip: isPrinterConnected ? 'Printer Connected' : 'Printer Disconnected',
      onPressed: onOpenPrinterConfig,
    ),
    buildStatusIconButton(
      icon: Icons.cloud,
      isOnline: isServerConnected,
      tooltip: isServerConnected ? 'Server Connected' : 'Server Disconnected',
      onPressed: onOpenServerConfig,
    ),
  ];
}

