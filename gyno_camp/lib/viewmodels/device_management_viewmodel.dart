import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/device_model.dart';
import '../repositories/device_security_repository.dart';
import 'device_security_viewmodel.dart';

class DeviceManagementState {
  final List<DeviceModel> devices;
  final String filterStatus; // 'ALL', 'PENDING_APPROVAL', 'APPROVED', 'REVOKED'
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const DeviceManagementState({
    this.devices = const [],
    this.filterStatus = 'ALL',
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

  int get pendingCount => devices.where((d) => d.status == DeviceActivationStatus.pendingApproval).length;
  int get approvedCount => devices.where((d) => d.status == DeviceActivationStatus.approved).length;
  int get revokedCount => devices.where((d) => d.status == DeviceActivationStatus.revoked).length;

  List<DeviceModel> get filteredDevices {
    if (filterStatus == 'ALL') return devices;
    return devices.where((d) => d.status.toDbString() == filterStatus).toList();
  }

  DeviceManagementState copyWith({
    List<DeviceModel>? devices,
    String? filterStatus,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    bool clearError = false,
    bool clearSuccess = false,
  }) {
    return DeviceManagementState(
      devices: devices ?? this.devices,
      filterStatus: filterStatus ?? this.filterStatus,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
    );
  }
}

class DeviceManagementViewModel extends StateNotifier<DeviceManagementState> {
  final IDeviceSecurityRepository _repository;
  final Ref? _ref;

  DeviceManagementViewModel(this._repository, [this._ref]) : super(const DeviceManagementState()) {
    loadDevices();
  }

  Future<void> loadDevices() async {
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      final list = await _repository.getAllDevices();
      if (!mounted) return;
      state = state.copyWith(devices: list, isLoading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load devices: $e',
      );
    }
  }

  void setFilter(String status) {
    state = state.copyWith(filterStatus: status);
  }

  Future<bool> approveDevice(String deviceId, {required String adminUserId}) async {
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      final success = await _repository.approveDevice(
        deviceId: deviceId,
        adminUserId: adminUserId,
      );
      if (success) {
        await loadDevices();
        if (!mounted) return true;
        state = state.copyWith(successMessage: 'Device successfully authorized.');
        _ref?.read(deviceSecurityProvider.notifier).checkCurrentDevice();
        return true;
      }
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to approve device.');
      return false;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, errorMessage: 'Approval error: $e');
      return false;
    }
  }

  Future<bool> revokeDevice(String deviceId, {required String adminUserId}) async {
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      final success = await _repository.revokeDevice(
        deviceId: deviceId,
        adminUserId: adminUserId,
      );
      if (success) {
        await loadDevices();
        if (!mounted) return true;
        state = state.copyWith(successMessage: 'Device access revoked.');
        _ref?.read(deviceSecurityProvider.notifier).checkCurrentDevice();
        return true;
      }
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to revoke device.');
      return false;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, errorMessage: 'Revocation error: $e');
      return false;
    }
  }
}

final deviceManagementProvider = StateNotifierProvider<DeviceManagementViewModel, DeviceManagementState>((ref) {
  final repo = ref.watch(deviceSecurityRepositoryProvider);
  return DeviceManagementViewModel(repo, ref);
});
