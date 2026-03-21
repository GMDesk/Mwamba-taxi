import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/otp_screen.dart';
import '../../features/auth/presentation/screens/welcome_screen.dart';
import '../../features/splash/presentation/screens/splash_screen.dart';
import '../../features/shell/presentation/screens/main_shell.dart';
import '../../features/ride/presentation/screens/ride_screen.dart';
import '../../features/ride/presentation/screens/ride_history_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/ride/presentation/screens/rating_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/welcome',
      name: 'welcome',
      builder: (context, state) => const WelcomeScreen(),
    ),
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      name: 'register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/otp',
      name: 'otp',
      builder: (context, state) {
        final phone = state.extra as String? ?? '';
        return OtpScreen(phoneNumber: phone);
      },
    ),
    GoRoute(
      path: '/home',
      name: 'home',
      builder: (context, state) => const MainShell(),
    ),
    GoRoute(
      path: '/ride/:rideId',
      name: 'ride',
      builder: (context, state) {
        final rideId = state.pathParameters['rideId']!;
        return RideScreen(rideId: rideId);
      },
    ),
    GoRoute(
      path: '/ride/:rideId/rate',
      name: 'rate',
      builder: (context, state) {
        final rideId = state.pathParameters['rideId']!;
        return RatingScreen(rideId: rideId);
      },
    ),
    GoRoute(
      path: '/history',
      name: 'history',
      builder: (context, state) => const RideHistoryScreen(),
    ),
    GoRoute(
      path: '/profile',
      name: 'profile',
      builder: (context, state) => const ProfileScreen(),
    ),
  ],
);
