import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await setupDependencies();
  runApp(const MwambaDriverApp());
}

class MwambaDriverApp extends StatelessWidget {
  const MwambaDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      builder: (context, child) {
        return BlocProvider(
          create: (_) => AuthBloc()..add(CheckAuthEvent()),
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            title: 'Mwamba Driver',
            theme: AppTheme.lightTheme,
            routerConfig: appRouter,
          ),
        );
      },
    );
  }
}
