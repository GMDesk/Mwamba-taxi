class ApiConstants {
  ApiConstants._();

  // Google Maps / Places API
  static const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  static const String baseUrl = 'https://mwambataxi.com/api/v1';
  // static const String baseUrl = 'http://192.168.18.10:8001/api/v1';  // Local
  // static const String baseUrl = 'http://10.0.2.2:8000/api/v1';  // Android emulator
  // static const String baseUrl = 'http://localhost:8000/api/v1';  // iOS sim

  static const String wsBaseUrl = 'wss://mwambataxi.com/ws';

  // Auth
  static const String registerPassenger = '/auth/register/passenger/';
  static const String registerDriver = '/auth/register/driver/';
  static const String login = '/auth/login/';
  static const String logout = '/auth/logout/';
  static const String refreshToken = '/auth/token/refresh/';
  static const String requestOtp = '/auth/otp/request/';
  static const String verifyOtp = '/auth/otp/verify/';
  static const String profile = '/auth/profile/';
  static const String changePassword = '/auth/profile/password/';

  // Nearby Drivers
  static const String nearbyDrivers = '/auth/drivers/nearby/';

  // Rides
  static const String estimatePrice = '/rides/estimate/';
  static const String requestRide = '/rides/request/';
  static String acceptRide(String id) => '/rides/$id/accept/';
  static String declineRide(String id) => '/rides/$id/decline/';
  static String timeoutRide(String id) => '/rides/$id/timeout/';
  static String startRide(String id) => '/rides/$id/start/';
  static String completeRide(String id) => '/rides/$id/complete/';
  static String cancelRide(String id) => '/rides/$id/cancel/';
  static String rideDetail(String id) => '/rides/$id/';
  static String rideLocation(String id) => '/rides/$id/location/';
  static String rideSos(String id) => '/rides/$id/sos/';
  static const String passengerHistory = '/rides/history/passenger/';

  // Payments / Wallet
  static const String wallet = '/payments/wallet/';
  static const String walletTransactions = '/payments/wallet/transactions/';
  static const String walletDeposit = '/payments/wallet/deposit/';
  static const String paymentHistory = '/payments/history/';
  static String paymentStatus(String id) => '/payments/$id/status/';

  // Notifications
  static const String notifications = '/notifications/';
  static const String unreadCount = '/notifications/unread-count/';
  static String markRead(String id) => '/notifications/$id/read/';
  static const String markAllRead = '/notifications/read-all/';
  static const String updateFcmToken = '/notifications/fcm-token/';

  // Promotions
  static const String validatePromo = '/promotions/validate/';

  // Reviews
  static const String createReview = '/reviews/create/';
}
