class PrinterStationModel {
  final String id;
  final String name;
  final String role; // 兼容保存选项字符串
  final String contentType; // 兼容保存选项字符串
  final bool printKitchen; // 后厨单
  final bool printFrontDesk; // 前台单
  final bool printCustomer; // 顾客单
  final String connectionType; // 'network', 'bluetooth', 'usb'
  final String? ip;
  final int port;
  final String? deviceAddress; // 蓝牙 MAC 地址/设备名 或 USB 端口名/打印机名
  final bool enableAutoPrint;
  final bool isEnabled;
  final DateTime createdAt;

  PrinterStationModel({
    required this.id,
    required this.name,
    String? role,
    String? contentType,
    bool? printKitchen,
    bool? printFrontDesk,
    bool? printCustomer,
    this.connectionType = 'network',
    this.ip = '192.168.1.100',
    this.port = 9100,
    this.deviceAddress,
    this.enableAutoPrint = true,
    this.isEnabled = true,
    DateTime? createdAt,
  })  : printKitchen = printKitchen ?? _parsePrintKitchen(contentType, role),
        printFrontDesk = printFrontDesk ?? _parsePrintFrontDesk(contentType, role),
        printCustomer = printCustomer ?? _parsePrintCustomer(contentType, role),
        role = role ??
            _buildOptionsStr(
              printKitchen ?? _parsePrintKitchen(contentType, role),
              printFrontDesk ?? _parsePrintFrontDesk(contentType, role),
              printCustomer ?? _parsePrintCustomer(contentType, role),
            ),
        contentType = contentType ??
            _buildOptionsStr(
              printKitchen ?? _parsePrintKitchen(contentType, role),
              printFrontDesk ?? _parsePrintFrontDesk(contentType, role),
              printCustomer ?? _parsePrintCustomer(contentType, role),
            ),
        createdAt = createdAt ?? DateTime.now();

  static String _buildOptionsStr(bool kitchen, bool frontDesk, bool customer) {
    final list = <String>[];
    if (kitchen) list.add('kitchen');
    if (frontDesk) list.add('front_desk');
    if (customer) list.add('customer');
    return list.isEmpty ? 'customer' : list.join(',');
  }

  static bool _parsePrintKitchen(String? contentType, String? role) {
    final ct = (contentType ?? '').toLowerCase();
    final r = (role ?? '').toLowerCase();
    if (ct.contains('kitchen') || r.contains('kitchen') || ct.contains('both') || r.contains('both')) {
      return true;
    }
    return false;
  }

  static bool _parsePrintFrontDesk(String? contentType, String? role) {
    final ct = (contentType ?? '').toLowerCase();
    final r = (role ?? '').toLowerCase();
    if (ct.contains('front_desk') || r.contains('front_desk') || ct.contains('both') || r.contains('both')) {
      return true;
    }
    return false;
  }

  static bool _parsePrintCustomer(String? contentType, String? role) {
    final ct = (contentType ?? '').toLowerCase();
    final r = (role ?? '').toLowerCase();
    if (ct.contains('customer') || r.contains('customer') || ct.contains('counter') || r.contains('counter') || ct.contains('both') || r.contains('both')) {
      return true;
    }
    return false;
  }

  static String mapRoleToContentType(String role) {
    return role;
  }

  Map<String, dynamic> toMap() {
    final optionsStr = _buildOptionsStr(printKitchen, printFrontDesk, printCustomer);
    return {
      'id': id,
      'name': name,
      'role': optionsStr,
      'content_type': optionsStr,
      'connection_type': connectionType,
      'ip': ip,
      'port': port,
      'device_address': deviceAddress,
      'enable_auto_print': enableAutoPrint ? 1 : 0,
      'is_enabled': isEnabled ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PrinterStationModel.fromMap(Map<String, dynamic> map) {
    final roleVal = map['role']?.toString() ?? 'counter';
    final ctVal = map['content_type']?.toString() ?? roleVal;

    final isKitchen = _parsePrintKitchen(ctVal, roleVal);
    final isFrontDesk = _parsePrintFrontDesk(ctVal, roleVal);
    final isCustomer = _parsePrintCustomer(ctVal, roleVal);

    return PrinterStationModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      role: roleVal,
      contentType: ctVal,
      printKitchen: isKitchen,
      printFrontDesk: isFrontDesk,
      printCustomer: isCustomer,
      connectionType: map['connection_type']?.toString() ?? 'network',
      ip: map['ip']?.toString(),
      port: (map['port'] is int)
          ? map['port']
          : int.tryParse(map['port']?.toString() ?? '9100') ?? 9100,
      deviceAddress: map['device_address']?.toString(),
      enableAutoPrint: map['enable_auto_print'] == 1 || map['enable_auto_print'] == true,
      isEnabled: map['is_enabled'] == 1 || map['is_enabled'] == true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  PrinterStationModel copyWith({
    String? id,
    String? name,
    String? role,
    String? contentType,
    bool? printKitchen,
    bool? printFrontDesk,
    bool? printCustomer,
    String? connectionType,
    String? ip,
    int? port,
    String? deviceAddress,
    bool? enableAutoPrint,
    bool? isEnabled,
    DateTime? createdAt,
  }) {
    return PrinterStationModel(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      contentType: contentType ?? this.contentType,
      printKitchen: printKitchen ?? this.printKitchen,
      printFrontDesk: printFrontDesk ?? this.printFrontDesk,
      printCustomer: printCustomer ?? this.printCustomer,
      connectionType: connectionType ?? this.connectionType,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      deviceAddress: deviceAddress ?? this.deviceAddress,
      enableAutoPrint: enableAutoPrint ?? this.enableAutoPrint,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get optionsDisplay {
    final list = <String>[];
    if (printKitchen) list.add('Kitchen Ticket');
    if (printFrontDesk) list.add('Front Desk Ticket');
    if (printCustomer) list.add('Customer Receipt');
    if (list.isEmpty) return 'No ticket selected';
    return list.join(' + ');
  }

  String get roleDisplay => optionsDisplay;

  String get contentTypeDisplay => optionsDisplay;

  String get connectionTypeDisplay {
    switch (connectionType) {
      case 'bluetooth':
        return '蓝牙';
      case 'usb':
        return 'USB';
      case 'network':
      default:
        return '局域网';
    }
  }
}
