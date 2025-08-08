import 'package:dio/dio.dart';
import '../../config/env.dart';

class ApiService {
  final Dio _dio = Dio(BaseOptions(baseUrl: Env.apiBaseUrl));

  Future<Response> get(String path, {Map<String, dynamic>? params}) async {
    return await _dio.get(path, queryParameters: params);
  }

  Future<Response> post(String path, Map<String, List<Map<String, Object>>> map, {dynamic data}) async {
    return await _dio.post(path, data: data);
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
