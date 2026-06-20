import 'package:flutter/material.dart';

import '../../common/services/print_service.dart';
import '../../common/services/settings_service.dart';

Future<bool?> showPrinterConfigDialog({
  required BuildContext context,
  required SettingsService settingsService,
  required PrintService printService,
}) async {
  await settingsService.initialize();
  if (!context.mounted) return false;
  final currentSettings = settingsService.getSettings();

  final addressController = TextEditingController(text: currentSettings.printerAddress);
  final portController = TextEditingController(text: currentSettings.printerPort.toString());
  bool enableAutoPrint = currentSettings.enableAutoPrint;
  bool isTesting = false;

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Printer Configuration'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Printer Address',
                  hintText: '192.168.1.100',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Printer Port',
                  hintText: '9100',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable Auto Print'),
                value: enableAutoPrint,
                onChanged: (value) {
                  setDialogState(() {
                    enableAutoPrint = value;
                  });
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: isTesting
                ? null
                : () async {
                    final address = addressController.text.trim();
                    final port = int.tryParse(portController.text.trim());

                    if (address.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Printer address cannot be empty')),
                      );
                      return;
                    }

                    if (port == null || port <= 0 || port > 65535) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Invalid printer port')),
                      );
                      return;
                    }

                    setDialogState(() {
                      isTesting = true;
                    });

                    try {
                      printService.configurePrinter(printerIP: address, printerPort: port);
                      final isReady = await printService.checkPrinterStatus();

                      if (!dialogContext.mounted) return;

                      if (isReady) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text('Printer connection successful'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text('Printer connection failed'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } catch (e) {
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text('Test failed: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } finally {
                      if (dialogContext.mounted) {
                        setDialogState(() {
                          isTesting = false;
                        });
                      }
                    }
                  },
            icon: isTesting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined),
            label: Text(isTesting ? 'Testing...' : 'Test Printer'),
          ),
          ElevatedButton(
            onPressed: () async {
              final address = addressController.text.trim();
              final port = int.tryParse(portController.text.trim());

              if (address.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Printer address cannot be empty')),
                );
                return;
              }

              if (port == null || port <= 0 || port > 65535) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid printer port')),
                );
                return;
              }

              final updated = currentSettings.copyWith(
                printerAddress: address,
                printerPort: port,
                enableAutoPrint: enableAutoPrint,
              );

              await settingsService.saveSettings(updated);
              printService.configurePrinter(printerIP: address, printerPort: port);

              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext, true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Printer settings updated')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );

  addressController.dispose();
  portController.dispose();

  return result;
}


