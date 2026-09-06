import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/device_model.dart';
import 'package:gyno_camp/repositories/device_security_repository.dart';
import 'package:gyno_camp/viewmodels/device_security_viewmodel.dart';
import 'package:gyno_camp/views/admin/device_management_view.dart';

class FakeDeviceSecurityRepository implements IDeviceSecurityRepository {
  List<DeviceModel> devices = [
    DeviceModel(
      deviceId: 'dev-01',
      deviceName: 'Kathmandu Clinic Tablet #1',
      model: 'Galaxy Tab A8',
      hardwareFingerprint: 'hw-fp-ktm-001',
      status: DeviceActivationStatus.approved,
      registeredAt: DateTime(2026, 9, 1),
      registeredByName: 'Sita Sharma',
    ),
    DeviceModel(
      deviceId: 'dev-02',
      deviceName: 'Dhading Mobile Tablet #2',
      model: 'Galaxy Tab A7',
      hardwareFingerprint: 'hw-fp-dhn-002',
      status: DeviceActivationStatus.pendingApproval,
      registeredAt: DateTime(2026, 9, 2),
      registeredByName: 'Gita Thapa',
    ),
  ];

  @override
  Future<List<DeviceModel>> getAllDevices() async => devices;

  @override
  Future<List<DeviceModel>> getPendingDevices() async {
    return devices.where((d) => d.status == DeviceActivationStatus.pendingApproval).toList();
  }

  @override
  Future<DeviceModel?> getDeviceByFingerprint(String fingerprint) async {
    try {
      return devices.firstWhere((d) => d.hardwareFingerprint == fingerprint);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DeviceModel?> getDeviceById(String deviceId) async {
    try {
      return devices.firstWhere((d) => d.deviceId == deviceId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<({DeviceModel device, String plainOtp})> requestDeviceRegistration({
    required String deviceName,
    required String model,
    required String hardwareFingerprint,
    required String staffUserId,
    required String staffName,
  }) async {
    final dev = DeviceModel(
      deviceId: 'dev-${DateTime.now().millisecondsSinceEpoch}',
      deviceName: deviceName,
      model: model,
      hardwareFingerprint: hardwareFingerprint,
      status: DeviceActivationStatus.pendingOtp,
      registeredAt: DateTime.now(),
      registeredByName: staffName,
    );
    devices.add(dev);
    return (device: dev, plainOtp: '123456');
  }

  @override
  Future<bool> verifyOtp({required String deviceId, required String enteredOtp}) async => true;

  @override
  Future<bool> approveDevice({required String deviceId, required String adminUserId}) async {
    final idx = devices.indexWhere((d) => d.deviceId == deviceId);
    if (idx != -1) {
      devices[idx] = devices[idx].copyWith(status: DeviceActivationStatus.approved);
      return true;
    }
    return false;
  }

  @override
  Future<bool> revokeDevice({required String deviceId, required String adminUserId}) async {
    final idx = devices.indexWhere((d) => d.deviceId == deviceId);
    if (idx != -1) {
      devices[idx] = devices[idx].copyWith(status: DeviceActivationStatus.revoked);
      return true;
    }
    return false;
  }

  @override
  Future<bool> setAppLockPin({required String deviceId, required String pin}) async => true;

  @override
  Future<bool> verifyAppLockPin({required String deviceId, required String enteredPin}) async => true;
}

void main() {
  Widget createTestWidget(IDeviceSecurityRepository repo) {
    return ProviderScope(
      overrides: [
        deviceSecurityRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const DeviceManagementView(),
      ),
    );
  }

  testWidgets('DeviceManagementView renders device cards and approval actions', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeDeviceSecurityRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    expect(find.text('Device Whitelist & Hardware Security'), findsOneWidget);
    expect(find.text('Pending Approval'), findsOneWidget);
    expect(find.text('Authorized'), findsOneWidget);
    expect(find.text('Revoked'), findsOneWidget);

    expect(find.text('Kathmandu Clinic Tablet #1'), findsOneWidget);
    expect(find.text('Dhading Mobile Tablet #2'), findsOneWidget);
    expect(find.text('Approve Device'), findsOneWidget);
  });
}
