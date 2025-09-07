import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'pages/order_page.dart';
import 'pages/report_page.dart';
import 'pages/settings_page.dart';
import 'pages/order_list_page.dart';
import 'pages/login_page.dart';
import '../../common/services/api_service.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text('Omneas POS'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _pages[_selectedIndex],
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
