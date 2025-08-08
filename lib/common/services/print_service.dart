import 'dart:io';
import '../../config/env.dart';

class PrintService {
  Socket? _socket;

  Future<void> connect() async {
    _socket = await Socket.connect(Env.printerIp, 9100);
  }

  void printText(String text) async {
    if (_socket == null) await connect();
    // 简单转码为 GB18030，实际可用 charset_converter 包
    List<int> bytes = text.codeUnits;
    _socket?.add(bytes);
    _socket?.flush();
  }

  void close() {
    _socket?.close();
    _socket = null;
  }
}

