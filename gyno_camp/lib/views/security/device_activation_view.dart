import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/device_security_viewmodel.dart';

class DeviceActivationView extends ConsumerStatefulWidget {
  const DeviceActivationView({super.key});

  @override
  ConsumerState<DeviceActivationView> createState() => _DeviceActivationViewState();
}

class _DeviceActivationViewState extends ConsumerState<DeviceActivationView> {
  final _deviceNameController = TextEditingController();
  final _otpController = TextEditingController();
  final _staffNameController = TextEditingController();

  @override
  void dispose() {
    _deviceNameController.dispose();
    _otpController.dispose();
    _staffNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceSecurityProvider);
    final vm = ref.read(deviceSecurityProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Authorization & Activation'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Security Info Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.security, color: AppTheme.primaryTeal, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Secure Device Access: This app only runs on organization-approved devices. OTP verification and Super Admin approval are mandatory.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.primaryDark,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Hardware Fingerprint Display
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'HARDWARE SIGNATURE',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      state.hardwareFingerprint,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Status: ', style: TextStyle(fontSize: 13)),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            state.device?.status.displayNameEn ?? 'Unregistered',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          backgroundColor: state.isApproved
                              ? AppTheme.successGreen.withValues(alpha: 0.15)
                              : state.isPendingApproval
                                  ? AppTheme.warningAmber.withValues(alpha: 0.15)
                                  : Colors.grey.withValues(alpha: 0.2),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Error display
            if (state.errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.dangerRose.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.dangerRose),
                ),
                child: Text(
                  state.errorMessage!,
                  style: const TextStyle(color: AppTheme.dangerRose, fontSize: 13),
                ),
              ),

            // Step 1: Request Activation (If unregistered)
            if (state.isUnregistered) ...[
              const Text(
                'Step 1: Request Device Activation',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _deviceNameController,
                decoration: const InputDecoration(
                  labelText: 'Device Nickname / Label',
                  hintText: 'e.g. Registration Desk Tablet #1',
                  prefixIcon: Icon(Icons.tablet_android),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _staffNameController,
                decoration: const InputDecoration(
                  labelText: 'Requesting Field Staff Name',
                  hintText: 'e.g. Sita Sharma (Field Nurse)',
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('Send Activation OTP Request'),
                onPressed: state.isChecking
                    ? null
                    : () async {
                        final deviceName = _deviceNameController.text.trim();
                        final staffName = _staffNameController.text.trim();
                        if (deviceName.isEmpty || staffName.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter both a Device Label and your Staff Name'),
                              backgroundColor: AppTheme.dangerRose,
                            ),
                          );
                          return;
                        }
                        await vm.requestRegistration(
                          deviceName: deviceName,
                          staffUserId: 'usr-datataker-01',
                          staffName: staffName,
                        );
                      },
              ),
            ],

            // Step 2: OTP Entry (If pending OTP)
            if (state.isPendingOtp) ...[
              const Text(
                'Step 2: Enter 6-Digit OTP Code',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (state.latestOtp != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Test OTP generated: ${state.latestOtp}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          _otpController.text = state.latestOtp!;
                        },
                        child: const Text('Auto-Fill'),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: '6-Digit Verification Code',
                  prefixIcon: Icon(Icons.password),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.verified),
                label: const Text('Verify OTP'),
                onPressed: state.isChecking
                    ? null
                    : () async {
                        await vm.verifyOtp(_otpController.text.trim());
                      },
              ),
            ],

            // Step 3: Pending Super Admin Approval
            if (state.isPendingApproval) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.hourglass_top, color: Colors.orange, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'Awaiting Super Admin Approval',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'OTP verified successfully! Your device request has been forwarded to the Super Admin dashboard. You will be able to access the app once approved.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Check Approval Status'),
                      onPressed: () => vm.checkCurrentDevice(),
                    ),
                    const SizedBox(height: 8),
                    // Quick Action for Demo & Testing
                    TextButton.icon(
                      icon: const Icon(Icons.admin_panel_settings),
                      label: const Text('Demo: Approve via Super Admin'),
                      onPressed: () async {
                        await vm.approveDeviceByAdmin(adminUserId: 'usr-superadmin-01');
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
