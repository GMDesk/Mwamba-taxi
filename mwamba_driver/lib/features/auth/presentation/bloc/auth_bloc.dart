import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';

// Events
abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class CheckAuthEvent extends AuthEvent {}

class LoginEvent extends AuthEvent {
  final String phone;
  final String password;
  LoginEvent({required this.phone, required this.password});
  @override
  List<Object?> get props => [phone, password];
}

class RegisterEvent extends AuthEvent {
  final String phone;
  final String firstName;
  final String lastName;
  final String password;
  final String? vehicleBrand;
  final String? vehicleModel;
  final String? vehicleColor;
  final String? licensePlate;
  RegisterEvent({
    required this.phone,
    required this.firstName,
    required this.lastName,
    required this.password,
    this.vehicleBrand,
    this.vehicleModel,
    this.vehicleColor,
    this.licensePlate,
  });
  @override
  List<Object?> get props => [phone, firstName, lastName, password];
}

class RequestOtpEvent extends AuthEvent {
  final String phone;
  RequestOtpEvent({required this.phone});
  @override
  List<Object?> get props => [phone];
}

class VerifyOtpEvent extends AuthEvent {
  final String phone;
  final String code;
  VerifyOtpEvent({required this.phone, required this.code});
  @override
  List<Object?> get props => [phone, code];
}

class LogoutEvent extends AuthEvent {}

// States
abstract class AuthState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}
class AuthLoading extends AuthState {}
class Authenticated extends AuthState {}
class Unauthenticated extends AuthState {}
class OtpSent extends AuthState {
  final String phone;
  OtpSent({required this.phone});
  @override
  List<Object?> get props => [phone];
}
class AuthError extends AuthState {
  final String message;
  AuthError(this.message);
  @override
  List<Object?> get props => [message];
}

// BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final ApiClient _api = getIt<ApiClient>();

  AuthBloc() : super(AuthInitial()) {
    on<CheckAuthEvent>(_onCheck);
    on<LoginEvent>(_onLogin);
    on<RegisterEvent>(_onRegister);
    on<RequestOtpEvent>(_onRequestOtp);
    on<VerifyOtpEvent>(_onVerifyOtp);
    on<LogoutEvent>(_onLogout);
  }

  Future<void> _onCheck(CheckAuthEvent event, Emitter<AuthState> emit) async {
    final has = await _api.hasTokens();
    emit(has ? Authenticated() : Unauthenticated());
  }

  Future<void> _onLogin(LoginEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final resp = await _api.dio.post(ApiConstants.login, data: {
        'phone_number': event.phone,
        'password': event.password,
      });
      final tokens = resp.data['tokens'];
      await _api.saveTokens(tokens['access'], tokens['refresh']);
      emit(Authenticated());
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data.containsKey('detail')) {
        emit(AuthError(data['detail'].toString()));
      } else {
        emit(AuthError('Identifiants incorrects'));
      }
    } catch (e) {
      emit(AuthError('Identifiants incorrects'));
    }
  }

  Future<void> _onRegister(RegisterEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final data = <String, dynamic>{
        'phone_number': event.phone,
        'full_name': '${event.firstName} ${event.lastName}'.trim(),
        'password': event.password,
      };
      if (event.vehicleBrand != null && event.vehicleBrand!.isNotEmpty) {
        data['vehicle_make'] = event.vehicleBrand;
      }
      if (event.vehicleModel != null && event.vehicleModel!.isNotEmpty) {
        data['vehicle_model'] = event.vehicleModel;
      }
      if (event.vehicleColor != null && event.vehicleColor!.isNotEmpty) {
        data['vehicle_color'] = event.vehicleColor;
      }
      if (event.licensePlate != null && event.licensePlate!.isNotEmpty) {
        data['license_plate'] = event.licensePlate;
      }

      final resp = await _api.dio.post(ApiConstants.registerDriver, data: data);
      final tokens = resp.data['tokens'];
      if (tokens != null) {
        await _api.saveTokens(tokens['access'], tokens['refresh']);
      }
      emit(Authenticated());
    } on DioException catch (e) {
      debugPrint('Register DioException: type=${e.type}, status=${e.response?.statusCode}, msg=${e.message}, error=${e.error}, errorType=${e.error?.runtimeType}');
      final responseData = e.response?.data;
      if (responseData is Map) {
        final messages = <String>[];
        responseData.forEach((key, value) {
          if (value is List) {
            messages.addAll(value.map((v) => v.toString()));
          } else if (value is String) {
            messages.add(value);
          } else if (value is Map && value.containsKey('message')) {
            messages.add(value['message'].toString());
          }
        });
        if (messages.isNotEmpty) {
          emit(AuthError(messages.first));
          return;
        }
      }
      if (e.type == DioExceptionType.connectionTimeout) {
        emit(AuthError('Connexion au serveur trop lente. Vérifiez votre internet.'));
      } else if (e.type == DioExceptionType.connectionError) {
        final inner = e.error;
        debugPrint('Connection error inner: $inner (${inner.runtimeType})');
        emit(AuthError('Erreur connexion: ${inner ?? e.message ?? "inconnue"}'));
      } else {
        emit(AuthError('Erreur serveur (${e.response?.statusCode ?? e.type.name})'));
      }
    } catch (e, stackTrace) {
      debugPrint('Register unexpected error: $e\n$stackTrace');
      emit(AuthError('Erreur: ${e.toString()}'));
    }
  }

  Future<void> _onRequestOtp(RequestOtpEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _api.dio.post(ApiConstants.requestOtp, data: {'phone_number': event.phone});
      emit(OtpSent(phone: event.phone));
    } catch (e) {
      emit(AuthError('Erreur d\'envoi du code'));
    }
  }

  Future<void> _onVerifyOtp(VerifyOtpEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final resp = await _api.dio.post(ApiConstants.verifyOtp, data: {
        'phone_number': event.phone,
        'code': event.code,
      });
      final tokens = resp.data['tokens'];
      await _api.saveTokens(tokens['access'], tokens['refresh']);
      emit(Authenticated());
    } catch (e) {
      emit(AuthError('Code invalide'));
    }
  }

  Future<void> _onLogout(LogoutEvent event, Emitter<AuthState> emit) async {
    await _api.clearTokens();
    emit(Unauthenticated());
  }
}
