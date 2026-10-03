import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/device_management_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../security/device_activation_view.dart';
import '../splash/security_gateway_view.dart';

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
    if (ref.read(authStateProvider).isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Please enter your staff email, username, or mobile number.'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return;
    }
    if (password.isEmpty) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Please enter your password or station PIN.'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return;
    }

    final authVm = ref.read(authStateProvider.notifier);
    final success = await authVm.login(
      email: email,
      password: password,
      deviceId: deviceId,
    );

    if (!mounted || !success) return;

    final user = ref.read(authStateProvider).currentUser;
    if (user == null) return;

    if (user.isSuperAdmin) {
      ref.read(deviceManagementProvider.notifier).loadDevices();
    }

    // If regular staff (non-admin), enforce hardware registration & approval
    if (!user.isSuperAdmin) {
      // Re-verify current device status live from repository before gating authorization
      await ref.read(deviceSecurityProvider.notifier).checkCurrentDevice();
      if (!mounted) return;
      final currentDeviceState = ref.read(deviceSecurityProvider);
      if (!currentDeviceState.isApproved) {
        // Clear active session immediately so the user is not authenticated on unapproved hardware
        await authVm.logout(deviceId: deviceId);
        if (!mounted) return;

        if (currentDeviceState.isUnregistered) {
          final staffNameController = TextEditingController(text: user.name);
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.devices_other_rounded, color: AppTheme.primaryTeal),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'New Workstation Detected',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This workstation is not yet recognized on the clinical outreach network. For medical record security, new hardware must be registered with the requesting person\'s details before Super Admin authorization.',
                      style: TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF334155)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: staffNameController,
                      decoration: const InputDecoration(
                        labelText: "Requesting Person's Name",
                        hintText: "e.g. Sita Sharma (Field Nurse)",
                        helperText: "Person requesting hardware whitelist",
                        prefixIcon: Icon(Icons.person_outline, size: 20),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.security, size: 16),
                  label: const Text('Register This Device'),
                  onPressed: () {
                    final requestedName = staffNameController.text.trim().isNotEmpty
                        ? staffNameController.text.trim()
                        : user.name;
                    Navigator.pop(ctx);
                    if (mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DeviceActivationView(
                            prefillStaffName: requestedName,
                            prefillStaffUserId: user.id,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          );
          staffNameController.dispose();
          return;
        } else if (currentDeviceState.isPendingApproval) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.hourglass_top_rounded, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Device Pending Approval',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Text(
                'Workstation "${currentDeviceState.device?.deviceName ?? "Device"}" is registered but awaiting Super Admin authorization. Please notify your administrator to approve this device in the central Admin Console.',
                style: const TextStyle(fontSize: 13.5, height: 1.4, color: Color(0xFF334155)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DeviceActivationView()),
                      );
                    }
                  },
                  child: const Text('View Status'),
                ),
              ],
            ),
          );
          return;
        } else if (currentDeviceState.isRevoked) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Access Denied: This hardware workstation has been revoked by administration.'),
              backgroundColor: AppTheme.dangerRose,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
          return;
        }
      }
    }

    // Authorized staff or Super Admin -> navigate immediately to clinical console
    if (mounted) {
      final isNestedInGateway = context.findAncestorWidgetOfExactType<SecurityGatewayView>() != null;
      if (!isNestedInGateway) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SecurityGatewayView()),
          (route) => false,
        );
      }
    }
  }

  void _showForgotPasswordModal(BuildContext context, String deviceId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ForgotPasswordDialog(
        initialEmail: _emailController.text.trim(),
        deviceId: deviceId,
        onResetSuccess: (email, newPassword) {
          _emailController.text = email;
          _passwordController.text = newPassword;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Password updated successfully! Signing you in...'),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
          _handleLogin(deviceId);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final deviceState = ref.watch(deviceSecurityProvider);
    final deviceId = deviceState.device?.deviceId ?? 'dev-local';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 960;

            if (isDesktop) {
              return _buildDesktopLayout(context, authState, deviceState, deviceId);
            } else {
              return _buildMobileLayout(context, authState, deviceState, deviceId);
            }
          },
        ),
      ),
    );
  }

  // =========================================================================
  // Desktop / Tablet Wide View (Split-Pane Workstation Layout)
  // =========================================================================
  Widget _buildDesktopLayout(
    BuildContext context,
    AuthState authState,
    DeviceSecurityState deviceState,
    String deviceId,
  ) {
    return Row(
      children: [
        // Left Column: Hero Branding & Outreach Mission Overview
        Expanded(
          flex: 5,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E0A38), Color(0xFF30026E), Color(0xFF56014B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                // Ambient glowing circles for visual richness
                Positioned(
                  top: -60,
                  left: -60,
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -80,
                  right: -80,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFBE185D).withValues(alpha: 0.12),
                    ),
                  ),
                ),

                // Main Content with ScrollView to prevent vertical overflow
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48.0, vertical: 36.0),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Brand
                        Row(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/WFWSNPrimaryCircle.jpg',
                                  fit: BoxFit.cover,
                                  errorBuilder: (ctx, err, stack) => const Icon(
                                    Icons.medical_services_rounded,
                                    color: AppTheme.brandPurple,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppConstants.appTitleEn,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -0.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    AppConstants.appTitleNe,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withValues(alpha: 0.85),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'Specialized Clinical Outreach & Gynaecological Health Portal',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.25,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Empowering rural screening camps, POP-Q staging, and referral management across Nepal with offline-first enterprise security.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 36),

                        // Feature Highlights / Medical Station Pillars
                        _buildDesktopFeatureTile(
                          icon: Icons.wifi_off_rounded,
                          title: '100% Offline-First Field Operation',
                          subtitle: 'Seamless registration, exam notes & OMR scans without active internet.',
                        ),
                        const SizedBox(height: 16),
                        _buildDesktopFeatureTile(
                          icon: Icons.lock_clock_rounded,
                          title: 'Role-Based Access Control (RBAC)',
                          subtitle: 'Strict station access segregation for Registrar, Clinician & Analyst.',
                        ),
                        const SizedBox(height: 16),
                        _buildDesktopFeatureTile(
                          icon: Icons.shield_rounded,
                          title: 'AES-256 Ledger & MoHP Compliance',
                          subtitle: 'Cryptographically sealed audit trail complying with health privacy standards.',
                        ),
                        const SizedBox(height: 36),

                        // Terminal Status Box
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                deviceState.isApproved ? Icons.check_circle_rounded : Icons.sensors_rounded,
                                color: deviceState.isApproved ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      deviceState.device?.deviceName != null
                                          ? 'Workstation: ${deviceState.device!.deviceName}'
                                          : 'Clinical Workstation: $deviceId',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      deviceState.isApproved
                                          ? 'Cryptographic Station Approved (Local Vault Ready)'
                                          : 'Pending Hardware Authorization',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.75),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Right Column: Sign-in Form
        Expanded(
          flex: 6,
          child: Container(
            color: const Color(0xFFF8FAFC),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 36.0, vertical: 40.0),
                  child: _buildCredentialCard(context, authState, deviceState, deviceId),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopFeatureTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // Mobile / Compact View (Single-Column Vertical Layout)
  // =========================================================================
  Widget _buildMobileLayout(
    BuildContext context,
    AuthState authState,
    DeviceSecurityState deviceState,
    String deviceId,
  ) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mobile Header
              Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.brandPurple, AppTheme.brandMagenta],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.brandPurple.withValues(alpha: 0.28),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.medical_services_rounded, size: 30, color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                AppConstants.appTitleEn,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                AppConstants.appTitleNe,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 12),

              // Hardware Security Badge
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_user_rounded, color: Color(0xFF059669), size: 14),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          deviceState.device?.deviceName != null
                              ? 'Terminal: ${deviceState.device!.deviceName} (RBAC)'
                              : 'Clinical Workstation (RBAC)',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF065F46)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Sign-in Card
              _buildCredentialCard(context, authState, deviceState, deviceId),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // Core Unified Credential Card (Used on both Desktop and Mobile)
  // =========================================================================
  Widget _buildCredentialCard(
    BuildContext context,
    AuthState authState,
    DeviceSecurityState deviceState,
    String deviceId,
  ) {
    return Column(
      key: const ValueKey('credential_card_column'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Error Message Banner (if any)
        if (authState.errorMessage != null)
          Container(
            key: const ValueKey('login_error_banner_box'),
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.dangerRose.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.dangerRose.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded, color: AppTheme.dangerRose, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    authState.errorMessage!,
                    style: const TextStyle(color: AppTheme.dangerRose, fontSize: 12, height: 1.3),
                  ),
                ),
                InkWell(
                  onTap: () => ref.read(authStateProvider.notifier).clearError(),
                  child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.dangerRose),
                ),
              ],
            ),
          ),

        Card(
          key: const ValueKey('login_credential_card'),
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Card Header with Wrap to eliminate horizontal overflow on narrow screens
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
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
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.brandPurple.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 12, color: AppTheme.brandPurple),
                          SizedBox(width: 4),
                          Text(
                            'Auto-Detect Role',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.brandPurple,
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
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.35),
                ),
                const SizedBox(height: 16),

                const SizedBox(height: 18),

                // Email / Username Field (0th TextField)
                const Text(
                  'Staff Email / Username',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 5),
                TextField(
                  key: const ValueKey('login_email_field'),
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: 'Enter registered staff email or phone',
                    hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.alternate_email_rounded, size: 18, color: Color(0xFF64748B)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),

                // Password / PIN Field (1st TextField)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Password / Security PIN',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'PIN or Password',
                      style: TextStyle(fontSize: 11, color: AppTheme.brandPurple, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                TextField(
                  key: const ValueKey('login_password_field'),
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'Enter account password or 4-digit PIN',
                    hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF64748B)),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 18,
                        color: const Color(0xFF64748B),
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onSubmitted: (_) => _handleLogin(deviceId),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('forgot_password_btn'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _showForgotPasswordModal(context, deviceId),
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.brandPurple,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Submit Action Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brandPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 1,
                      shadowColor: AppTheme.brandPurple.withValues(alpha: 0.3),
                    ),
                    icon: authState.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.login_rounded, size: 18),
                    label: Text(
                      authState.isLoading ? 'Authenticating Session...' : 'Sign In to GynoCamp',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, letterSpacing: 0.2),
                    ),
                    onPressed: authState.isLoading ? null : () => _handleLogin(deviceId),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Bottom Security Link
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.shield_outlined, size: 15, color: Color(0xFF64748B)),
            label: const Text(
              'Device Authorization & Security Management',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeviceActivationView()),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        const Center(
          child: Text(
            'Protected under Nepal Ministry of Health Data Privacy Protocol • AES-256 Vault',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
          ),
        ),
      ],
    );
  }
}

