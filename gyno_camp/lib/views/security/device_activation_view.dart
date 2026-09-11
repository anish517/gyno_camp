import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../splash/security_gateway_view.dart';

class DeviceActivationView extends ConsumerStatefulWidget {
  final String? prefillStaffName;
  final String? prefillStaffUserId;

  const DeviceActivationView({
    super.key,
    this.prefillStaffName,
    this.prefillStaffUserId,
  });

  @override
  ConsumerState<DeviceActivationView> createState() => _DeviceActivationViewState();
}

class _DeviceActivationViewState extends ConsumerState<DeviceActivationView> {
  final _deviceNameController = TextEditingController();
  final _otpController = TextEditingController();
  late final TextEditingController _staffNameController;

  @override
  void initState() {
    super.initState();
    _staffNameController = TextEditingController(text: widget.prefillStaffName ?? '');
  }

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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Return to Login',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const SecurityGatewayView()),
                (route) => false,
              );
            }
          },
        ),
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
                          staffUserId: widget.prefillStaffUserId ?? 'usr-staff-${DateTime.now().millisecondsSinceEpoch}',
                          staffName: staffName,
                        );
                      },
              ),
            ],

            // Step 2: OTP Entry (If pending OTP)
            if (state.isPendingOtp) ...[
              const Text(
                'Step 2: Enter 6-Digit Verification Code',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.mark_email_read_outlined, color: AppTheme.primaryTeal, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'A 6-digit one-time authorization code has been issued for this device. Please enter the verification code to activate this hardware.',
                        style: TextStyle(fontSize: 12.5, color: AppTheme.primaryDark),
                      ),
                    ),
                  ],
                ),
              ),
              if (state.latestOtp != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF93C5FD)),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.pin_outlined, color: Color(0xFF1D4ED8), size: 22),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Security Authorization Code (SMS / Local Terminal):',
                                style: TextStyle(fontSize: 11, color: Color(0xFF1E40AF), fontWeight: FontWeight.w600),
                              ),
                              Text(
                                state.latestOtp!,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 3,
                                  color: Color(0xFF1E3A8A),
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFDBEAFE),
                          foregroundColor: const Color(0xFF1D4ED8),
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Fill Code', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          setState(() {
                            _otpController.text = state.latestOtp!;
                          });
                        },
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
                label: const Text('Verify Code'),
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
                      'Awaiting Central Administrator Approval',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Hardware signature has been verified and registered. The Super Administrator can authorize this workstation from the central Admin Console (Device Whitelist & Security).',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Check Authorization Status'),
                      onPressed: () => vm.checkCurrentDevice(),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Return to Staff Login'),
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const SecurityGatewayView()),
                          (route) => false,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],

            // Step 4: Approved & Whitelisted Device
            if (state.isApproved) ...[
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF059669).withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(
                        color: Color(0xFFD1FAE5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.verified_rounded, color: Color(0xFF059669), size: 36),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Terminal Hardware Approved & Authorized',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Device "${state.device?.deviceName ?? "Workstation"}" has been whitelisted by Super Admin. You can now log in to your designated clinical role console.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF047857), height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: const Text(
                          'Proceed to Staff Sign-In',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        onPressed: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const SecurityGatewayView()),
                            (route) => false,
                          );
                        },
                      ),
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
