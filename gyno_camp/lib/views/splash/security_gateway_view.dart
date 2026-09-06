import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../auth/login_view.dart';
import '../dashboard/home_gateway_view.dart';
import '../security/app_lock_pin_view.dart';
import '../security/device_activation_view.dart';

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

    // 1. Device not approved yet -> Device Activation View
    if (!deviceState.isApproved) {
      return const DeviceActivationView();
    }

    // 2. Device approved, but App is locked with PIN -> PIN Unlock View
    if (deviceState.isAppLocked) {
      return const AppLockPinView();
    }

    // 3. Device unlocked: Check if user is already authenticated
    if (authState.isAuthenticated) {
      return const HomeGatewayView();
    }

    // 4. Otherwise -> Login View
    return const LoginView();
  }
}
