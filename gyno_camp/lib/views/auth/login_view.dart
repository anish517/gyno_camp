import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../security/device_activation_view.dart';

class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key});

  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin(String deviceId) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your staff email, username, or mobile number.')),
      );
      return;
    }
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your password or station PIN.')),
      );
      return;
    }

    final authVm = ref.read(authStateProvider.notifier);
    final success = await authVm.login(
      email: email,
      password: password,
      deviceId: deviceId,
    );

    if (!success || !mounted) return;

    final user = ref.read(authStateProvider).currentUser;
    if (user == null) return;

    // Super Admin is exempt from device lockout so the administrator can always access the console
    if (user.isSuperAdmin) {
      return;
    }

    final currentDeviceState = ref.read(deviceSecurityProvider);
    if (!currentDeviceState.isApproved) {
      if (currentDeviceState.isUnregistered) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.devices_other, color: AppTheme.primaryTeal),
                SizedBox(width: 8),
                Text('New Workstation Detected'),
              ],
            ),
            content: Text(
              'Welcome, ${user.name}. This workstation is not yet recognized on the clinical outreach network. For medical record security, new hardware must be registered and authorized by the Super Admin before clinical intake begins.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ref.read(authStateProvider.notifier).logout(deviceId: deviceId);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.security, size: 16),
                label: const Text('Register This Device'),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DeviceActivationView(
                        prefillStaffName: user.name,
                        prefillStaffUserId: user.id,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      } else if (currentDeviceState.isPendingApproval) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.hourglass_top, color: Colors.orange),
                SizedBox(width: 8),
                Text('Device Pending Approval'),
              ],
            ),
            content: Text(
              'Workstation "${currentDeviceState.device?.deviceName ?? "Device"}" is registered but awaiting Super Admin authorization. Please notify your administrator to approve this device in the central Admin Console.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DeviceActivationView()),
                  );
                },
                child: const Text('View Status'),
              ),
            ],
          ),
        );
      } else if (currentDeviceState.isRevoked) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Access Denied: This hardware workstation has been revoked by administration.'),
            backgroundColor: AppTheme.dangerRose,
          ),
        );
        ref.read(authStateProvider.notifier).logout(deviceId: deviceId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final deviceState = ref.watch(deviceSecurityProvider);
    final deviceId = deviceState.device?.deviceId ?? 'dev-local';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 36.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Brand Header
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primaryTeal, Color(0xFF0F766E)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryTeal.withValues(alpha: 0.28),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.medical_services_rounded, size: 36, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    AppConstants.appTitleEn,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppConstants.appTitleNe,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Hardware Security Badge
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_user_rounded, color: Color(0xFF059669), size: 16),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              deviceState.device?.deviceName != null
                                  ? 'Authorized Terminal: ${deviceState.device!.deviceName} (RBAC Active)'
                                  : 'Clinical Workstation (RBAC Active)',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF065F46)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Error Message Banner
                  if (authState.errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 18),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerRose.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.dangerRose.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, color: AppTheme.dangerRose, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              authState.errorMessage!,
                              style: const TextStyle(color: AppTheme.dangerRose, fontSize: 13, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Single Unified Credential Authentication Card
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(26.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Staff Sign-In',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1E293B),
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'अधिकृत कर्मचारी लगइन',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryTeal.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.auto_awesome_rounded, size: 13, color: AppTheme.primaryTeal),
                                    SizedBox(width: 4),
                                    Text(
                                      'Auto-Detect Role',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primaryTeal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sign in with your staff account. The system will automatically direct you to your designated console.',
                            style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.35),
                          ),
                          const SizedBox(height: 22),

                          // Email / Username Field
                          const Text(
                            'Staff Email / Username',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              hintText: 'Enter registered staff email or phone',
                              prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                            onSubmitted: (_) => _handleLogin(deviceId),
                          ),
                          const SizedBox(height: 16),

                          // Password Field
                          const Text(
                            'Password / Security PIN',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              hintText: 'Enter account password or 4-digit PIN',
                              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                            onSubmitted: (_) => _handleLogin(deviceId),
                          ),
                          const SizedBox(height: 24),

                          // Submit Action Button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryTeal,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 1,
                              ),
                              icon: authState.isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Icon(Icons.login_rounded, size: 20),
                              label: Text(
                                authState.isLoading ? 'Authenticating Session...' : 'Sign In to GynoCamp',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.2),
                              ),
                              onPressed: authState.isLoading ? null : () => _handleLogin(deviceId),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Bottom Security Link
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.shield_outlined, size: 16, color: Color(0xFF64748B)),
                      label: const Text(
                        'Device Authorization & Security Management',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const DeviceActivationView()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text(
                      'Protected under Nepal Ministry of Health Data Privacy Protocol • AES-256 Vault',
                      style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
