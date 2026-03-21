import '../network/api_client.dart';

/// Simple service locator
final getIt = _GetIt();

class _GetIt {
  final Map<Type, dynamic> _instances = {};

  T call<T>() {
    if (!_instances.containsKey(T)) {
      throw Exception('$T is not registered in DI container');
    }
    return _instances[T] as T;
  }

  void registerSingleton<T>(T instance) {
    _instances[T] = instance;
  }

  void registerFactory<T>(T Function() factory) {
    _instances[T] = factory();
  }
}

Future<void> setupDependencies() async {
  // Core
  final apiClient = ApiClient();
  getIt.registerSingleton<ApiClient>(apiClient);
}
