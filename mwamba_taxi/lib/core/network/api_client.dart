import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/api_constants.dart';

class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(_AuthInterceptor(this));
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => print('[API] $obj'),
    ));
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
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}

class _AuthInterceptor extends Interceptor {
  final ApiClient _client;
  bool _isRefreshing = false;

  _AuthInterceptor(this._client);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Skip auth for public endpoints
    final publicPaths = [
      ApiConstants.login,
      ApiConstants.registerPassenger,
      ApiConstants.requestOtp,
      ApiConstants.verifyOtp,
      ApiConstants.refreshToken,
      ApiConstants.nearbyDrivers,
    ];
    if (publicPaths.any((p) => options.path.contains(p))) {
      return handler.next(options);
    }

    final token = await _client.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      // Try refresh
      final refreshToken = await _client.getRefreshToken();
      if (refreshToken != null) {
        try {
          final response = await Dio().post(
            '${ApiConstants.baseUrl}${ApiConstants.refreshToken}',
            data: {'refresh': refreshToken},
          );
          final newAccess = response.data['access'] as String;
          final newRefresh = response.data['refresh'] as String? ?? refreshToken;
          await _client.saveTokens(access: newAccess, refresh: newRefresh);
          _isRefreshing = false;

          // Retry original request
          err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
          final retryResponse = await _client.dio.fetch(err.requestOptions);
          return handler.resolve(retryResponse);
        } catch (_) {
          await _client.clearTokens();
          _isRefreshing = false;
        }
      } else {
        _isRefreshing = false;
      }
    }
    handler.next(err);
  }
}
