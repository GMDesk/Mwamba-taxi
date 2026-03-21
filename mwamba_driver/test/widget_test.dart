import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:mwamba_driver/core/di/injection.dart';
import 'package:mwamba_driver/core/theme/app_theme.dart';
import 'package:mwamba_driver/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mwamba_driver/features/auth/presentation/screens/welcome_screen.dart';

void main() {
  setUpAll(() async {
    await setupDependencies();
  });

  testWidgets('App builds and shows welcome screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        builder: (context, child) {
          return BlocProvider(
            create: (_) => AuthBloc()..add(CheckAuthEvent()),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'Mwamba Driver',
              theme: AppTheme.lightTheme,
              home: const WelcomeScreen(),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    // Verify the app renders without errors
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
