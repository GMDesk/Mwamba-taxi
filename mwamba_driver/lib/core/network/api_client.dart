import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/api_constants.dart';

class ApiClient {
  late final Dio dio;
  final _storage = const FlutterSecureStorage();

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _loginTimestampKey = 'login_timestamp';

  /// Session duration: 30 days
  static const Duration sessionDuration = Duration(days: 30);

  ApiClient() {
    dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final path = options.path;
        final isPublic = path.contains('register') ||
            path.contains('login') ||
            path.contains('otp') ||
            path.contains('token/refresh');
        if (!isPublic) {
          final token = await _storage.read(key: _accessKey);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final refreshed = await _refreshToken();
          if (refreshed) {
            final token = await _storage.read(key: _accessKey);
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            final response = await dio.fetch(error.requestOptions);
            return handler.resolve(response);
          }
        }
        handler.next(error);
      },
    ));

    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        error: true,
      ));
    }
  }

  Future<bool> _refreshToken() async {
    try {
      final refresh = await _storage.read(key: _refreshKey);
      if (refresh == null) return false;

      final resp = await Dio(BaseOptions(baseUrl: ApiConstants.baseUrl)).post(
        ApiConstants.refreshToken,
        data: {'refresh': refresh},
      );
      await _storage.write(key: _accessKey, value: resp.data['access']);
      return true;
    } catch (_) {
      await clearTokens();
      return false;
    }
  }

  Future<void> saveTokens(String access, String refresh) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  /// Force-stamp login time (call after login/register).
  Future<void> stampLoginTime() async {
    await _storage.write(
      key: _loginTimestampKey,
      value: DateTime.now().toIso8601String(),
    );
  }

  Future<void> clearTokens() async {
    await _storage.deleteAll();
  }

  Future<String?> getAccessToken() => _storage.read(key: _accessKey);

  Future<bool> hasTokens() async {
    final token = await _storage.read(key: _accessKey);
    return token != null;
  }

  /// Returns true if session is within the allowed 30-day duration.
  Future<bool> isSessionValid() async {
    final token = await _storage.read(key: _accessKey);
    if (token == null || token.isEmpty) return false;
    final stamp = await _storage.read(key: _loginTimestampKey);
    if (stamp == null) return false;
    final loginTime = DateTime.tryParse(stamp);
    if (loginTime == null) return false;
    return DateTime.now().difference(loginTime) < sessionDuration;
  }

  /// Remaining session time, or Duration.zero if expired.
  Future<Duration> remainingSession() async {
    final stamp = await _storage.read(key: _loginTimestampKey);
    if (stamp == null) return Duration.zero;
    final loginTime = DateTime.tryParse(stamp);
    if (loginTime == null) return Duration.zero;
    final remaining = sessionDuration - DateTime.now().difference(loginTime);
    return remaining.isNegative ? Duration.zero : remaining;
  }
}
