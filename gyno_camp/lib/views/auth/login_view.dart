import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';

class LoginView extends ConsumerWidget {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final authVm = ref.read(authStateProvider.notifier);
    final deviceState = ref.watch(deviceSecurityProvider);
    final deviceId = deviceState.device?.deviceId ?? 'dev-local';

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // App Logo / Icon Header
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryTeal, width: 2),
                  ),
                  child: const Icon(Icons.medical_services_outlined, size: 40, color: AppTheme.primaryTeal),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                AppConstants.appTitleEn,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimaryLight,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                AppConstants.appTitleNe,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 32),

              // Device Security Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.successGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.successGreen.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.verified, color: AppTheme.successGreen, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Verified Device: ${deviceState.device?.deviceName ?? "Active Hardware"}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.successGreen),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              const Text(
                'Select User Role to Continue:',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),

              if (authState.errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerRose.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.dangerRose),
                  ),
                  child: Text(
                    authState.errorMessage!,
                    style: const TextStyle(color: AppTheme.dangerRose, fontSize: 13),
                  ),
                ),

              // Role Card 1: Data Taker (Field Role)
              _buildRoleCard(
                context: context,
                title: 'Data Taker (Field Staff)',
                nepaliTitle: 'डाटा टेकर (क्षेत्रीय कर्मचारी)',
                description: 'Registers patients, scans Yellow Form, and enters clinical data during camp.',
                icon: Icons.assignment_ind_outlined,
                color: AppTheme.primaryTeal,
                onTap: () => authVm.loginAsRole(role: UserRole.dataTaker, deviceId: deviceId),
              ),
              const SizedBox(height: 12),

              // Role Card 2: Super Admin
              _buildRoleCard(
                context: context,
                title: 'Super Admin',
                nepaliTitle: 'सुपर एडमिन (प्रणाली नियन्त्रक)',
                description: 'Manages camps, schedules staff, approves devices, and customizes form lists.',
                icon: Icons.admin_panel_settings_outlined,
                color: Colors.indigo,
                onTap: () => authVm.loginAsRole(role: UserRole.superAdmin, deviceId: deviceId),
              ),
              const SizedBox(height: 12),

              // Role Card 3: Data Analyst
              _buildRoleCard(
                context: context,
                title: 'Data Analyst',
                nepaliTitle: 'डाटा विश्लेषक',
                description: 'Reviews synced camp statistics and exports instant PDF and Excel reports.',
                icon: Icons.analytics_outlined,
                color: Colors.teal.shade800,
                onTap: () => authVm.loginAsRole(role: UserRole.dataAnalyst, deviceId: deviceId),
              ),
              const SizedBox(height: 24),

              // Lock Device Action
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.lock_clock, size: 18),
                  label: const Text('Lock App Session (Require PIN)'),
                  onPressed: () {
                    ref.read(deviceSecurityProvider.notifier).lockApp();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required String title,
    required String nepaliTitle,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      nepaliTitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
