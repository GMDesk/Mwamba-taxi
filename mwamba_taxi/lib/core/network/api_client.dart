import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/api_constants.dart';

class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _loginTimestampKey = 'login_timestamp';

  /// Session duration: 30 days
  static const Duration sessionDuration = Duration(days: 30);

  static const _publicPaths = [
    ApiConstants.login,
    ApiConstants.registerPassenger,
    ApiConstants.requestOtp,
    ApiConstants.verifyOtp,
    ApiConstants.refreshToken,
    ApiConstants.nearbyDrivers,
  ];

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (_publicPaths.any((p) => options.path.contains(p))) {
          return handler.next(options);
        }
        final token = await getAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // Don't attempt token refresh for public endpoints (login, register, etc.)
        if (_publicPaths.any((p) => error.requestOptions.path.contains(p))) {
          return handler.next(error);
        }
        if (error.response?.statusCode == 401) {
          final refreshed = await _tryRefreshToken();
          if (refreshed) {
            final token = await getAccessToken();
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            try {
              final response = await _dio.fetch(error.requestOptions);
              return handler.resolve(response);
            } catch (e) {
              return handler.next(error);
            }
          }
        }
        handler.next(error);
      },
    ));

    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        error: true,
      ));
    }
  }

  Dio get dio => _dio;

  Future<String?> getAccessToken() => _storage.read(key: _accessTokenKey);
  Future<String?> getRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _storage.write(key: _accessTokenKey, value: access);
    await _storage.write(key: _refreshTokenKey, value: refresh);
    // Stamp login time only on first save (login), not on token refresh
    final existing = await _storage.read(key: _loginTimestampKey);
    if (existing == null) {
      await _storage.write(
        key: _loginTimestampKey,
        value: DateTime.now().toIso8601String(),
      );
    }
  }

  /// Force-stamp login time (call after login/register).
  Future<void> stampLoginTime() async {
    await _storage.write(
      key: _loginTimestampKey,
      value: DateTime.now().toIso8601String(),
    );
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _loginTimestampKey);
  }

  Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// Returns true if session is within the allowed duration.
  Future<bool> isSessionValid() async {
    final token = await getAccessToken();
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

  Future<bool> _tryRefreshToken() async {
    try {
      final refresh = await getRefreshToken();
      if (refresh == null) return false;
      final resp = await Dio(BaseOptions(baseUrl: ApiConstants.baseUrl)).post(
        ApiConstants.refreshToken,
        data: {'refresh': refresh},
      );
      final newAccess = resp.data['access'] as String;
      final newRefresh = resp.data['refresh'] as String? ?? refresh;
      await saveTokens(access: newAccess, refresh: newRefresh);
      return true;
    } catch (_) {
      await clearTokens();
      return false;
    }
  }
}
