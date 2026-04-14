import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 💡 引入 SharedPreferences
import '../main.dart';

/// 统一的网络请求工具类
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  late Dio _dio;

  // 💡 1. 新增：全局保存当前登录的 userId
  static String? globalToken;

  factory ApiClient() => _instance;

  ApiClient._internal() {
    BaseOptions options = BaseOptions(
      baseUrl: "http://43.136.23.112:9000", // 模拟测试(模拟机)/
      // baseUrl: "http://127.0.0.1:9000",   // 无线测试(真机)
      // baseUrl: "http://10.96.54.158:9000",

      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      responseType: ResponseType.json,
    );

    _dio = Dio(options);

    _dio.interceptors.add(InterceptorsWrapper(
      // 加上 async，因为我们要异步读取本地缓存
      onRequest: (options, handler) async {
        bool isAuthApi = options.path.contains('/api/auth/login') ||
            options.path.contains('/api/auth/face-login') ||
            options.path.contains('/api/auth/send-sms');

        if (isAuthApi) {
          // 白名单接口，确保请求头干净
          options.headers.remove('Authorization');
        } else {
          // 每次请求前，直接从 SharedPreferences 拿最新的 Token
          // 这样即使重启 APP，只要没退出登录，就绝不会丢 Token
          final prefs = await SharedPreferences.getInstance();
          String? token = prefs.getString('token');

          if (token != null && token.isNotEmpty) {
            options.headers["Authorization"] = token;
          }
        }
        // print("➡️ 发起请求: ${options.method} ${options.path}");
        // print("📦 请求参数: ${options.data ?? options.queryParameters}");
        // print("🎫 请求头: ${options.headers}");
        return handler.next(options);
      },
      onResponse: (response, handler) {
        // print("✅ 收到响应: ${response.data}");
        return handler.next(response);
      },
      onError: (DioException e, handler) async {
        // 当后端返回 401 (未登录或 Token 过期/无效) 时
        if (e.response?.statusCode == 401) {
          // 清理本地缓存的 Token，防止无限死循环
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('token');
          await prefs.remove('userId');
          await prefs.remove('userPhone');

          // 强制清空路由栈并跳转到登录页
          if (navigatorKey.currentState != null) {
            navigatorKey.currentState!.pushNamedAndRemoveUntil('/login', (route) => false);
          }
        }
        return handler.next(e);
      },
    ));
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      var response = await _dio.get(path, queryParameters: queryParameters);
      return _handleResponse(response);
    } catch (e) {
      rethrow;
    }
  }

  Future<dynamic> post(String path, {dynamic data, Options? options}) async {
    try {
      // 支持传入自定义 options（比如强制覆盖 headers）
      var response = await _dio.post(path, data: data, options: options);
      return _handleResponse(response);
    } catch (e) {
      rethrow;
    }
  }

  Future<dynamic> put(String path, {dynamic data}) async {
    try {
      var response = await _dio.put(path, data: data);
      return _handleResponse(response);
    } catch (e) {
      rethrow;
    }
  }

  Future<dynamic> delete(String path) async {
    try {
      var response = await _dio.delete(path);
      return _handleResponse(response);
    } catch (e) {
      rethrow;
    }
  }

  dynamic _handleResponse(Response response) {
    final data = response.data;
    if (data == null) {
      throw Exception("空响应");
    }

    if (data is Map<String, dynamic>) {
      if (data.containsKey('code')) {
        if (data['code'] == 200) {
          return data['data'];
        }
        // 优先解析 'msg'，防止后端报错时前端拿到 null
        String errorMsg = data['msg'] ?? data['message'] ?? "未知服务器错误";
        throw Exception(errorMsg);
      }
      return data;
    }

    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        throw Exception(data);
      }
    }

    return data;
  }
}