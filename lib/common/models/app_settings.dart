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

  @HiveField(6)
  int syncTaskIntervalMinutes;

  @HiveField(7)
  int fetchRemoteOrdersIntervalSeconds;

  @HiveField(8)
  int printRetryTaskIntervalMinutes;

  @HiveField(9)
  int orderMatchCheckIntervalMinutes;

  AppSettings({
    this.apiServerUrl = 'http://127.0.0.1:8000/api',
    this.printerAddress = '192.168.1.100',
    this.printerPort = 9100,
    this.printerType = 'network',
    this.enableAutoSync = true,
    this.enableAutoPrint = true,
    this.syncTaskIntervalMinutes = 60,
    this.fetchRemoteOrdersIntervalSeconds = 5,
    this.printRetryTaskIntervalMinutes = 2,
    this.orderMatchCheckIntervalMinutes = 5,
  });

  /// 修复缺失或无效的字段值（用于向后兼容）
  AppSettings migrateIfNeeded() {
    return AppSettings(
      apiServerUrl: apiServerUrl.isNotEmpty ? apiServerUrl : 'http://127.0.0.1:8000/api',
      printerAddress: printerAddress.isNotEmpty ? printerAddress : '192.168.1.100',
      printerPort: printerPort > 0 ? printerPort : 9100,
      printerType: printerType.isNotEmpty ? printerType : 'network',
      enableAutoSync: enableAutoSync,
      enableAutoPrint: enableAutoPrint,
      syncTaskIntervalMinutes: syncTaskIntervalMinutes > 0 ? syncTaskIntervalMinutes : 5,
      fetchRemoteOrdersIntervalSeconds: fetchRemoteOrdersIntervalSeconds > 0 ? fetchRemoteOrdersIntervalSeconds : 5,
      printRetryTaskIntervalMinutes: printRetryTaskIntervalMinutes > 0 ? printRetryTaskIntervalMinutes : 2,
      orderMatchCheckIntervalMinutes: orderMatchCheckIntervalMinutes > 0 ? orderMatchCheckIntervalMinutes : 5,
    );
  }

  AppSettings copyWith({
    String? apiServerUrl,
    String? printerAddress,
    int? printerPort,
    String? printerType,
    bool? enableAutoSync,
    bool? enableAutoPrint,
    int? syncTaskIntervalMinutes,
    int? fetchRemoteOrdersIntervalSeconds,
    int? printRetryTaskIntervalMinutes,
    int? orderMatchCheckIntervalMinutes,
  }) {
    return AppSettings(
      apiServerUrl: apiServerUrl ?? this.apiServerUrl,
      printerAddress: printerAddress ?? this.printerAddress,
      printerPort: printerPort ?? this.printerPort,
      printerType: printerType ?? this.printerType,
      enableAutoSync: enableAutoSync ?? this.enableAutoSync,
      enableAutoPrint: enableAutoPrint ?? this.enableAutoPrint,
      syncTaskIntervalMinutes: syncTaskIntervalMinutes ?? this.syncTaskIntervalMinutes,
      fetchRemoteOrdersIntervalSeconds: fetchRemoteOrdersIntervalSeconds ?? this.fetchRemoteOrdersIntervalSeconds,
      printRetryTaskIntervalMinutes: printRetryTaskIntervalMinutes ?? this.printRetryTaskIntervalMinutes,
      orderMatchCheckIntervalMinutes: orderMatchCheckIntervalMinutes ?? this.orderMatchCheckIntervalMinutes,
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
      'syncTaskIntervalMinutes': syncTaskIntervalMinutes,
      'fetchRemoteOrdersIntervalSeconds': fetchRemoteOrdersIntervalSeconds,
      'printRetryTaskIntervalMinutes': printRetryTaskIntervalMinutes,
      'orderMatchCheckIntervalMinutes': orderMatchCheckIntervalMinutes,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      apiServerUrl: json['apiServerUrl'] ?? 'http://127.0.0.1:8000/api',
      printerAddress: json['printerAddress'] ?? '192.168.1.100',
      printerPort: json['printerPort'] ?? 9100,
      printerType: json['printerType'] ?? 'network',
      enableAutoSync: json['enableAutoSync'] ?? true,
      enableAutoPrint: json['enableAutoPrint'] ?? true,
      syncTaskIntervalMinutes: json['syncTaskIntervalMinutes'] ?? 5,
      fetchRemoteOrdersIntervalSeconds: json['fetchRemoteOrdersIntervalSeconds'] ?? 5,
      printRetryTaskIntervalMinutes: json['printRetryTaskIntervalMinutes'] ?? 2,
      orderMatchCheckIntervalMinutes: json['orderMatchCheckIntervalMinutes'] ?? 5,
    );
  }
}
