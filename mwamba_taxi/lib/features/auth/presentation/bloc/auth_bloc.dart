import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/constants/api_constants.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------
abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class AuthLoginRequested extends AuthEvent {
  final String phoneNumber;
  final String? password;
  final String? otp;

  AuthLoginRequested({required this.phoneNumber, this.password, this.otp});

  @override
  List<Object?> get props => [phoneNumber, password, otp];
}

class AuthRegisterRequested extends AuthEvent {
  final String phoneNumber;
  final String fullName;
  final String password;

  AuthRegisterRequested({
    required this.phoneNumber,
    required this.fullName,
    required this.password,
  });

  @override
  List<Object?> get props => [phoneNumber, fullName, password];
}

class AuthOtpRequested extends AuthEvent {
  final String phoneNumber;
  AuthOtpRequested({required this.phoneNumber});

  @override
  List<Object?> get props => [phoneNumber];
}

class AuthOtpVerified extends AuthEvent {
  final String phoneNumber;
  final String code;

  AuthOtpVerified({required this.phoneNumber, required this.code});

  @override
  List<Object?> get props => [phoneNumber, code];
}

class AuthLogoutRequested extends AuthEvent {}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------
abstract class AuthState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}
class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final Map<String, dynamic> user;
  AuthAuthenticated({required this.user});

  @override
  List<Object?> get props => [user];
}

class AuthUnauthenticated extends AuthState {}

class AuthOtpSent extends AuthState {
  final String phoneNumber;
  AuthOtpSent({required this.phoneNumber});

  @override
  List<Object?> get props => [phoneNumber];
}

class AuthError extends AuthState {
  final String message;
  AuthError({required this.message});

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// BLoC
// ---------------------------------------------------------------------------
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final ApiClient _apiClient = getIt<ApiClient>();

  AuthBloc() : super(AuthInitial()) {
    on<AuthCheckRequested>(_onCheckAuth);
    on<AuthLoginRequested>(_onLogin);
    on<AuthRegisterRequested>(_onRegister);
    on<AuthOtpRequested>(_onRequestOtp);
    on<AuthOtpVerified>(_onVerifyOtp);
    on<AuthLogoutRequested>(_onLogout);
  }

  Future<void> _onCheckAuth(AuthCheckRequested event, Emitter<AuthState> emit) async {
    final isAuth = await _apiClient.isAuthenticated();
    if (isAuth) {
      try {
        final response = await _apiClient.dio.get(ApiConstants.profile);
        emit(AuthAuthenticated(user: response.data));
      } catch (_) {
        await _apiClient.clearTokens();
        emit(AuthUnauthenticated());
      }
    } else {
      emit(AuthUnauthenticated());
    }
  }

  String _formatPhone(String phone) {
    phone = phone.trim().replaceAll(RegExp(r'[\s\-]'), '');
    if (phone.startsWith('+')) return phone;
    if (phone.startsWith('00')) return '+${phone.substring(2)}';
    if (phone.startsWith('0')) return '+243${phone.substring(1)}';
    return '+243$phone';
  }

  Future<void> _onLogin(AuthLoginRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final phone = _formatPhone(event.phoneNumber);
      final data = <String, dynamic>{'phone_number': phone};
      if (event.password != null) data['password'] = event.password;
      if (event.otp != null) data['otp'] = event.otp;

      final response = await _apiClient.dio.post(ApiConstants.login, data: data);
      final tokens = response.data['tokens'];
      await _apiClient.saveTokens(
        access: tokens['access'],
        refresh: tokens['refresh'],
      );
      emit(AuthAuthenticated(user: response.data['user']));
    } catch (e) {
      emit(AuthError(message: _extractError(e)));
    }
  }

  Future<void> _onRegister(AuthRegisterRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final phone = _formatPhone(event.phoneNumber);
      final response = await _apiClient.dio.post(
        ApiConstants.registerPassenger,
        data: {
          'phone_number': phone,
          'full_name': event.fullName,
          'password': event.password,
        },
      );
      final tokens = response.data['tokens'];
      await _apiClient.saveTokens(
        access: tokens['access'],
        refresh: tokens['refresh'],
      );
      emit(AuthAuthenticated(user: response.data['user']));
    } catch (e) {
      emit(AuthError(message: _extractError(e)));
    }
  }

  Future<void> _onRequestOtp(AuthOtpRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final phone = _formatPhone(event.phoneNumber);
      await _apiClient.dio.post(
        ApiConstants.requestOtp,
        data: {'phone_number': phone},
      );
      emit(AuthOtpSent(phoneNumber: phone));
    } catch (e) {
      emit(AuthError(message: _extractError(e)));
    }
  }

  Future<void> _onVerifyOtp(AuthOtpVerified event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final phone = _formatPhone(event.phoneNumber);
      // Login directly with OTP — the login endpoint handles verification
      final response = await _apiClient.dio.post(
        ApiConstants.login,
        data: {'phone_number': phone, 'otp': event.code},
      );
      final tokens = response.data['tokens'];
      await _apiClient.saveTokens(
        access: tokens['access'],
        refresh: tokens['refresh'],
      );
      emit(AuthAuthenticated(user: response.data['user']));
    } catch (e) {
      emit(AuthError(message: _extractError(e)));
    }
  }

  Future<void> _onLogout(AuthLogoutRequested event, Emitter<AuthState> emit) async {
    try {
      final refresh = await _apiClient.getRefreshToken();
      if (refresh != null) {
        await _apiClient.dio.post(ApiConstants.logout, data: {'refresh': refresh});
      }
    } catch (_) {} finally {
      await _apiClient.clearTokens();
      emit(AuthUnauthenticated());
    }
  }

  String _extractError(dynamic e) {
    try {
      if (e.response?.data != null) {
        final data = e.response!.data;
        if (data is Map) {
          if (data.containsKey('detail')) return data['detail'].toString();
          // Handle DRF field-level validation errors
          final errors = <String>[];
          for (final value in data.values) {
            if (value is List) {
              errors.addAll(value.map((v) => v.toString()));
            } else if (value is String) {
              errors.add(value);
            }
          }
          if (errors.isNotEmpty) return errors.first;
        }
        if (data is String && data.isNotEmpty) return data;
      }
    } catch (_) {}
    return 'Une erreur est survenue. Veuillez réessayer.';
  }
}
