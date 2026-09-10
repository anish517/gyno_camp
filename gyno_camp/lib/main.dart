import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'core/constants/app_constants.dart';
import 'core/services/session_service.dart';
import 'core/theme/app_theme.dart';
import 'views/splash/security_gateway_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite database factory based on platform
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else {
    // Native mobile platforms (Android / iOS)
    databaseFactory = databaseFactorySqflitePlugin;
  }

  // Initialize persistent session service (SharedPreferences)
  await SessionService.getInstance();

  runApp(const ProviderScope(child: GynocampApp()));
}

class GynocampApp extends StatelessWidget {
  const GynocampApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SecurityGatewayView(),
    );
  }
}
