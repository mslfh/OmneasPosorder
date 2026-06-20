import 'package:flutter/material.dart';

import '../../common/services/api_service.dart';
import '../../common/services/settings_service.dart';
import '../../common/services/sync_service.dart';

Future<bool?> showServerConfigDialog({
  required BuildContext context,
  required SettingsService settingsService,
  required SyncService syncService,
  required String Function(String) cleanUrlFormat,
}) async {
  await settingsService.initialize();
  if (!context.mounted) return false;
  final currentSettings = settingsService.getSettings();
  final apiUrlController = TextEditingController(text: currentSettings.apiServerUrl);

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Server Configuration'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: apiUrlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'API Server URL',
                  hintText: 'http://127.0.0.1:8000/api',
                  border: OutlineInputBorder(),
                ),
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
            onPressed: () async {
              final apiUrl = cleanUrlFormat(apiUrlController.text.trim());
              if (apiUrl.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('API server URL cannot be empty')),
                );
                return;
              }

              setDialogState(() {});
              syncService.configureBaseUrl(apiUrl);

              try {
                final isConnected = await syncService.checkNetworkConnectivity();
                if (!dialogContext.mounted) return;

                if (isConnected) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Server connection successful'),
                      backgroundColor: Colors.greenAccent,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Server connection failed'),
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
              }
            },
            icon: const Icon(Icons.cloud),
            label: const Text('Test Connection'),
          ),
          ElevatedButton(
            onPressed: () async {
              final apiUrl = cleanUrlFormat(apiUrlController.text.trim());
              if (apiUrl.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('API server URL cannot be empty')),
                );
                return;
              }

              final updated = currentSettings.copyWith(apiServerUrl: apiUrl);
              await settingsService.saveSettings(updated);
              syncService.configureBaseUrl(apiUrl);
              ApiService().updateBaseUrl(apiUrl);

              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext, true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Server settings updated')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );

  apiUrlController.dispose();
  return result;
}


