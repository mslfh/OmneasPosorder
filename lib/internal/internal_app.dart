import 'package:flutter/material.dart';
import 'pages/order_page.dart';
import 'pages/history_page.dart';
import 'pages/report_page.dart';
import 'pages/settings_page.dart';

class InternalApp extends StatefulWidget {
  @override
  State<InternalApp> createState() => _InternalAppState();
}

class _InternalAppState extends State<InternalApp> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [
    OrderPage(),
    HistoryPage(),
    ReportPage(),
    SettingsPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Omneas Posorder')),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Order'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Report'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Setting'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
