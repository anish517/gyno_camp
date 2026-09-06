import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/security/security_service.dart';
import '../models/device_model.dart';
import '../repositories/device_security_repository.dart';

class DeviceSecurityState {
  final DeviceModel? device;
  final String hardwareFingerprint;
  final bool isChecking;
  final bool isAppLocked;
  final String? latestOtp; // Useful for demonstration/testing
  final String? errorMessage;

  const DeviceSecurityState({
    this.device,
    required this.hardwareFingerprint,
    this.isChecking = false,
    this.isAppLocked = true,
    this.latestOtp,
    this.errorMessage,
  });

  bool get isApproved => device?.isApproved ?? false;
  bool get isPendingOtp => device?.status == DeviceActivationStatus.pendingOtp;
  bool get isPendingApproval => device?.status == DeviceActivationStatus.pendingApproval;
  bool get isRevoked => device?.status == DeviceActivationStatus.revoked;
  bool get isUnregistered => device == null || device?.status == DeviceActivationStatus.unregistered;
  bool get requiresPinSetup => isApproved && !(device?.hasPinSet ?? false);

  DeviceSecurityState copyWith({
    DeviceModel? device,
    String? hardwareFingerprint,
    bool? isChecking,
    bool? isAppLocked,
    String? latestOtp,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DeviceSecurityState(
      device: device ?? this.device,
      hardwareFingerprint: hardwareFingerprint ?? this.hardwareFingerprint,
      isChecking: isChecking ?? this.isChecking,
      isAppLocked: isAppLocked ?? this.isAppLocked,
      latestOtp: latestOtp ?? this.latestOtp,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class DeviceSecurityViewModel extends StateNotifier<DeviceSecurityState> {
  final IDeviceSecurityRepository _repository;

  DeviceSecurityViewModel(this._repository)
      : super(DeviceSecurityState(
          hardwareFingerprint: SecurityService.generateDeviceFingerprint(),
        )) {
    checkCurrentDevice();
  }

  Future<void> checkCurrentDevice() async {
    state = state.copyWith(isChecking: true, clearError: true);
    try {
      final dev = await _repository.getDeviceByFingerprint(state.hardwareFingerprint);
      if (!mounted) return;
      final isLocked = dev?.isApproved == true && (dev?.hasPinSet == true);
      state = state.copyWith(
        device: dev,
        isChecking: false,
        isAppLocked: isLocked,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isChecking: false,
        errorMessage: 'Failed to verify device: $e',
      );
    }
  }

  Future<bool> requestRegistration({
    required String deviceName,
    required String staffUserId,
    required String staffName,
  }) async {
    state = state.copyWith(isChecking: true, clearError: true);
    try {
      final result = await _repository.requestDeviceRegistration(
        deviceName: deviceName,
        model: 'Android Field Tablet',
        hardwareFingerprint: state.hardwareFingerprint,
        staffUserId: staffUserId,
        staffName: staffName,
      );

      state = state.copyWith(
        device: result.device,
        latestOtp: result.plainOtp,
        isChecking: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isChecking: false,
        errorMessage: 'Registration failed: $e',
      );
      return false;
    }
  }

  Future<bool> verifyOtp(String otp) async {
    if (state.device == null) return false;
    state = state.copyWith(isChecking: true, clearError: true);

    try {
      final success = await _repository.verifyOtp(
        deviceId: state.device!.deviceId,
        enteredOtp: otp,
      );

      if (success) {
        final updated = await _repository.getDeviceById(state.device!.deviceId);
        state = state.copyWith(
          device: updated,
          isChecking: false,
        );
        return true;
      } else {
        state = state.copyWith(
          isChecking: false,
          errorMessage: 'Invalid or expired OTP. Please try again.',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isChecking: false,
        errorMessage: 'OTP Verification error: $e',
      );
      return false;
    }
  }

  Future<bool> approveDeviceByAdmin({required String adminUserId}) async {
    if (state.device == null) return false;
    state = state.copyWith(isChecking: true, clearError: true);

    try {
      final success = await _repository.approveDevice(
        deviceId: state.device!.deviceId,
        adminUserId: adminUserId,
      );

      if (success) {
        final updated = await _repository.getDeviceById(state.device!.deviceId);
        state = state.copyWith(
          device: updated,
          isChecking: false,
        );
        return true;
      } else {
        state = state.copyWith(isChecking: false, errorMessage: 'Failed to approve device.');
        return false;
      }
    } catch (e) {
      state = state.copyWith(isChecking: false, errorMessage: 'Approval error: $e');
      return false;
    }
  }

  Future<bool> setupPin(String pin) async {
    if (state.device == null) return false;
    try {
      final success = await _repository.setAppLockPin(
        deviceId: state.device!.deviceId,
        pin: pin,
      );
      if (success) {
        final updated = await _repository.getDeviceById(state.device!.deviceId);
        state = state.copyWith(device: updated, isAppLocked: false);
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(errorMessage: 'PIN setup failed: $e');
      return false;
    }
  }

  Future<bool> unlockWithPin(String pin) async {
    if (state.device == null) return false;
    final valid = await _repository.verifyAppLockPin(
      deviceId: state.device!.deviceId,
      enteredPin: pin,
    );

    if (valid) {
      state = state.copyWith(isAppLocked: false, clearError: true);
      return true;
    } else {
      state = state.copyWith(errorMessage: 'Incorrect PIN. Try again.');
      return false;
    }
  }

  void lockApp() {
    state = state.copyWith(isAppLocked: true);
  }
}

final deviceSecurityRepositoryProvider = Provider<IDeviceSecurityRepository>((ref) {
  return DeviceSecurityRepository();
});

final deviceSecurityProvider = StateNotifierProvider<DeviceSecurityViewModel, DeviceSecurityState>((ref) {
  final repository = ref.watch(deviceSecurityRepositoryProvider);
  return DeviceSecurityViewModel(repository);
});
