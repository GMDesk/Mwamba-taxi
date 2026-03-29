import '../network/api_client.dart';
import '../services/driver_status_notifier.dart';
import '../services/ride_request_notifier.dart';

final Map<Type, dynamic> _instances = {};

T getIt<T>() => _instances[T] as T;

Future<void> setupDependencies() async {
  _instances[ApiClient] = ApiClient();
  _instances[DriverStatusNotifier] = DriverStatusNotifier();
  _instances[RideRequestNotifier] = RideRequestNotifier();
}