class _ForgotPasswordDialog extends ConsumerStatefulWidget {
  final String initialEmail;
  final String deviceId;
  final void Function(String email, String newPassword) onResetSuccess;

  const _ForgotPasswordDialog({
    required this.initialEmail,
    required this.deviceId,
    required this.onResetSuccess,
  });

  @override
  ConsumerState<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends ConsumerState<_ForgotPasswordDialog> {
  int _step = 1; // 1: Email, 2: OTP, 3: New Password
  late final TextEditingController _emailCtrl;
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _devCodeHint;

  Timer? _resendTimer;
  int _resendCountdown = 0;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendCountdown = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendCountdown = 0);
      } else {
        if (mounted) setState(() => _resendCountdown--);
      }
    });
  }

  Future<void> _handleSendOtp() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _errorMessage = 'Please enter a valid staff email address.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await ref.read(authStateProvider.notifier).sendForgotPasswordOtp(email);

    if (!mounted) return;

    if (res['success'] == true) {
      setState(() {
        _isLoading = false;
        _step = 2;
        _devCodeHint = res['dev_code']?.toString();
      });
      _startResendTimer();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = res['error']?.toString() ?? 'Unable to send verification code. Please try again.';
      });
    }
  }

  Future<void> _handleVerifyCode() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final code = _codeCtrl.text.trim();

    if (code.length < 4) {
      setState(() => _errorMessage = 'Please enter the verification code sent to your email.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await ref.read(authStateProvider.notifier).verifyResetCode(email, code);

    if (!mounted) return;

    if (res['success'] == true) {
      setState(() {
        _isLoading = false;
        _step = 3;
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = res['error']?.toString() ?? 'Verification code is invalid or expired.';
      });
    }
  }

  Future<void> _handleResetPassword() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final code = _codeCtrl.text.trim();
    final newPass = _passwordCtrl.text.trim();
    final confirmPass = _confirmPasswordCtrl.text.trim();
    final newPin = _pinCtrl.text.trim();

    if (newPass.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters long.');
      return;
    }

    if (newPass != confirmPass) {
      setState(() => _errorMessage = 'Passwords do not match. Please re-enter.');
      return;
    }

    if (newPin.isNotEmpty && (newPin.length < 4 || newPin.length > 6)) {
      setState(() => _errorMessage = 'PIN must be between 4 and 6 digits.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await ref.read(authStateProvider.notifier).resetPasswordWithCode(
      email: email,
      code: code,
      newPassword: newPass,
      newPin: newPin.isNotEmpty ? newPin : null,
      deviceId: widget.deviceId,
    );

    if (!mounted) return;

    if (res['success'] == true) {
      Navigator.of(context).pop();
      widget.onResetSuccess(email, newPass);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = res['error']?.toString() ?? 'Failed to reset password. Please try again.';
      });
    }
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _buildStepDot(1, 'Email', _step >= 1, _step == 1),
        _buildStepLine(_step >= 2),
        _buildStepDot(2, 'Code', _step >= 2, _step == 2),
        _buildStepLine(_step >= 3),
        _buildStepDot(3, 'Password', _step >= 3, _step == 3),
      ],
    );
  }

  Widget _buildStepDot(int stepNum, String label, bool isReached, bool isCurrent) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCurrent
                ? AppTheme.brandPurple
                : (isReached ? const Color(0xFF059669) : const Color(0xFFE2E8F0)),
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: AppTheme.brandPurple.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isReached && !isCurrent
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text(
                    '$stepNum',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isReached ? Colors.white : const Color(0xFF94A3B8),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
            color: isCurrent
                ? AppTheme.brandPurple
                : (isReached ? const Color(0xFF334155) : const Color(0xFF94A3B8)),
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(bool isActive) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
        color: isActive ? const Color(0xFF059669) : const Color(0xFFE2E8F0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.all(24),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Title & Step Indicator
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.brandPurple.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _step == 1
                          ? Icons.lock_reset_rounded
                          : (_step == 2 ? Icons.mark_email_read_rounded : Icons.key_rounded),
                      color: AppTheme.brandPurple,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _step == 1
                              ? 'Reset Password'
                              : (_step == 2 ? 'Verify Security Code' : 'Set New Password'),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E293B),
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          _step == 1
                              ? 'Staff Authentication Recovery'
                              : (_step == 2 ? 'Check your email inbox' : 'Update login credentials'),
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Progress Indicator
              _buildStepIndicator(),
              const SizedBox(height: 20),

              // Error Banner (if any)
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerRose.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.dangerRose.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppTheme.dangerRose, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppTheme.dangerRose, fontSize: 12, height: 1.3),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _errorMessage = null),
                        child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.dangerRose),
                      ),
                    ],
                  ),
                ),

              // Dev Code Banner (when testing in environment without live SMTP)
              if (_step == 2 && _devCodeHint != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.developer_mode_rounded, color: Color(0xFFB45309), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Server Dev Code (SMTP Mock)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFFB45309)),
                            ),
                            Text(
                              'Verification Code: $_devCodeHint',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                        ),
                        onPressed: () => _codeCtrl.text = _devCodeHint!,
                        child: const Text('Auto-Fill', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),

              // STEP 1 CONTENT: Email Input
              if (_step == 1) ...[
                const Text(
                  'Enter your registered staff email address. A 6-digit verification code will be dispatched to your inbox via SMTP.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF475569), height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Registered Staff Email',
                    prefixIcon: const Icon(Icons.mail_outline_rounded, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _handleSendOtp(),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.wifi_off_rounded, size: 16, color: Color(0xFF64748B)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Remote Field Contingency: If your outreach camp is offline without cellular coverage, the on-site Super Administrator can reset your password immediately via Staff Management.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _isLoading ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.brandPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.send_rounded, size: 16),
                        label: Text(
                          _isLoading ? 'Sending Code...' : 'Send Reset Code',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        onPressed: _isLoading ? null : _handleSendOtp,
                      ),
                    ),
                  ],
                ),
              ],

              // STEP 2 CONTENT: Code Verification
              if (_step == 2) ...[
                Text(
                  'We sent a 6-digit security code to ${_emailCtrl.text.trim()}. Please enter it below:',
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569), height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  maxLength: 6,
                  style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E0A38),
                  ),
                  decoration: InputDecoration(
                    hintText: '••••••',
                    counterText: '',
                    hintStyle: const TextStyle(letterSpacing: 8, color: Color(0xFFCBD5E1)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onSubmitted: (_) => _handleVerifyCode(),
                ),
                const SizedBox(height: 12),
                Center(
                  child: _resendCountdown > 0
                      ? Text(
                          'Resend code in ${_resendCountdown}s',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        )
                      : TextButton.icon(
                          icon: const Icon(Icons.refresh_rounded, size: 15),
                          label: const Text('Resend Security Code', style: TextStyle(fontSize: 12)),
                          onPressed: _isLoading ? null : _handleSendOtp,
                        ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => setState(() {
                                  _step = 1;
                                  _errorMessage = null;
                                }),
                        child: const Text('Change Email'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.brandPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.verified_user_rounded, size: 16),
                        label: Text(
                          _isLoading ? 'Verifying...' : 'Verify Code',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        onPressed: _isLoading ? null : _handleVerifyCode,
                      ),
                    ),
                  ],
                ),
              ],

              // STEP 3 CONTENT: Set New Password
              if (_step == 3) ...[
                const Text(
                  'Code verified! Create your new secure password and optional station PIN below:',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF475569), height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'New Password *',
                    hintText: 'At least 6 characters',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 18,
                        color: const Color(0xFF64748B),
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmPasswordCtrl,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password *',
                    hintText: 'Re-enter password',
                    prefixIcon: const Icon(Icons.lock_reset_rounded, size: 18),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 18,
                        color: const Color(0xFF64748B),
                      ),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pinCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'Optional Station PIN (4-6 digits)',
                    hintText: 'e.g. 1234',
                    counterText: '',
                    helperText: 'For quick field workstation unlocks',
                    prefixIcon: const Icon(Icons.pin_outlined, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _isLoading ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_rounded, size: 16),
                        label: Text(
                          _isLoading ? 'Updating...' : 'Save & Sign In',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        onPressed: _isLoading ? null : _handleResetPassword,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
