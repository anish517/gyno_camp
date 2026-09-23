import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/security/security_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/device_model.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/auth_repository.dart';
import 'package:gyno_camp/repositories/camp_repository.dart';
import 'package:gyno_camp/repositories/device_security_repository.dart';
import 'package:gyno_camp/viewmodels/auth_viewmodel.dart';
import 'package:gyno_camp/viewmodels/camp_viewmodel.dart';
import 'package:gyno_camp/viewmodels/device_security_viewmodel.dart';
import 'package:gyno_camp/views/admin/user_management_view.dart';
import 'package:gyno_camp/views/auth/login_view.dart';
import 'package:gyno_camp/views/dashboard/home_gateway_view.dart';
import 'package:gyno_camp/views/splash/security_gateway_view.dart';

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
      passwordHash: SecurityService.hashSha256('Admin@123'),
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
      deviceId: 'dev-01',
      deviceName: deviceName,
      model: model,
      hardwareFingerprint: hardwareFingerprint,
      status: DeviceActivationStatus.approved,
      registeredByUserId: staffUserId,
      registeredByName: staffName,
      registeredAt: DateTime.now(),
      approvedAt: DateTime.now(),
    );
    store.devices.add(dev);
    return (device: dev, plainOtp: plainOtp);
  }

  @override
  Future<bool> verifyOtp({required String deviceId, required String enteredOtp}) async => true;

  @override
  Future<bool> approveDevice({required String deviceId, required String adminUserId}) async => true;

  @override
  Future<bool> revokeDevice({required String deviceId, required String adminUserId}) async => true;

  @override
  Future<bool> setAppLockPin({required String deviceId, required String pin}) async => true;

  @override
  Future<bool> verifyAppLockPin({required String deviceId, required String enteredPin}) async => true;
}

class FakeCampRepo implements ICampRepository {
  final List<CampModel> camps = [];

  @override
  Future<List<CampModel>> getAllCamps({String? tenantId}) async => camps;

  @override
  Future<CampModel?> getActiveCamp() async => null;

  @override
  Future<CampModel?> getCampById(String id) async => null;

  @override
  Future<CampModel> createCamp(CampModel camp, {required String createdByUserId, required String deviceId}) async => camp;

  @override
  Future<CampModel> updateCamp(CampModel camp, {required String adminUserId, required String deviceId}) async => camp;

  @override
  Future<bool> openCamp(String campId, {required String adminUserId, required String deviceId}) async => true;

  @override
  Future<bool> closeCamp(String campId, {required String adminUserId, required String deviceId}) async => true;

  @override
  Future<bool> archiveCamp(String campId, {required String adminUserId, required String deviceId}) async => true;

  @override
  Future<bool> assignStaff(String campId, List<String> staffIds, {required String adminUserId, required String deviceId}) async => true;

  @override
  Future<bool> deleteCamp(String campId, {required String adminUserId, required String deviceId}) async => true;
}

void main() {
  testWidgets('Test full flow: login -> tap staff directory -> back -> logout', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final store = MockDataStore();
    final approvedDevice = DeviceModel(
      deviceId: 'dev-admin-tablet',
      deviceName: 'Admin Workstation',
      model: 'Android Tablet',
      hardwareFingerprint: 'hw-admin-fingerprint',
      status: DeviceActivationStatus.approved,
      registeredByUserId: 'usr-superadmin-01',
      registeredByName: 'System Administrator (Super Admin)',
      registeredAt: DateTime.now(),
      approvedAt: DateTime.now(),
    );
    store.devices.add(approvedDevice);

    final authRepo = FakeAuthRepo(store);
    final campRepo = FakeCampRepo();
    final deviceRepo = FakeDeviceRepo(store);

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        campRepositoryProvider.overrideWithValue(campRepo),
        deviceSecurityRepositoryProvider.overrideWithValue(deviceRepo),
        allUsersProvider.overrideWith((ref) => authRepo.getAllUsers(includeInactive: true)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SecurityGatewayView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify LoginView is shown
    expect(find.byType(LoginView), findsOneWidget);

    // Enter login credentials
    await tester.enterText(find.byType(TextField).at(0), 'admin@gynocamp.org');
    await tester.enterText(find.byType(TextField).at(1), 'Admin@123');
    await tester.pumpAndSettle();

    // Click Sign In
    await tester.tap(find.text('Sign In to GynoCamp'));
    await tester.pumpAndSettle();

    // Verify HomeGatewayView is shown
    expect(find.byType(HomeGatewayView), findsOneWidget);

    // Look for Staff & Personnel Directory tile and tap it
    final staffCard = find.text('Staff & Personnel Directory (RBAC)');
    expect(staffCard, findsOneWidget);
    await tester.ensureVisible(staffCard);
    await tester.pumpAndSettle();
    await tester.tap(staffCard);
    await tester.pumpAndSettle();

    // Verify UserManagementView is shown
    expect(find.byType(UserManagementView), findsOneWidget);

    // Go back
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(HomeGatewayView), findsOneWidget);

    // Click Logout
    await tester.tap(find.byTooltip('Logout / Sign Out'));
    await tester.pumpAndSettle();

    // Confirm Logout
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign Out'));
    await tester.pumpAndSettle();

    // Verify we are back on LoginView
    expect(find.byType(LoginView), findsOneWidget);
    container.dispose();
  });
}
