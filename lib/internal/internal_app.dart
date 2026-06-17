import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'pages/order_page.dart';
import 'pages/report_page.dart';
import 'pages/settings_page.dart';
import 'pages/order_list_page.dart';
import 'pages/login_page.dart';
import '../../common/services/api_service.dart';
import '../../common/services/admin_password_service.dart';
import '../../common/services/background_task_manager.dart';
import '../../common/services/order_match_service.dart';
import '../../common/services/settings_service.dart';
import '../../common/services/sync_service.dart';
import '../../common/services/print_service.dart';
import 'services/order_match_manager.dart';

class InternalApp extends StatefulWidget {
  @override
  State<InternalApp> createState() => _InternalAppState();
}

class _InternalAppState extends State<InternalApp> {
  int _selectedIndex = 0;

  bool _isChecking = true;
  bool _isLoggedIn = false;

  final SettingsService _settingsService = SettingsService();
  final SyncService _syncService = SyncService();
  final PrintService _printService = PrintService();

  bool _isPrinterConnected = false;
  bool _isServerConnected = false;
  bool _isCheckingStatus = false;
  OrderMatchResult? _orderMatchResult;
  Future<void> Function()? _requestOrderMatchCheck;

  // Admin Mode related variables
  bool _isAdminMode = false;
  int _titleTapCount = 0;
  DateTime? _lastTitleTapTime;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    _refreshServiceStatus();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _checkLoginStatus() async {
    final box = await Hive.openBox('authBox');
    final token = box.get('authToken');
    if (token != null && token is String && token.isNotEmpty) {
      ApiService().setAuthToken(token);
      setState(() {
        _isLoggedIn = true;
        _isChecking = false;
      });
    } else {
      setState(() {
        _isLoggedIn = false;
        _isChecking = false;
      });
    }
  }

