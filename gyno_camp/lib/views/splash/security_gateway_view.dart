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

    // Only show full-screen loader on initial boot check or while restoring active session
    if (!deviceState.isInitialized || authState.isRestoringSession) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.primaryTeal),
              SizedBox(height: 16),
              Text(
                'Restoring secure session...',
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

    final user = authState.currentUser;

    // Super Admin is the approving authority, so their own workstation is
    // registered + approved automatically (audited). This keeps device-bound
    // features such as cloud OCR working for admins without a manual step.
    // Revoked devices are never re-approved; the call is guarded to run once.
    if (user != null &&
        user.isSuperAdmin &&
        !deviceState.isApproved &&
        !deviceState.isRevoked) {
      final deviceNotifier = ref.read(deviceSecurityProvider.notifier);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        deviceNotifier.ensureAdminDeviceApproved(
          adminUserId: user.id,
          adminName: user.name,
        );
      });
    }

    // 2. Hardware security guard: Non-admin staff must be on an approved workstation
    if (user != null && !user.isSuperAdmin && !deviceState.isApproved) {
      return DeviceActivationView(
        prefillStaffName: user.name,
        prefillStaffUserId: user.id,
      );
    }

    // 3. If authenticated, check if session is locked with PIN
    if (deviceState.isAppLocked && (deviceState.device?.hasPinSet ?? false)) {
      return const AppLockPinView();
    }

    // 4. User is authenticated and unlocked -> Role-Tailored Dashboard
    return const HomeGatewayView();
  }
}
