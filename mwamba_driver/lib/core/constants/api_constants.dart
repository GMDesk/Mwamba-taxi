class ApiConstants {
  ApiConstants._();

  static const String baseUrl = 'https://mwambataxi.com/api/v1';
  // static const String baseUrl = 'http://192.168.18.10:8001/api/v1';  // Local
  // static const String baseUrl = 'http://10.0.2.2:8000/api/v1';  // Android emulator

  static const String wsBaseUrl = 'wss://mwambataxi.com/ws';

  // Auth
  static const String registerDriver = '/auth/register/driver/';
  static const String login = '/auth/login/';
  static const String logout = '/auth/logout/';
  static const String refreshToken = '/auth/token/refresh/';
  static const String requestOtp = '/auth/otp/request/';
  static const String verifyOtp = '/auth/otp/verify/';
  static const String profile = '/auth/profile/';

  // Driver
  static const String driverProfile = '/auth/driver/profile/';
  static const String updateLocation = '/auth/driver/location/';
  static const String updateStatus = '/auth/driver/status/';

  // Rides
  static String acceptRide(String id) => '/rides/$id/accept/';
  static String startRide(String id) => '/rides/$id/start/';
  static String completeRide(String id) => '/rides/$id/complete/';
  static String cancelRide(String id) => '/rides/$id/cancel/';
  static String rideDetail(String id) => '/rides/$id/';
  static String rideLocation(String id) => '/rides/$id/location/';
  static String rideSos(String id) => '/rides/$id/sos/';
  static const String driverHistory = '/rides/history/driver/';
  static const String pendingRides = '/rides/pending/';

  // Payments
  static const String earnings = '/payments/earnings/';
  static const String payouts = '/payments/payouts/';

  // Notifications
  static const String notifications = '/notifications/';
  static const String unreadCount = '/notifications/unread-count/';
  static String markRead(String id) => '/notifications/$id/read/';
  static const String markAllRead = '/notifications/read-all/';
  static const String updateFcmToken = '/notifications/fcm-token/';

  // Reviews
  static String driverReviews(String driverId) => '/reviews/driver/$driverId/';
}
