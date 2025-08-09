import 'package:hive/hive.dart';

part 'app_settings.g.dart';

@HiveType(typeId: 10)
class AppSettings {
  @HiveField(0)
  String apiServerUrl;

  @HiveField(1)
  String printerAddress;

  @HiveField(2)
  int printerPort;

  @HiveField(3)
  String printerType; // 'network', 'usb', 'bluetooth'

  @HiveField(4)
  bool enableAutoSync;

  @HiveField(5)
  bool enableAutoPrint;

  AppSettings({
    this.apiServerUrl = 'https://api.example.com',
    this.printerAddress = '192.168.1.100',
    this.printerPort = 9100,
    this.printerType = 'network',
    this.enableAutoSync = true,
    this.enableAutoPrint = true,
  });

  AppSettings copyWith({
    String? apiServerUrl,
    String? printerAddress,
    int? printerPort,
    String? printerType,
    bool? enableAutoSync,
    bool? enableAutoPrint,
  }) {
    return AppSettings(
      apiServerUrl: apiServerUrl ?? this.apiServerUrl,
      printerAddress: printerAddress ?? this.printerAddress,
      printerPort: printerPort ?? this.printerPort,
      printerType: printerType ?? this.printerType,
      enableAutoSync: enableAutoSync ?? this.enableAutoSync,
      enableAutoPrint: enableAutoPrint ?? this.enableAutoPrint,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiServerUrl': apiServerUrl,
      'printerAddress': printerAddress,
      'printerPort': printerPort,
      'printerType': printerType,
      'enableAutoSync': enableAutoSync,
      'enableAutoPrint': enableAutoPrint,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      apiServerUrl: json['apiServerUrl'] ?? 'https://api.example.com',
      printerAddress: json['printerAddress'] ?? '192.168.1.100',
      printerPort: json['printerPort'] ?? 9100,
      printerType: json['printerType'] ?? 'network',
      enableAutoSync: json['enableAutoSync'] ?? true,
      enableAutoPrint: json['enableAutoPrint'] ?? true,
    );
  }
}
