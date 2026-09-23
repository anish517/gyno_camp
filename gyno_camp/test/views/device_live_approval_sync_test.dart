import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/security/security_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/device_model.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/auth_repository.dart';
import 'package:gyno_camp/repositories/device_security_repository.dart';
import 'package:gyno_camp/viewmodels/auth_viewmodel.dart';
import 'package:gyno_camp/viewmodels/device_security_viewmodel.dart';
import 'package:gyno_camp/views/admin/device_management_view.dart';
import 'package:gyno_camp/views/auth/login_view.dart';
import 'package:gyno_camp/views/security/device_activation_view.dart';

class _MockDataStore {
  final List<UserModel> users = [
    UserModel(
      id: 'usr-superadmin-01',
      name: 'System Administrator',
      email: 'admin@gynocamp.org',
      phone: '9851000001',
      role: UserRole.superAdmin,
      isActive: true,
      tenantId: 'tenant-01',
      tenantName: 'Nepal Health Outreach Network',
      passwordHash: SecurityService.hashSha256('admin123'),
      pinHash: SecurityService.hashPin('1234'),
    ),
    UserModel(
      id: 'usr-anita-99',
      name: 'Anita Tamang',
      email: 'anita.tamang@gynocamp.org',
      phone: '9841999888',
      role: UserRole.dataTaker,
      isActive: true,
      tenantId: 'tenant-01',
      tenantName: 'Nepal Health Outreach Network',
      passwordHash: SecurityService.hashSha256('anitaPass123'),
      pinHash: SecurityService.hashPin('7788'),
    ),
  ];

  final List<CampModel> camps = [];
  final List<DeviceModel> devices = [];
}

class _FakeAuthRepo implements IAuthRepository {
  final _MockDataStore store;
  UserModel? _current;

  _FakeAuthRepo(this.store);

  @override
  UserModel? get currentUser => _current;

  @override
  void setCurrentUser(UserModel? user) => _current = user;

