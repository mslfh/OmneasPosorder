import 'package:flutter/material.dart';

import '../../common/services/api_service.dart';
import '../../common/services/settings_service.dart';
import '../../common/services/sync_service.dart';
import '../../common/services/language_service.dart';
import '../../common/services/background_task_manager.dart';

Future<bool?> showServerConfigDialog({
  required BuildContext context,
  required SettingsService settingsService,
  required SyncService syncService,
  String Function(String)? cleanUrlFormat,
}) async {
  await settingsService.initialize();
  if (!context.mounted) return false;
  final currentSettings = settingsService.getSettings();

  final apiUrlController = TextEditingController(text: currentSettings.apiServerUrl);
  final fetchIntervalController = TextEditingController(text: currentSettings.fetchRemoteOrdersIntervalSeconds.toString());
  final matchIntervalController = TextEditingController(text: currentSettings.orderMatchCheckIntervalMinutes.toString());
  final urlCleaner = cleanUrlFormat ?? SettingsService.cleanUrlFormat;

  bool enableAutoSync = currentSettings.enableAutoSync;
  bool isTesting = false;
  bool isPulling = false;

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.cloud_outlined, color: Color(0xFF0284C7)),
                const SizedBox(width: 8),
                Text('server_config'.tr),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: apiUrlController,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'api_url_label'.tr,
                        hintText: 'api_url_hint'.tr,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isTesting
                                ? null
                                : () async {
                                    final apiUrl = urlCleaner(apiUrlController.text);
                                    if (apiUrl.isEmpty) return;

                                    setDialogState(() {
                                      isTesting = true;
                                    });

                                    try {
                                      ApiService().updateBaseUrlInternal(apiUrl);

                                      final isConnected = await syncService.checkNetworkConnectivity();
                                      if (!dialogContext.mounted) return;

                                      if (isConnected) {
                                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                                          SnackBar(
                                            content: Text('conn_success'.tr),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      } else {
                                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                                          SnackBar(
                                            content: Text('conn_failed'.tr),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (!dialogContext.mounted) return;
                                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                                        SnackBar(
                                          content: Text('${'conn_failed'.tr}: $e'),
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
                                : const Icon(Icons.wifi_find_rounded, size: 18),
                            label: Text(isTesting ? 'testing'.tr : 'test_connection'.tr),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isPulling
                                ? null
                                : () async {
                                    final apiUrl = urlCleaner(apiUrlController.text);
                                    if (apiUrl.isNotEmpty) {
                                      ApiService().updateBaseUrlInternal(apiUrl);
                                    }

                                    setDialogState(() {
                                      isPulling = true;
                                    });

                                    try {
                                      await syncService.fetchAndLandNewRemoteOrders();
                                      if (!dialogContext.mounted) return;
                                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                                        SnackBar(
                                          content: Text('pull_all'.tr),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    } catch (e) {
                                      if (!dialogContext.mounted) return;
                                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                                        SnackBar(
                                          content: Text('Error: $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    } finally {
                                      if (dialogContext.mounted) {
                                        setDialogState(() {
                                          isPulling = false;
                                        });
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                            ),
                            icon: isPulling
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.cloud_download, size: 18),
                            label: Text('pull'.tr.toUpperCase()),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('auto_sync'.tr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text('auto_sync_desc'.tr, style: const TextStyle(fontSize: 12)),
                      value: enableAutoSync,
                      onChanged: (val) {
                        setDialogState(() {
                          enableAutoSync = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: fetchIntervalController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'fetch_interval'.tr,
                              suffixText: 'fetch_interval_unit'.tr,
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: matchIntervalController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'match_interval'.tr,
                              suffixText: 'match_interval_unit'.tr,
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text('cancel'.tr),
              ),
              ElevatedButton(
                onPressed: () async {
                  final apiUrl = urlCleaner(apiUrlController.text);
                  if (apiUrl.isEmpty) return;

                  final fetchInterval = int.tryParse(fetchIntervalController.text.trim()) ?? 5;
                  final matchInterval = int.tryParse(matchIntervalController.text.trim()) ?? 5;

                  final updated = currentSettings.copyWith(
                    apiServerUrl: apiUrl,
                    enableAutoSync: enableAutoSync,
                    fetchRemoteOrdersIntervalSeconds: fetchInterval > 0 ? fetchInterval : 5,
                    orderMatchCheckIntervalMinutes: matchInterval > 0 ? matchInterval : 5,
                  );

                  await settingsService.saveSettings(updated);
                  await BackgroundTaskManager().refreshScheduledTasks();

                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext, true);
                },
                child: Text('save'.tr),
              ),
            ],
          );
        },
      );
    },
  );

  apiUrlController.dispose();
  fetchIntervalController.dispose();
  matchIntervalController.dispose();
  return result;
}
