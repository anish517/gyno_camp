import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../auth/login_view.dart';
import '../dashboard/home_gateway_view.dart';
import '../security/app_lock_pin_view.dart';

class SecurityGatewayView extends ConsumerWidget {
  const SecurityGatewayView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(deviceSecurityProvider);
    final authState = ref.watch(authStateProvider);

    if (deviceState.isChecking) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.primaryTeal),
              SizedBox(height: 16),
              Text(
                'Checking device authorization...',
                style: TextStyle(color: AppTheme.textSecondaryLight, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    // 1. If not authenticated -> show Professional Role-Based Login Screen
    if (!authState.isAuthenticated) {
      return const LoginView();
    }

    // 2. If authenticated, check if session is locked with PIN
    if (deviceState.isAppLocked && (deviceState.device?.hasPinSet ?? false)) {
      return const AppLockPinView();
    }

    // 3. User is authenticated and unlocked -> Role-Tailored Dashboard
    return const HomeGatewayView();
  }
}
