import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/auth_viewmodel.dart';
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
  final _passwordFocusNode = FocusNode();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onFieldChanged);
    _passwordController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (!mounted) return;
    // Clear stale server/auth errors immediately when user modifies input
    if (ref.read(authStateProvider).errorMessage != null) {
      ref.read(authStateProvider.notifier).clearError();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _emailController.removeListener(_onFieldChanged);
    _passwordController.removeListener(_onFieldChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
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

    if (!success || !mounted) return;

    final user = ref.read(authStateProvider).currentUser;
    if (user == null) return;

    // If regular staff (non-admin), enforce hardware registration & approval
    if (!user.isSuperAdmin) {
      final currentDeviceState = ref.read(deviceSecurityProvider);
      if (!currentDeviceState.isApproved) {
        // Clear active session immediately so the user is not authenticated on unapproved hardware
        await authVm.logout(deviceId: deviceId);
        if (!mounted) return;

        if (currentDeviceState.isUnregistered) {
          showDialog(
            context: context,
            barrierDismissible: false,
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
              content: Text(
                'Welcome, ${user.name}. This workstation is not yet recognized on the clinical outreach network. For medical record security, new hardware must be registered and authorized by the Super Admin before clinical intake begins.',
                style: const TextStyle(fontSize: 13.5, height: 1.4, color: Color(0xFF334155)),
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
                    Navigator.pop(ctx);
                    if (mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DeviceActivationView(
                            prefillStaffName: user.name,
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
          return;
        } else if (currentDeviceState.isPendingApproval) {
          showDialog(
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
                colors: [Color(0xFF042F2E), Color(0xFF0F766E), Color(0xFF0D9488)],
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
                      color: const Color(0xFF2DD4BF).withValues(alpha: 0.08),
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
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.medical_services_rounded,
                                color: Color(0xFF0F766E),
                                size: 28,
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Error Message Banner (if any)
        if (authState.errorMessage != null)
          Container(
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
                        color: AppTheme.primaryTeal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 12, color: AppTheme.primaryTeal),
                          SizedBox(width: 4),
                          Text(
                            'Auto-Detect Role',
                            style: TextStyle(
                              fontSize: 10.5,
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
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: 'Enter registered staff email or phone',
                    hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.alternate_email_rounded, size: 18, color: Color(0xFF64748B)),
                    suffixIcon: _emailController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16, color: Color(0xFF94A3B8)),
                            onPressed: () => _emailController.clear(),
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onSubmitted: (_) {
                    FocusScope.of(context).requestFocus(_passwordFocusNode);
                  },
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
                      style: TextStyle(fontSize: 11, color: Colors.teal.shade700, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  obscureText: _obscurePassword,
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
                const SizedBox(height: 20),

                // Submit Action Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 1,
                      shadowColor: AppTheme.primaryTeal.withValues(alpha: 0.3),
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
