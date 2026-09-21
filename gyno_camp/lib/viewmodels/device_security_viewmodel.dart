import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/security/security_service.dart';
import '../models/device_model.dart';
import '../repositories/device_security_repository.dart';
import 'device_management_viewmodel.dart';

class DeviceSecurityState {
  final DeviceModel? device;
  final String hardwareFingerprint;
  final bool isChecking;
  final bool isAppLocked;
  final String? latestOtp; // Useful for demonstration/testing
  final String? errorMessage;
  final bool isInitialized;

  const DeviceSecurityState({
    this.device,
    required this.hardwareFingerprint,
    this.isChecking = false,
    this.isAppLocked = true,
    this.latestOtp,
    this.errorMessage,
    this.isInitialized = false,
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
    bool? isInitialized,
    bool clearError = false,
  }) {
    return DeviceSecurityState(
      device: device ?? this.device,
      hardwareFingerprint: hardwareFingerprint ?? this.hardwareFingerprint,
      isChecking: isChecking ?? this.isChecking,
      isAppLocked: isAppLocked ?? this.isAppLocked,
      latestOtp: latestOtp ?? this.latestOtp,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

class DeviceSecurityViewModel extends StateNotifier<DeviceSecurityState> {
  final IDeviceSecurityRepository _repository;
  final Ref? _ref;
  Timer? _approvalPollTimer;

  DeviceSecurityViewModel(this._repository, [this._ref])
      : super(DeviceSecurityState(
          hardwareFingerprint: SecurityService.generateDeviceFingerprint(),
          isChecking: true,
          isInitialized: false,
        )) {
    checkCurrentDevice();
  }

  void _startPollingApproval() {
    if (_approvalPollTimer != null && _approvalPollTimer!.isActive) return;
    _approvalPollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted) {
        _stopPollingApproval();
        return;
      }
      await checkCurrentDevice(silent: true);
      if (state.isApproved) {
        _stopPollingApproval();
      }
    });
  }

  void _stopPollingApproval() {
    _approvalPollTimer?.cancel();
    _approvalPollTimer = null;
  }

  @override
  void dispose() {
    _stopPollingApproval();
    super.dispose();
  }

  Future<void> checkCurrentDevice({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(isChecking: true, clearError: true);
    }
    try {
      final dev = await _repository.getDeviceByFingerprint(state.hardwareFingerprint);
      if (!mounted) return;
      final isLocked = dev?.isApproved == true && (dev?.hasPinSet == true);
      state = state.copyWith(
        device: dev,
        isChecking: false,
        isAppLocked: isLocked,
        isInitialized: true,
      );

      if (dev?.status == DeviceActivationStatus.pendingApproval) {
        _startPollingApproval();
      } else {
        _stopPollingApproval();
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isChecking: false,
        isInitialized: true,
        errorMessage: silent ? null : 'Failed to verify device: $e',
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

      if (!mounted) return true;
      state = state.copyWith(
        device: result.device,
        latestOtp: result.plainOtp,
        isChecking: false,
      );
      _ref?.read(deviceManagementProvider.notifier).loadDevices();
      return true;
    } catch (e) {
      if (!mounted) return false;
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
        if (!mounted) return true;
        state = state.copyWith(
          device: updated,
          isChecking: false,
        );
        _ref?.read(deviceManagementProvider.notifier).loadDevices();
        if (updated?.status == DeviceActivationStatus.pendingApproval) {
          _startPollingApproval();
        }
        return true;
      } else {
        if (!mounted) return false;
        state = state.copyWith(
          isChecking: false,
          errorMessage: 'Invalid or expired OTP. Please try again.',
        );
        return false;
      }
    } catch (e) {
      if (!mounted) return false;
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
        if (!mounted) return true;
        state = state.copyWith(
          device: updated,
          isChecking: false,
        );
        _ref?.read(deviceManagementProvider.notifier).loadDevices();
        return true;
      } else {
        if (!mounted) return false;
        state = state.copyWith(isChecking: false, errorMessage: 'Failed to approve device.');
        return false;
      }
    } catch (e) {
      if (!mounted) return false;
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
        if (!mounted) return true;
        state = state.copyWith(device: updated, isAppLocked: false);
        return true;
      }
      return false;
    } catch (e) {
      if (!mounted) return false;
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

    if (!mounted) return valid;
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
  return DeviceSecurityViewModel(repository, ref);
});
