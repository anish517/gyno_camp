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
import 'package:gyno_camp/viewmodels/device_management_viewmodel.dart';
import 'package:gyno_camp/viewmodels/device_security_viewmodel.dart';
import 'package:gyno_camp/views/admin/device_management_view.dart';
import 'package:gyno_camp/views/auth/login_view.dart';
import 'package:gyno_camp/views/dashboard/home_gateway_view.dart';
import 'package:gyno_camp/views/security/device_activation_view.dart';

class MockDataStore {
  final List<UserModel> users = [
    UserModel(
      id: 'usr-superadmin-01',
      name: 'System Administrator (Super Admin)',
      email: 'admin@gynocamp.org',
      phone: '9851000001',
      role: UserRole.superAdmin,
      isActive: true,
      tenantId: 'tenant-01',
      tenantName: 'Nepal Health Outreach Network',
      passwordHash: SecurityService.hashSha256('admin123'),
      pinHash: SecurityService.hashPin('1234'),
    ),
  ];

  final List<CampModel> camps = [];
  final List<DeviceModel> devices = [];
}

class FakeAuthRepo implements IAuthRepository {
  final MockDataStore store;
  UserModel? _current;

  FakeAuthRepo(this.store);

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
}

class FakeDeviceRepo implements IDeviceSecurityRepository {
  final MockDataStore store;

  FakeDeviceRepo(this.store);

  @override
  Future<List<DeviceModel>> getAllDevices() async => store.devices;

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
  late MockDataStore store;
  late FakeAuthRepo authRepo;
  late FakeDeviceRepo deviceRepo;

  setUp(() {
    store = MockDataStore();
    authRepo = FakeAuthRepo(store);
    deviceRepo = FakeDeviceRepo(store);
  });

  group('New Device Activation, Admin Approval, and Custom Staff Login Flow', () {
    testWidgets('Complete Real-World Workflow: Custom Staff Assignment -> Device Registration -> Admin Approval -> Login',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // -------------------------------------------------------------
      // Step 1: Admin Creates Custom Staff (Anita Tamang)
      // -------------------------------------------------------------
      final anitaUser = UserModel(
        id: 'usr-anita-99',
        name: 'Anita Tamang (Outreach Nurse)',
        email: 'anita.tamang@gynocamp.org',
        phone: '9841999888',
        role: UserRole.dataTaker,
        isActive: true,
        tenantId: 'tenant-01',
        tenantName: 'Nepal Health Outreach Network',
        passwordHash: SecurityService.hashSha256('anitaPass123'),
        pinHash: SecurityService.hashPin('7788'),
      );
      await authRepo.createUser(
        user: anitaUser,
        adminUserId: 'usr-superadmin-01',
        deviceId: 'dev-admin-workstation',
      );

      expect(store.users.length, 2);
      expect(store.users.any((u) => u.email == 'anita.tamang@gynocamp.org'), isTrue);

      // -------------------------------------------------------------
      // Step 2: Anita opens a brand new device & Requests Activation
      // -------------------------------------------------------------
      final deviceVm = DeviceSecurityViewModel(deviceRepo);
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            deviceSecurityProvider.overrideWith((ref) => deviceVm),
          ],
          child: const MaterialApp(home: DeviceActivationView()),
        ),
      );
      await tester.pumpAndSettle();

      // Find step 1 fields
      expect(find.text('Step 1: Request Device Activation'), findsOneWidget);
      final nicknameField = find.widgetWithText(TextField, 'Device Nickname / Label');
      final staffField = find.widgetWithText(TextField, 'Requesting Field Staff Name');

      await tester.enterText(nicknameField, 'Pokhara Outreach Tablet #1');
      await tester.enterText(staffField, 'Anita Tamang');
      await tester.tap(find.text('Send Activation OTP Request'));
      await tester.pumpAndSettle();

      // Step 2: Verify OTP
      expect(find.text('Step 2: Enter 6-Digit Verification Code'), findsOneWidget);
      expect(find.text('654321'), findsOneWidget); // Verification code displayed