  @override
  Future<UserModel?> getUserByEmail(String email) async {
    final lower = email.trim().toLowerCase();
    try {
      return store.users.firstWhere((u) => u.email.toLowerCase() == lower);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<UserModel?> getUserById(String id) async {
    try {
      return store.users.firstWhere((u) => u.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<UserModel>> getAllUsers({bool includeInactive = false}) async {
    return store.users.where((u) => includeInactive || u.isActive).toList();
  }

  @override
  Future<UserModel> createUser({
    required UserModel user,
    required String adminUserId,
    required String deviceId,
  }) async {
    store.users.add(user);
    return user;
  }

  @override
  Future<UserModel> updateUser({
    required UserModel user,
    required String adminUserId,
    required String deviceId,
  }) async {
    final idx = store.users.indexWhere((u) => u.id == user.id);
    if (idx != -1) store.users[idx] = user;
    return user;
  }

  @override
  Future<void> deleteUser({
    required String userId,
    required String adminUserId,
    required String deviceId,
  }) async {
    store.users.removeWhere((u) => u.id == userId);
  }

  @override
  Future<UserModel?> login({
    required String email,
    String? password,
    required String deviceId,
  }) async {
    final user = await getUserByEmail(email);
    if (user == null || !user.isActive) return null;

    if (password != null && password.isNotEmpty) {
      final inputHash = SecurityService.hashSha256(password);
      final isPinValid = user.pinHash != null && SecurityService.verifyPin(password, user.pinHash!);
      final isPasswordValid = user.passwordHash == inputHash;
      if (!isPasswordValid && !isPinValid) return null;
    }

    _current = user;
    return user;
  }

  @override
  Future<UserModel?> loginAsRole({required UserRole role, required String deviceId}) async {
    final user = store.users.firstWhere((u) => u.role == role, orElse: () => store.users.first);
    _current = user;
    return user;
  }

  @override
  Future<void> logout({required String deviceId}) async {
    _current = null;
  }

  @override
  Future<List<String>> getValidCampsForUser(List<String> assignedCampIds) async => assignedCampIds;
}

class _FakeDeviceRepo implements IDeviceSecurityRepository {
  final _MockDataStore store;

  _FakeDeviceRepo(this.store);

  @override
  Future<List<DeviceModel>> getAllDevices() async => List.from(store.devices);

  @override
  Future<List<DeviceModel>> getPendingDevices() async {
    return store.devices.where((d) => d.status == DeviceActivationStatus.pendingApproval).toList();
  }

  @override
  Future<DeviceModel?> getDeviceByFingerprint(String fingerprint) async {
    try {
      return store.devices.firstWhere((d) => d.hardwareFingerprint == fingerprint);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DeviceModel?> getDeviceById(String deviceId) async {
    try {
      return store.devices.firstWhere((d) => d.deviceId == deviceId);
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
    const plainOtp = '654321';
    final dev = DeviceModel(
      deviceId: 'dev-${DateTime.now().millisecondsSinceEpoch}',
      deviceName: deviceName,
      model: model,
      hardwareFingerprint: hardwareFingerprint,
      status: DeviceActivationStatus.pendingOtp,
      registeredByUserId: staffUserId,
      registeredByName: staffName,
      registeredAt: DateTime.now(),
      otpHash: SecurityService.hashSha256(plainOtp),
      otpExpiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
    store.devices.add(dev);
    return (device: dev, plainOtp: plainOtp);
  }

  @override
  Future<bool> verifyOtp({required String deviceId, required String enteredOtp}) async {
    final idx = store.devices.indexWhere((d) => d.deviceId == deviceId);
    if (idx == -1) return false;
    final dev = store.devices[idx];
    if (enteredOtp == '654321') {
      store.devices[idx] = dev.copyWith(status: DeviceActivationStatus.pendingApproval);
      return true;
    }
    return false;
  }

  @override
  Future<bool> approveDevice({required String deviceId, required String adminUserId}) async {
    final idx = store.devices.indexWhere((d) => d.deviceId == deviceId);
    if (idx == -1) return false;
    store.devices[idx] = store.devices[idx].copyWith(
      status: DeviceActivationStatus.approved,
      approvedByUserId: adminUserId,
      approvedAt: DateTime.now(),
    );
    return true;
  }

  @override
  Future<bool> revokeDevice({required String deviceId, required String adminUserId}) async {
    final idx = store.devices.indexWhere((d) => d.deviceId == deviceId);
    if (idx == -1) return false;
    store.devices[idx] = store.devices[idx].copyWith(status: DeviceActivationStatus.revoked);
    return true;
  }

  @override
  Future<bool> setAppLockPin({required String deviceId, required String pin}) async {
    final idx = store.devices.indexWhere((d) => d.deviceId == deviceId);
    if (idx == -1) return false;
    store.devices[idx] = store.devices[idx].copyWith(pinHash: SecurityService.hashPin(pin));
    return true;
  }

  @override
  Future<bool> verifyAppLockPin({required String deviceId, required String enteredPin}) async {
    final dev = await getDeviceById(deviceId);
    if (dev?.pinHash == null) return false;
    return SecurityService.verifyPin(enteredPin, dev!.pinHash!);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Real-time sync: Device registration appears in Admin immediately, and approval unlocks login immediately without app reload',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final store = _MockDataStore();
      final authRepo = _FakeAuthRepo(store);
      final deviceRepo = _FakeDeviceRepo(store);

      // SINGLE persistent container to simulate a live app without reload
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepo),
          deviceSecurityRepositoryProvider.overrideWithValue(deviceRepo),
        ],
      );
      addTearDown(container.dispose);

      // -------------------------------------------------------------
      // 1. Device Registration in DeviceActivationView
      // -------------------------------------------------------------
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DeviceActivationView()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Step 1: Request Device Activation'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Device Nickname / Label'),
        'Pokhara Outreach Tablet #1',
      );
      await tester.enterText(
        find.widgetWithText(TextField, "Requesting Person's Name"),
        'Anita Tamang',
      );
      await tester.tap(find.text('Send Activation OTP Request'));
      await tester.pumpAndSettle();

      // Enter OTP
      expect(find.text('Step 2: Enter 6-Digit Verification Code'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, '6-Digit Verification Code'),
        '654321',
      );
      await tester.tap(find.text('Verify Code'));
      await tester.pumpAndSettle();

      // Device is now awaiting approval
      expect(find.text('Awaiting Central Administrator Approval'), findsOneWidget);

      // -------------------------------------------------------------
      // 2. Super Admin opens DeviceManagementView WITHOUT RELOADING
      // -------------------------------------------------------------
      authRepo.setCurrentUser(store.users.first); // Admin logged in

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DeviceManagementView()),
        ),
      );
      await tester.pumpAndSettle();

      // The pending device MUST appear immediately without reload
      expect(find.text('Pokhara Outreach Tablet #1'), findsOneWidget);
      expect(find.textContaining('Anita Tamang'), findsOneWidget);
      expect(find.text('Approve Device'), findsOneWidget);

      // Super Admin approves the device
      await tester.tap(find.text('Approve Device'));
      await tester.pumpAndSettle();

      expect(find.text('Authorize Field Device?'), findsOneWidget);
      await tester.tap(find.text('Approve & Whitelist'));
      await tester.pumpAndSettle();

      // Status in store is approved
      expect(store.devices.first.status, DeviceActivationStatus.approved);

      // -------------------------------------------------------------
      // 3. Navigate to DeviceActivationView WITHOUT RELOADING
      // -------------------------------------------------------------
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DeviceActivationView()),
        ),
      );
      await tester.pumpAndSettle();

      // MUST display approved terminal immediately without reload
      expect(find.text('Terminal Hardware Approved & Authorized'), findsOneWidget);
      expect(find.textContaining('Pokhara Outreach Tablet #1'), findsWidgets);

      // -------------------------------------------------------------
      // 4. Navigate to LoginView and login as staff WITHOUT RELOADING
      // -------------------------------------------------------------
      authRepo.setCurrentUser(null); // Log out

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LoginView()),
        ),
      );
      await tester.pumpAndSettle();

      final emailField = find.byType(TextField).at(0);
      final passField = find.byType(TextField).at(1);

      await tester.enterText(emailField, 'anita.tamang@gynocamp.org');
      await tester.enterText(passField, 'anitaPass123');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In to GynoCamp'));
      await tester.pumpAndSettle();

      // Anita is logged in successfully! No "Device Pending Approval" dialog!
      expect(find.text('Device Pending Approval'), findsNothing);
      expect(authRepo.currentUser?.email, 'anita.tamang@gynocamp.org');
      expect(authRepo.currentUser?.role, UserRole.dataTaker);
    },
  );
}
