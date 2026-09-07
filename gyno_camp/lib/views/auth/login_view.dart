import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
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
  UserRole _selectedRole = UserRole.dataTaker;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _selectRole(UserRole role) {
    setState(() {
      _selectedRole = role;
    });
  }

  Future<void> _handleLogin(String deviceId) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your staff email or username.')),
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
    await authVm.login(email: email, password: password, deviceId: deviceId);
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.dataTaker:
        return AppTheme.primaryTeal;
      case UserRole.superAdmin:
        return const Color(0xFF4338CA);
      case UserRole.dataAnalyst:
        return const Color(0xFF0F766E);
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
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Brand Header
                  Center(
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primaryTeal, Color(0xFF0F766E)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryTeal.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.medical_services_rounded, size: 34, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 16),

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
                          Text(
                            deviceState.device?.deviceName != null
                                ? 'Authorized Terminal: ${deviceState.device!.deviceName} (RBAC Active)'
                                : 'Clinical Workstation (RBAC Active)',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF065F46)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Error Message Banner
                  if (authState.errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerRose.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.dangerRose),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppTheme.dangerRose, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              authState.errorMessage!,
                              style: const TextStyle(color: AppTheme.dangerRose, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Role Selection Header
                  const Text(
                    'Select User Role to Continue:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose your designated role to launch the station console or enter credentials below:',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 14),

                  // 3 Role Station Cards
                  _buildRoleCard(
                    title: 'Data Taker (Field Staff)',
                    nepaliTitle: 'डाटा टेकर (क्षेत्रीय कर्मचारी)',
                    subtitle: 'Station Intakes, Demographic Registration & Yellow Form Scanner',
                    description: 'Patient intake, vital signs triage, POP-Q clinical exams & offline local sync',
                    icon: Icons.assignment_ind_rounded,
                    color: AppTheme.primaryTeal,
                    isSelected: _selectedRole == UserRole.dataTaker,
                    onTap: () => _selectRole(UserRole.dataTaker),
                  ),
                  const SizedBox(height: 10),

                  _buildRoleCard(
                    title: 'Super Admin',
                    nepaliTitle: 'सुपर एडमिन (प्रणाली नियन्त्रक)',
                    subtitle: 'Lead Clinician, Camp Operations & Hardware Security',
                    description: 'Camp scheduling, staff deployment roster, device approvals & master formulary',
                    icon: Icons.admin_panel_settings_rounded,
                    color: const Color(0xFF4338CA),
                    isSelected: _selectedRole == UserRole.superAdmin,
                    onTap: () => _selectRole(UserRole.superAdmin),
                  ),
                  const SizedBox(height: 10),

                  _buildRoleCard(
                    title: 'Data Analyst',
                    nepaliTitle: 'डाटा विश्लेषक (तथ्याङ्कविद्)',
                    subtitle: 'Clinical Epidemiology, POP-Q Metrics & Aggregations',
                    description: 'Cohort analytics, prevalence indicators & instant PDF / Excel reporting',
                    icon: Icons.analytics_rounded,
                    color: const Color(0xFF0F766E),
                    isSelected: _selectedRole == UserRole.dataAnalyst,
                    onTap: () => _selectRole(UserRole.dataAnalyst),
                  ),
                  const SizedBox(height: 24),

                  // Credential Authentication Card
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(22.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getRoleColor(_selectedRole).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Active Station: ${_selectedRole.displayNameEn}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _getRoleColor(_selectedRole),
                                  ),
                                ),
                              ),
                              const Text(
                                'Staff Login (कर्मचारी लगइन)',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Email Field
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: 'Staff Email / Username',
                              prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Password Field
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Password / Security PIN',
                              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Submit Action Button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _getRoleColor(_selectedRole),
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
                                authState.isLoading ? 'Authenticating Session...' : 'Sign In as ${_selectedRole.displayNameEn}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.2),
                              ),
                              onPressed: authState.isLoading ? null : () => _handleLogin(deviceId),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Bottom Security Link
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.shield_outlined, size: 16, color: Color(0xFF64748B)),
                      label: const Text(
                        'Device Authorization & Security Management',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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

  Widget _buildRoleCard({
    required String title,
    required String nepaliTitle,
    required String subtitle,
    required String description,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: isSelected ? 2 : 0,
      color: isSelected ? color.withValues(alpha: 0.04) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected ? color : const Color(0xFFE2E8F0),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? color : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.check_circle_rounded, size: 16, color: color),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? color : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.radio_button_checked, size: 13, color: color),
                      const SizedBox(width: 4),
                      Text(
                        'Active',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                      ),
                    ],
                  ),
                )
              else
                const Icon(Icons.radio_button_unchecked, color: Color(0xFFCBD5E1), size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
