class PrinterStationModel {
  final String id;
  final String name;
  final String role; // 'counter', 'kitchen', 'both'
  final String contentType; // 'customer_receipt', 'kitchen_ticket', 'both'
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
    this.role = 'counter',
    String? contentType,
    this.connectionType = 'network',
    this.ip = '192.168.1.100',
    this.port = 9100,
    this.deviceAddress,
    this.enableAutoPrint = true,
    this.isEnabled = true,
    DateTime? createdAt,
  })  : contentType = contentType ?? mapRoleToContentType(role),
        createdAt = createdAt ?? DateTime.now();

  static String mapRoleToContentType(String role) {
    switch (role) {
      case 'kitchen':
        return 'kitchen_ticket';
      case 'both':
        return 'both';
      case 'counter':
      default:
        return 'customer_receipt';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'content_type': mapRoleToContentType(role),
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
    return PrinterStationModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      role: roleVal,
      contentType: map['content_type']?.toString() ?? mapRoleToContentType(roleVal),
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
    String? connectionType,
    String? ip,
    int? port,
    String? deviceAddress,
    bool? enableAutoPrint,
    bool? isEnabled,
    DateTime? createdAt,
  }) {
    final updatedRole = role ?? this.role;
    return PrinterStationModel(
      id: id ?? this.id,
      name: name ?? this.name,
      role: updatedRole,
      contentType: contentType ?? mapRoleToContentType(updatedRole),
      connectionType: connectionType ?? this.connectionType,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      deviceAddress: deviceAddress ?? this.deviceAddress,
      enableAutoPrint: enableAutoPrint ?? this.enableAutoPrint,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get roleDisplay {
    switch (role) {
      case 'kitchen':
        return '后厨 (后厨小票)';
      case 'both':
        return '前台+后厨 (顾客+后厨小票)';
      case 'counter':
      default:
        return '前台 (顾客小票)';
    }
  }

  String get contentTypeDisplay {
    switch (contentType) {
      case 'kitchen_ticket':
        return '后厨小票';
      case 'both':
        return '顾客小票+后厨小票';
      case 'customer_receipt':
      default:
        return '顾客小票';
    }
  }

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