  void _onLoginSuccess() async {
    final box = await Hive.openBox('authBox');
    final token = box.get('authToken');
    if (token != null && token is String && token.isNotEmpty) {
      ApiService().setAuthToken(token);
    }
    setState(() {
      _isLoggedIn = true;
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  String _cleanUrlFormat(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  Future<void> _refreshServiceStatus() async {
    if (_isCheckingStatus) return;
    _isCheckingStatus = true;

    try {
      final serviceStatus = await BackgroundTaskManager().checkServiceStatus();

      if (!mounted) return;
      setState(() {
        _isPrinterConnected = serviceStatus.isPrinterConnected;
        _isServerConnected = serviceStatus.isServerConnected;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isPrinterConnected = false;
        _isServerConnected = false;
      });
    } finally {
      _isCheckingStatus = false;
    }
  }

   Future<void> _showPrinterConfigDialog() async {
     await _settingsService.initialize();
     final currentSettings = _settingsService.getSettings();
 
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
               onPressed: isTesting ? null : () async {
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
                   _printService.configurePrinter(printerIP: address, printerPort: port);
                   final isReady = await _printService.checkPrinterStatus();

                   if (!mounted) return;

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
                   if (!mounted) return;
                   ScaffoldMessenger.of(dialogContext).showSnackBar(
                     SnackBar(
                       content: Text('Test failed: $e'),
                       backgroundColor: Colors.red,
                     ),
                   );
                 } finally {
                   if (mounted) {
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
 
                 await _settingsService.saveSettings(updated);
                 _printService.configurePrinter(printerIP: address, printerPort: port);
 
                 if (!mounted) return;
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
 
     if (result == true) {
       await _refreshServiceStatus();
     }
   }

  Future<void> _showServerConfigDialog() async {
    await _settingsService.initialize();
    final currentSettings = _settingsService.getSettings();
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
                final apiUrl = _cleanUrlFormat(apiUrlController.text.trim());
                if (apiUrl.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('API server URL cannot be empty')),
                  );
                  return;
                }

                setDialogState(() {});
                _syncService.configureBaseUrl(apiUrl);

                try {
                  final isConnected = await _syncService.checkNetworkConnectivity();
                  if (!mounted) return;

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
                  if (!mounted) return;
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
                final apiUrl = _cleanUrlFormat(apiUrlController.text.trim());
                if (apiUrl.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('API server URL cannot be empty')),
                  );
                  return;
                }

                final updated = currentSettings.copyWith(apiServerUrl: apiUrl);
                await _settingsService.saveSettings(updated);
                _syncService.configureBaseUrl(apiUrl);
                ApiService().updateBaseUrl(apiUrl);

                if (!mounted) return;
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

    if (result == true) {
      await _refreshServiceStatus();
    }
  }

  Widget _buildStatusIconButton({
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

  void _onOrderMatchStateChanged(
    OrderMatchResult? result,
    Future<void> Function()? requestCheck,
  ) {
    if (!mounted) return;
    setState(() {
      _orderMatchResult = result;
      _requestOrderMatchCheck = requestCheck;
    });
  }

  Future<void> _showOrderMatchDetailsDialog() async {
    final result = _orderMatchResult;
    if (result == null) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          result.isMatched ? '✓ 订单匹配成功' : '✗ 订单不匹配',
          style: TextStyle(
            color: result.isMatched ? Colors.green : Colors.red,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OrderMatchUIBuilder.buildDetailsHeader(result),
              const SizedBox(height: 12),
              if (result.serverData != null) ...[
                OrderMatchUIBuilder.buildDataCard(
                  title: '服务器数据',
                  data: result.serverData!,
                  accentColor: Colors.blue,
                ),
                const SizedBox(height: 12),
              ],
              if (result.localData != null) ...[
                OrderMatchUIBuilder.buildDataCard(
                  title: '本地数据',
                  data: result.localData!,
                  accentColor: Colors.orange,
                ),
                const SizedBox(height: 12),
              ],
              if (result.getMismatchedItems().isNotEmpty) ...[
                const Text(
                  '不匹配项',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ...result.getMismatchedItems().map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, size: 16, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item,
                            style: TextStyle(fontSize: 12, color: Colors.red[700]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  '所有字段均一致，无需修正。',
                  style: TextStyle(fontSize: 12, color: Colors.green[700]),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          if (_requestOrderMatchCheck != null)
            ElevatedButton.icon(
              onPressed: () async {
                final requestCheck = _requestOrderMatchCheck;
                Navigator.pop(dialogContext);
                if (requestCheck != null) {
                  await requestCheck();
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
        ],
      ),
    );
  }

  /// Handle title tap for admin mode activation
  void _onTitleTap() {
    final now = DateTime.now();

    // Reset count if more than 5 seconds have passed
    if (_lastTitleTapTime != null &&
        now.difference(_lastTitleTapTime!).inSeconds > 5) {
      _titleTapCount = 1;
    } else {
      _titleTapCount++;
    }

    _lastTitleTapTime = now;

    // Check if 5 taps within 5 seconds
    if (_titleTapCount == 5) {
      _titleTapCount = 0;
      _showAdminPasswordDialog();
    }
  }

  /// Show admin password verification dialog
  void _showAdminPasswordDialog() {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Admin Mode'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('请输入管理员密码'),
            SizedBox(height: 16),
            TextField(
              controller: passwordController,
              decoration: InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final password = passwordController.text;
              final isValid = await AdminPasswordService.verifyPassword(password);

              if (isValid) {
                Navigator.pop(context);
                setState(() {
                  _isAdminMode = true;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已进入管理模式')),
                );
              } else {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('密码错误'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('验证'),
          ),
        ],
      ),
    );
  }

  /// Show change password dialog
  void _showChangePasswordDialog() {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('修改管理员密码'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPasswordController,
                decoration: InputDecoration(
                  labelText: '当前密码',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              SizedBox(height: 16),
              TextField(
                controller: newPasswordController,
                decoration: InputDecoration(
                  labelText: '新密码',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                decoration: InputDecoration(
                  labelText: '确认新密码',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final oldPassword = oldPasswordController.text;
              final newPassword = newPasswordController.text;
              final confirmPassword = confirmPasswordController.text;

              if (newPassword.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('新密码不能为空')),
                );
                return;
              }

              if (newPassword != confirmPassword) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('两次输入的密码不一致')),
                );
                return;
              }

              final success = await AdminPasswordService.changePassword(
                oldPassword,
                newPassword,
              );

              Navigator.pop(context);

              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('密码修改成功'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('旧密码错误'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('修改'),
          ),
        ],
      ),
    );
  }

  /// Exit admin mode
  void _exitAdminMode() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('退出管理模式'),
        content: Text('确认要退出管理模式吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isAdminMode = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已退出管理模式')),
              );
            },
            child: Text('确认'),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isLoggedIn) {
      return LoginPage(onLoginSuccess: _onLoginSuccess);
    }

    // Update pages list with admin mode
    final pages = [
      OrderPage(
        isAdminMode: _isAdminMode,
        onOrderMatchStateChanged: _onOrderMatchStateChanged,
      ),
      OrderListPage(),
      ReportPage(),
      SettingsPage(),
    ];

    final List<Widget> appBarActions = [
      if (_selectedIndex == 0 && _orderMatchResult != null)
        IconButton(
          tooltip: '匹配详情',
          onPressed: _showOrderMatchDetailsDialog,
          icon: Icon(
            _orderMatchResult!.isMatched ? Icons.verified : Icons.error_outline,
            color: _orderMatchResult!.isMatched ? Colors.greenAccent : Colors.red,
          ),
        ),
      _buildStatusIconButton(
        icon: Icons.print,
        isOnline: _isPrinterConnected,
        tooltip: _isPrinterConnected ? 'Printer Connected' : 'Printer Disconnected',
        onPressed: _showPrinterConfigDialog,
      ),
      _buildStatusIconButton(
        icon: Icons.cloud,
        isOnline: _isServerConnected,
        tooltip: _isServerConnected ? 'Server Connected' : 'Server Disconnected',
        onPressed: _showServerConfigDialog,
      ),
    ];

    if (_isAdminMode) {
      appBarActions.addAll([
        ElevatedButton.icon(
          onPressed: _showChangePasswordDialog,
          icon: Icon(Icons.lock),
          label: Text('Change Password'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
        ),
        SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _exitAdminMode,
          icon: Icon(Icons.exit_to_app),
          label: Text('Exit Admin'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
        ),
        SizedBox(width: 8),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _onTitleTap,
          child: Text('Omneas POS'),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: appBarActions,
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.blue,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.restaurant_menu),
            label: 'Menu',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'Reports',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
