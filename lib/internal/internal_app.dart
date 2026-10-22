import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'pages/order_page.dart';
import 'pages/report_page.dart';
import 'pages/settings_page.dart';
import 'pages/order_list_page.dart';
import 'pages/login_page.dart';
import '../../common/services/api_service.dart';
import '../../common/services/admin_password_service.dart';
import '../../common/services/order_match_service.dart';
import '../../common/services/settings_service.dart';
import '../../common/services/sync_service.dart';
import '../../common/services/print_service.dart';
import '../../common/services/language_service.dart';
import 'services/service_status_service.dart';
import 'widgets/printer_config_dialog.dart';
import 'widgets/server_config_dialog.dart';
import 'widgets/service_status_actions.dart';

class InternalApp extends StatefulWidget {
  const InternalApp({Key? key}) : super(key: key);

  @override
  _InternalAppState createState() => _InternalAppState();
}

class _InternalAppState extends State<InternalApp> {
  int _selectedIndex = 0;

  bool _isChecking = true;
  bool _isLoggedIn = false;

  final SettingsService _settingsService = SettingsService();
  final SyncService _syncService = SyncService();
  final PrintService _printService = PrintService();
  final ServiceStatusService _serviceStatusService = ServiceStatusService();

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
    return SettingsService.cleanUrlFormat(url);
  }

  Future<void> _refreshServiceStatus() async {
    if (_isCheckingStatus) return;
    _isCheckingStatus = true;

    try {
      final serviceStatus = await _serviceStatusService.fetchServiceStatus();

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
     final result = await showPrinterConfigDialog(
       context: context,
       settingsService: _settingsService,
       printService: _printService,
     );

     if (result == true) {
       await _refreshServiceStatus();
     }
   }

  Future<void> _showServerConfigDialog() async {
    final result = await showServerConfigDialog(
      context: context,
      settingsService: _settingsService,
      syncService: _syncService,
      cleanUrlFormat: _cleanUrlFormat,
    );

    if (result == true) {
      await _refreshServiceStatus();
    }
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
    // 点击直接跳转到订单管理 (OrderListPage)
    setState(() {
      _selectedIndex = 1;
    });
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
        title: Text('admin_mode'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('enter_admin_pwd'.tr),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              decoration: InputDecoration(
                labelText: 'pwd_label'.tr,
                border: const OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr),
          ),
          ElevatedButton(
            onPressed: () async {
              final password = passwordController.text;
              final isValid = await AdminPasswordService.verifyPassword(password);

              if (!mounted) return;
              if (isValid) {
                Navigator.pop(context);
                setState(() {
                  _isAdminMode = true;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('admin_mode_activated'.tr)),
                );
              } else {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('invalid_pwd'.tr),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('confirm'.tr),
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

    final List<Widget> appBarActions = buildServiceStatusActions(
      selectedIndex: _selectedIndex,
      orderMatchResult: _orderMatchResult,
      onShowOrderMatchDetails: _showOrderMatchDetailsDialog,
      isPrinterConnected: _isPrinterConnected,
      onOpenPrinterConfig: _showPrinterConfigDialog,
      isServerConnected: _isServerConnected,
      onOpenServerConfig: _showServerConfigDialog,
    );

    if (_isAdminMode) {
      appBarActions.addAll([
        ElevatedButton.icon(
          onPressed: _showChangePasswordDialog,
          icon: const Icon(Icons.lock),
          label: Text('change_pwd'.tr),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _exitAdminMode,
          icon: const Icon(Icons.exit_to_app),
          label: Text('exit_admin'.tr),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
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
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.restaurant_menu),
            label: 'nav_menu'.tr,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long),
            label: 'nav_orders'.tr,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.analytics),
            label: 'nav_reports'.tr,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings),
            label: 'nav_settings'.tr,
          ),
        ],
      ),
    );
  }
}
