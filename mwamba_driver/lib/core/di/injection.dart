import '../network/api_client.dart';

final Map<Type, dynamic> _instances = {};

T getIt<T>() => _instances[T] as T;

Future<void> setupDependencies() async {
  _instances[ApiClient] = ApiClient();
}
