import 'package:flutter/material.dart';
import 'internal/internal_app.dart';
import 'customer/customer_app.dart';

class OmneasApp extends StatelessWidget {
  const OmneasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Omneas Posorder',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: InternalApp(), // 默认服务员端，可切换为 CustomerApp()
    );
  }
}

