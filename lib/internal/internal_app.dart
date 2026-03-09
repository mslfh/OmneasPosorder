import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'pages/order_page.dart';
import 'pages/report_page.dart';
import 'pages/settings_page.dart';
import 'pages/order_list_page.dart';
import 'pages/login_page.dart';
import '../../common/services/api_service.dart';
import '../../common/services/admin_password_service.dart';

class InternalApp extends StatefulWidget {
  @override
  State<InternalApp> createState() => _InternalAppState();
}

class _InternalAppState extends State<InternalApp> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [
    OrderPage(),
    OrderListPage(),
    ReportPage(),
    SettingsPage(),
  ];

  bool _isChecking = true;
  bool _isLoggedIn = false;

  // Admin Mode related variables
  bool _isAdminMode = false;
  int _titleTapCount = 0;
  DateTime? _lastTitleTapTime;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
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
      OrderPage(isAdminMode: _isAdminMode),
      OrderListPage(),
      ReportPage(),
      SettingsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _onTitleTap,
          child: Text('Omneas POS'),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: _isAdminMode
            ? [
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
              ]
            : [],
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
