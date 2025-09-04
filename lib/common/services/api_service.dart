import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'settings_service.dart';
import '../../config/env.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    _initializeDio();
  }

  static final SettingsService _settingsService = SettingsService();
  late Dio _dio;
  String? _authToken; // 新增token字段


  void _initializeDio() async {
    String? baseUrl;
    try {
      final box = await Hive.openBox('authBox');
      final hiveUrl = box.get('apiServerUrl') as String?;
      if (hiveUrl != null && hiveUrl.isNotEmpty) {
        baseUrl = hiveUrl;
      }
    } catch (_) {}
    if (baseUrl == null) {
      final settings = _settingsService.getSettings();
      baseUrl = settings.apiServerUrl.isNotEmpty ? settings.apiServerUrl : Env.apiBaseUrl;
    }
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: Duration(seconds: 30),
      receiveTimeout: Duration(seconds: 30),
      headers: _authToken != null ? {'Authorization': 'Bearer $_authToken'} : null,
    ));
  }

  /// 设置token并更新header
  void setAuthToken(String token) {
    _authToken = token;
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// 更新API基础URL，并保存到Hive
  void updateBaseUrl(String baseUrl) async {
    _dio.options.baseUrl = baseUrl;
    try {
      final box = await Hive.openBox('authBox');
      await box.put('apiServerUrl', baseUrl);
    } catch (_) {}
  }

  Future<Response> get(String path, {Map<String, dynamic>? params}) async {
    // 保证baseUrl以/结尾，path不以/开头
    String fixedPath = path.startsWith('/') ? path.substring(1) : path;
    if (!_dio.options.baseUrl.endsWith('/')) {
      _dio.options.baseUrl = _dio.options.baseUrl + '/';
    }
    final options = Options(headers: Map<String, dynamic>.from(_dio.options.headers ?? {}));
    options.headers ??= {};
    options.headers?['Accept'] = 'application/json';
    print('[API] GET url: ' + _dio.options.baseUrl + fixedPath);
    print('[API] headers: ' + options.headers.toString());
    print('[API] params: ' + (params?.toString() ?? 'null'));
    final response = await _dio.get(
      fixedPath,
      queryParameters: params,
      options: options.copyWith(
        validateStatus: (status) => status != null && status < 500, // 允许404
      ),
    );
    print('[API] response.statusCode: ' + response.statusCode.toString());
    print('[API] response.headers: ' + response.headers.toString());
    return response;
  }

  Future<Response> post(String path, {dynamic data}) async {
    // 保证baseUrl以/结尾，path不以/开头
    String fixedPath = path.startsWith('/') ? path.substring(1) : path;
    if (!_dio.options.baseUrl.endsWith('/')) {
      _dio.options.baseUrl = _dio.options.baseUrl + '/';
    }
    final options = Options(headers: Map<String, dynamic>.from(_dio.options.headers ?? {}));
    print('[API] POST url: ' + _dio.options.baseUrl + fixedPath);
    print('[API] headers: ' + options.headers.toString());
    print('[API] data: ' + (data?.toString() ?? 'null'));
    return await _dio.post(fixedPath, data: data, options: options);
  }

  Future<Response> put(String path, {dynamic data}) async {
    try {
      return await _dio.put(path, data: data);
    } catch (e) {
      throw Exception('PUT请求失败: $e');
    }
  }

  Future<Response> delete(String path, {dynamic data}) async {
    try {
      return await _dio.delete(path, data: data);
    } catch (e) {
      throw Exception('DELETE请求失败: $e');
    }
  }

  Future<Response> patch(String path, {dynamic data}) async {
    try {
      return await _dio.patch(path, data: data);
    } catch (e) {
      throw Exception('PATCH请求失败: $e');
    }
  }

  // 统一异常处理
  Future<Response> safeRequest(Future<Response> Function() request) async {
    try {
      return await request();
    } catch (e) {
      throw Exception('网络请求失败: $e');
    }
  }
}