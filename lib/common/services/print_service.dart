import 'dart:convert';
import 'dart:io';
import 'package:charset_converter/charset_converter.dart';
import '../../config/env.dart';

class PrintService {
  Socket? _socket;

  Future<void> connect() async {
    print('[PrintService] Connecting to printer: ${Env.printerIp}:9100');
    _socket = await Socket.connect(Env.printerIp, 9100);
    print('[PrintService] Connected');
  }

  Future<void> printReceipt({
    required List<Map<String, dynamic>> orderData,
    required double totalPrice,
    required double receivedAmount,
    required double change,
    int maxRetry = 3,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('*** RECEIPT ***');
    for (var item in orderData) {
      buffer.writeln('Item: ${item['product_id']}');
      if (item['options'] != null && item['options'].isNotEmpty) {
        for (var opt in item['options']) {
          buffer.writeln('  - ${opt['type']}: ${opt['option_id']}');
        }
      }
    }
    buffer.writeln('----------------');
    buffer.writeln('Total: ¥${totalPrice.toStringAsFixed(2)}');
    buffer.writeln('Received: ¥${receivedAmount.toStringAsFixed(2)}');
    buffer.writeln('Change: ¥${change.toStringAsFixed(2)}');
    buffer.writeln('Thank you!');
    buffer.writeln('\n\n\n');

    List<int> escposHeader = [0x1B, 0x40];
    List<int> escposCut = [0x1D, 0x56, 0x00];

    print('[PrintService] Encoding receipt to GB18030...');
    List<int> gbBytes = escposHeader +
      (await CharsetConverter.encode("gb18030", buffer.toString())) +
      escposCut;
    print('[PrintService] Encoded bytes length: ${gbBytes.length}');
    print('[PrintService] Bytes: $gbBytes');

    int retry = 0;
    while (retry < maxRetry) {
      try {
        if (_socket == null) await connect();
        print('[PrintService] Sending bytes to printer...');
        _socket?.add(gbBytes);
        await _socket?.flush();
        print('[PrintService] Data sent, waiting before closing socket...');
        await Future.delayed(const Duration(milliseconds: 500));
        await _socket?.close();
        print('[PrintService] Socket closed');
        _socket = null;
        break;
      } catch (e) {
        retry++;
        print('[PrintService] Print error: $e, retry $retry/$maxRetry');
        if (retry >= maxRetry) {
          print('Print failed after $maxRetry retries: $e');
        }
      }
    }
  }

  void printText(String text) async {
    if (_socket == null) await connect();
    List<int> bytes = text.codeUnits;
    _socket?.add(bytes);
    _socket?.flush();
  }

  void close() {
    _socket?.close();
    _socket = null;
  }
}
