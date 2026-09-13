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
    expect(find.text('Pending Approval'), findsWidgets);
    expect(find.text('Authorized'), findsOneWidget);
    expect(find.text('Revoked'), findsOneWidget);

    expect(find.text('Kathmandu Clinic Tablet #1'), findsOneWidget);
    expect(find.text('Dhading Mobile Tablet #2'), findsOneWidget);
    expect(find.text('Approve Device'), findsOneWidget);
  });

  testWidgets('DeviceManagementView renders cleanly on narrow mobile viewport without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeDeviceSecurityRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    expect(find.text('Device Whitelist & Hardware Security'), findsOneWidget);
    expect(find.text('Kathmandu Clinic Tablet #1'), findsOneWidget);
    expect(find.text('Dhading Mobile Tablet #2'), findsOneWidget);
    expect(find.text('Approve Device'), findsOneWidget);
    expect(find.text('Details'), findsWidgets);
  });

  testWidgets('Real-time search filters devices by name, model, and fingerprint', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeDeviceSecurityRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Search for Dhading
    await tester.enterText(find.byType(TextField), 'Dhading');
    await tester.pumpAndSettle();

    expect(find.text('Dhading Mobile Tablet #2'), findsOneWidget);
    expect(find.text('Kathmandu Clinic Tablet #1'), findsNothing);

    // Clear search
    await tester.tap(find.byIcon(Icons.clear_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Kathmandu Clinic Tablet #1'), findsOneWidget);
    expect(find.text('Dhading Mobile Tablet #2'), findsOneWidget);

    // Search with no results
    await tester.enterText(find.byType(TextField), 'NonexistentTabletXYZ');
    await tester.pumpAndSettle();

    expect(find.text('No devices match "NonexistentTabletXYZ"'), findsOneWidget);
    expect(find.text('Clear Search'), findsOneWidget);

    // Tap Clear Search button in empty state
    await tester.tap(find.text('Clear Search'));
    await tester.pumpAndSettle();

    expect(find.text('Kathmandu Clinic Tablet #1'), findsOneWidget);
  });

  testWidgets('Status filter chips filter device list correctly', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeDeviceSecurityRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Tap Pending chip
    await tester.tap(find.text('Pending (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Dhading Mobile Tablet #2'), findsOneWidget);
    expect(find.text('Kathmandu Clinic Tablet #1'), findsNothing);

    // Tap Approved chip
    await tester.tap(find.text('Approved (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Kathmandu Clinic Tablet #1'), findsOneWidget);
    expect(find.text('Dhading Mobile Tablet #2'), findsNothing);
  });

  testWidgets('Tapping Details opens device security specification modal', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeDeviceSecurityRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Tap first Details button
    await tester.tap(find.text('Details').first);
    await tester.pumpAndSettle();

    expect(find.text('Device Security Specification'), findsOneWidget);
    expect(find.text('Hardware Model'), findsOneWidget);
    expect(find.text('Galaxy Tab A8'), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('hw-fp-ktm-001')), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Device Security Specification'), findsNothing);
  });

  testWidgets('Copy fingerprint button triggers feedback snackbar', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeDeviceSecurityRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Tap copy icon button
    await tester.tap(find.byIcon(Icons.copy_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('Hardware fingerprint copied to clipboard.'), findsOneWidget);
  });

  testWidgets('Approving and revoking devices updates status and displays SnackBar', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeDeviceSecurityRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Approve Dhading tablet
    await tester.tap(find.text('Approve Device'));
    await tester.pumpAndSettle();

    expect(find.text('Authorize Field Device?'), findsOneWidget);
    await tester.tap(find.text('Approve & Whitelist'));
    await tester.pumpAndSettle();

    expect(find.text('Device "Dhading Mobile Tablet #2" approved successfully.'), findsOneWidget);
    expect(fakeRepo.devices[1].status, DeviceActivationStatus.approved);

    // Now revoke Kathmandu tablet
    await tester.tap(find.text('Revoke Access').first);
    await tester.pumpAndSettle();

    expect(find.text('Revoke Device Access?'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Revoke Access')));
    await tester.pumpAndSettle();

    expect(find.text('Device "Kathmandu Clinic Tablet #1" access revoked.'), findsOneWidget);
    expect(fakeRepo.devices[0].status, DeviceActivationStatus.revoked);
  });
}
