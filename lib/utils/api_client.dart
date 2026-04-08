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
      // baseUrl: "http://10.0.2.2:9000", // 模拟测试(模拟机)
      // baseUrl: "http://127.0.0.1:9000",   // 无线测试(真机)
      baseUrl: "http://10.96.54.158:9000",

      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      responseType: ResponseType.json,
    );

    _dio = Dio(options);

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // 💡 2. 核心修复：白名单接口（免登录）绝对不能带上旧的/无效的 Token！
        bool isAuthApi = options.path.contains('/api/auth/login') ||
            options.path.contains('/api/auth/face-login') ||
            options.path.contains('/api/auth/send-sms');

        if (isAuthApi) {
          // 确保请求头中干净，没有 Authorization
          options.headers.remove('Authorization');
        } else {
          // 💡 其他正常的业务接口，如果用户已登录，自动把 Token 塞入所有的请求头中
          if (globalToken != null && globalToken!.isNotEmpty) {
            options.headers["Authorization"] = globalToken;
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
        // print("❌ 请求异常: ${e.message}, 状态码: ${e.response?.statusCode}");

        // 当后端返回 401 (未登录或 Token 过期/无效) 时
        if (e.response?.statusCode == 401) {
          // 1. 清理内存中的 Token
          globalToken = null;

          // 2. 清理本地缓存的 Token，防止下次打开 APP 又自动登录
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('token');
          await prefs.remove('userId');
          await prefs.remove('userPhone');

          // 3. 使用全局路由键，强制清空路由栈并跳转到登录页
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
        String errorMsg = data['message'] ?? "未知服务器错误";
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