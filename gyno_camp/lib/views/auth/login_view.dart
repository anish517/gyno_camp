import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';

class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key});

  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  final _emailController = TextEditingController(text: 'sita@gynocamp.org');
  final _passwordController = TextEditingController(text: 'pass123');
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
      switch (role) {
        case UserRole.dataTaker:
          _emailController.text = 'sita@gynocamp.org';
          _passwordController.text = 'pass123';
          break;
        case UserRole.superAdmin:
          _emailController.text = 'admin@gynocamp.org';
          _passwordController.text = 'admin123';
          break;
        case UserRole.dataAnalyst:
          _emailController.text = 'analyst@gynocamp.org';
          _passwordController.text = 'analyst123';
          break;
      }
    });
  }

  Future<void> _handleLogin(String deviceId) async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    final authVm = ref.read(authStateProvider.notifier);
    await authVm.login(email: email, deviceId: deviceId);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final authVm = ref.read(authStateProvider.notifier);
    final deviceState = ref.watch(deviceSecurityProvider);
    final deviceId = deviceState.device?.deviceId ?? 'dev-local';

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              // App Logo / Icon Header
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryTeal, width: 2),
                  ),
                  child: const Icon(Icons.medical_services_outlined, size: 36, color: AppTheme.primaryTeal),
                ),
              ),
              const SizedBox(height: 14),
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
                  fontSize: 14,
                  color: AppTheme.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 20),

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
                    const Icon(Icons.verified_user_outlined, color: AppTheme.successGreen, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Verified Device: ${deviceState.device?.deviceName ?? "Camp Field Tablet #1"} (RBAC Active)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.successGreen),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Error Message Banner
              if (authState.errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerRose.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
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

              // Credential Form Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Staff Login (कर्मचारी लगइन)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sign in with your registered account credentials to access role-specific clinical tools.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),

                      // Email Field
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Staff Email / Username',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Password Field
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password / Security PIN',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryTeal,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: authState.isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.login),
                          label: Text(
                            authState.isLoading ? 'Authenticating...' : 'Sign In as ${_selectedRole.displayNameEn}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          onPressed: authState.isLoading ? null : () => _handleLogin(deviceId),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Role Selection Section
              const Text(
                'Select User Role to Continue:',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap a staff role below to auto-fill verified credentials or fast-switch profile:',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),

              // Role Card 1: Data Taker
              _buildRoleCard(
                title: 'Data Taker (Field Staff)',
                nepaliTitle: 'डाटा टेकर (क्षेत्रीय कर्मचारी)',
                emailSubtitle: 'sita@gynocamp.org (Sita Sharma)',
                description: 'Registers patients, scans Yellow Form, and enters clinical data during camp.',
                icon: Icons.assignment_ind_outlined,
                color: AppTheme.primaryTeal,
                isSelected: _selectedRole == UserRole.dataTaker,
                onTap: () {
                  _selectRole(UserRole.dataTaker);
                  authVm.loginAsRole(role: UserRole.dataTaker, deviceId: deviceId);
                },
              ),
              const SizedBox(height: 10),

              // Role Card 2: Super Admin
              _buildRoleCard(
                title: 'Super Admin',
                nepaliTitle: 'सुपर एडमिन (प्रणाली नियन्त्रक)',
                emailSubtitle: 'admin@gynocamp.org (Dr. Aarav Sharma)',
                description: 'Manages camps, schedules staff, approves devices, and customizes form lists.',
                icon: Icons.admin_panel_settings_outlined,
                color: Colors.indigo,
                isSelected: _selectedRole == UserRole.superAdmin,
                onTap: () {
                  _selectRole(UserRole.superAdmin);
                  authVm.loginAsRole(role: UserRole.superAdmin, deviceId: deviceId);
                },
              ),
              const SizedBox(height: 10),

              // Role Card 3: Data Analyst
              _buildRoleCard(
                title: 'Data Analyst',
                nepaliTitle: 'डाटा विश्लेषक',
                emailSubtitle: 'analyst@gynocamp.org (Bikash Adhikari)',
                description: 'Reviews synced camp statistics and exports instant PDF and Excel reports.',
                icon: Icons.analytics_outlined,
                color: Colors.teal.shade800,
                isSelected: _selectedRole == UserRole.dataAnalyst,
                onTap: () {
                  _selectRole(UserRole.dataAnalyst);
                  authVm.loginAsRole(role: UserRole.dataAnalyst, deviceId: deviceId);
                },
              ),
              const SizedBox(height: 20),

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
    required String title,
    required String nepaliTitle,
    required String emailSubtitle,
    required String description,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: isSelected ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? color : Colors.transparent,
          width: isSelected ? 2 : 0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
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
                        Text(
                          title,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.check_circle, size: 16, color: color),
                        ],
                      ],
                    ),
                    Text(
                      emailSubtitle,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondaryLight),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