      // Enter OTP
      final otpField = find.widgetWithText(TextField, '6-Digit Verification Code');
      await tester.enterText(otpField, '654321');
      await tester.tap(find.text('Verify Code'));
      await tester.pumpAndSettle();

      // Step 3: Now device is Awaiting Super Admin Approval
      expect(find.text('Awaiting Central Administrator Approval'), findsOneWidget);
      expect(store.devices.length, 1);
      expect(store.devices.first.status, DeviceActivationStatus.pendingApproval);

      // -------------------------------------------------------------
      // Step 3: Super Admin Approves the Device from DeviceManagementView
      // -------------------------------------------------------------
      final devMgmtVm = DeviceManagementViewModel(deviceRepo);
      await devMgmtVm.loadDevices();
      authRepo.setCurrentUser(store.users.first); // Admin logged in

      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            deviceManagementProvider.overrideWith((ref) => devMgmtVm),
            authStateProvider.overrideWith((ref) => AuthViewModel(authRepo)),
            deviceSecurityRepositoryProvider.overrideWithValue(deviceRepo),
          ],
          child: const MaterialApp(home: DeviceManagementView()),
        ),
      );
      await tester.pumpAndSettle();

      // Super Admin sees the pending device
      expect(find.text('Pokhara Outreach Tablet #1'), findsOneWidget);
      expect(find.text('Approve Device'), findsOneWidget);

      // Super Admin clicks Approve Device
      await tester.tap(find.text('Approve Device'));
      await tester.pumpAndSettle();

      // Dialog pops up -> Admin confirms "Approve & Whitelist"
      expect(find.text('Authorize Field Device?'), findsOneWidget);
      await tester.tap(find.text('Approve & Whitelist'));
      await tester.pumpAndSettle();

      // Device is approved in the database
      expect(store.devices.first.status, DeviceActivationStatus.approved);

      // -------------------------------------------------------------
      // Step 4: Anita Logs in on the Approved Device
      // -------------------------------------------------------------
      final authVm = AuthViewModel(authRepo);
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            authStateProvider.overrideWith((ref) => authVm),
            deviceSecurityProvider.overrideWith((ref) => DeviceSecurityViewModel(deviceRepo)),
          ],
          child: const MaterialApp(home: LoginView()),
        ),
      );
      await tester.pumpAndSettle();

      // Anita enters custom email and custom password
      final emailInput = find.byType(TextField).at(0);
      final passInput = find.byType(TextField).at(1);

      await tester.enterText(emailInput, 'anita.tamang@gynocamp.org');
      await tester.enterText(passInput, 'anitaPass123');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In to GynoCamp'));
      await tester.pumpAndSettle();

      // Successfully authenticated as Anita!
      expect(authRepo.currentUser?.email, 'anita.tamang@gynocamp.org');
      expect(authRepo.currentUser?.role, UserRole.dataTaker);

      // -------------------------------------------------------------
      // Step 5: Verify HomeGatewayView shows Data Taker Console (No role bleed)
      // -------------------------------------------------------------
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            authStateProvider.overrideWith((ref) => AuthViewModel(authRepo)),
            deviceSecurityProvider.overrideWith((ref) => DeviceSecurityViewModel(deviceRepo)),
          ],
          child: const MaterialApp(home: HomeGatewayView()),
        ),
      );
      await tester.pumpAndSettle();

      // Confirms Data Taker elements are visible
      expect(find.text('Clinical Stations (Field Workstation Workflow)'), findsOneWidget);
      expect(find.text('Register Patient (दर्ता)'), findsOneWidget);
      expect(find.text('Scan Yellow Form (स्क्यान)'), findsOneWidget);
      expect(find.text('Patient Roll'), findsWidgets);

      // Confirms Super Admin actions are NOT present (No role bleed)
      expect(find.text('Staff Assignments'), findsNothing);
      expect(find.text('Authorize Camp Hardware'), findsNothing);
      expect(find.text('Clinical Protocols'), findsNothing);
    });
  });
}
