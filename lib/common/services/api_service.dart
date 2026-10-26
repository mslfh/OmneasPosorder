import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'settings_service.dart';

class ApiService {
  static final Logger _logger = Logger();
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    _initializeDio();
  }

  static final SettingsService _settingsService = SettingsService();
  late Dio _dio;
  String? _authToken; // token 字段

  bool get isBaseUrlConfigured => _dio.options.baseUrl.trim().isNotEmpty;

  String _normalizeBaseUrl(String rawUrl) {
    var clean = SettingsService.cleanUrlFormat(rawUrl);
    if (clean.isNotEmpty && !clean.endsWith('/')) {
      clean += '/';
    }
    return clean;
  }

  String _normalizePath(String path) {
    return path.startsWith('/') ? path.substring(1) : path;
  }

  Options _buildOptions({Map<String, dynamic>? extraHeaders}) {
    final headers = Map<String, dynamic>.from(_dio.options.headers);
    headers['Accept'] = 'application/json';
    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }
    return Options(
      headers: headers,
      validateStatus: (status) => status != null && status < 500,
    );
  }

  void _initializeDio() {
    final settings = _settingsService.getSettings();
    final baseUrl = _normalizeBaseUrl(settings.apiServerUrl);
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: _authToken != null ? {'Authorization': 'Bearer $_authToken'} : null,
    ));
  }

  /// 设置token并更新header
  void setAuthToken(String token) {
    _authToken = token;
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// 清除token并移除Authorization header
  void clearAuthToken() {
    _authToken = null;
    try {
      _dio.options.headers.remove('Authorization');
    } catch (_) {}
  }

  /// 仅更新内部 Dio BaseUrl（供 SettingsService 内部调用）
  void updateBaseUrlInternal(String baseUrl) {
    _dio.options.baseUrl = _normalizeBaseUrl(baseUrl);
  }

  /// 更新 API 基础 URL，并保存到数据库
  Future<void> updateBaseUrl(String baseUrl) async {
    final cleanUrl = _normalizeBaseUrl(baseUrl);
    _dio.options.baseUrl = cleanUrl;
    await _settingsService.updateApiServerUrl(SettingsService.cleanUrlFormat(baseUrl));
  }

  Future<Response> get(String path, {Map<String, dynamic>? params}) async {
    if (_dio.options.baseUrl.trim().isEmpty) {
      throw Exception('API server URL is not configured');
    }
    final fixedPath = _normalizePath(path);
    final options = _buildOptions();
    _logger.d('[API] GET url: ${_dio.options.baseUrl}$fixedPath | params: ${params ?? "null"}');
    final response = await _dio.get(
      fixedPath,
      queryParameters: params,
      options: options,
    );
    _logger.d('[API] response.statusCode: ${response.statusCode}');
    return response;
  }

  Future<Response> post(String path, {dynamic data}) async {
    if (_dio.options.baseUrl.trim().isEmpty) {
      throw Exception('API server URL is not configured');
    }
    final fixedPath = _normalizePath(path);
    final options = _buildOptions();
    _logger.d('[API] POST url: ${_dio.options.baseUrl}$fixedPath');
    return await _dio.post(fixedPath, data: data, options: options);
  }

  Future<Response> put(String path, {dynamic data}) async {
    if (_dio.options.baseUrl.trim().isEmpty) {
      throw Exception('API server URL is not configured');
    }
    try {
      final fixedPath = _normalizePath(path);
      final options = _buildOptions();
      return await _dio.put(fixedPath, data: data, options: options);
    } catch (e) {
      throw Exception('PUT请求失败: $e');
    }
  }

  Future<Response> delete(String path, {dynamic data}) async {
    if (_dio.options.baseUrl.trim().isEmpty) {
      throw Exception('API server URL is not configured');
    }
    try {
      final fixedPath = _normalizePath(path);
      final options = _buildOptions();
      return await _dio.delete(fixedPath, data: data, options: options);
    } catch (e) {
      throw Exception('DELETE请求失败: $e');
    }
  }

  Future<Response> patch(String path, {dynamic data}) async {
    if (_dio.options.baseUrl.trim().isEmpty) {
      throw Exception('API server URL is not configured');
    }
    try {
      final fixedPath = _normalizePath(path);
      final options = _buildOptions();
      return await _dio.patch(fixedPath, data: data, options: options);
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
