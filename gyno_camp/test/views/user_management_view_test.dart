import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/auth_repository.dart';
import 'package:gyno_camp/viewmodels/auth_viewmodel.dart';
import 'package:gyno_camp/views/admin/user_management_view.dart';

class FakeAuthRepository implements IAuthRepository {
  List<UserModel> users = [
    const UserModel(
      id: 'usr-admin-01',
      name: 'Dr. Aarav Admin',
      email: 'admin@gynocamp.org',
      phone: '9851000001',
      role: UserRole.superAdmin,
      isActive: true,
      tenantId: 'tenant_default',
      tenantName: 'Community Health Outreach',
      assignedCampIds: ['camp-ktm-01'],
    ),
    const UserModel(
      id: 'usr-nurse-01',
      name: 'Rita Sharma (Nurse)',
      email: 'rita@gynocamp.org',
      phone: '9841234567',
      role: UserRole.dataTaker,
      isActive: true,
      tenantId: 'tenant_default',
      tenantName: 'Community Health Outreach',
      assignedCampIds: ['camp-ktm-01'],
    ),
    const UserModel(
      id: 'usr-analyst-01',
      name: 'Bikash Analyst',
      email: 'analyst@gynocamp.org',
      phone: '9860123456',
      role: UserRole.dataAnalyst,
      isActive: true,
      tenantId: 'tenant_default',
      tenantName: 'Community Health Outreach',
      assignedCampIds: [],
    ),
  ];

  @override
  Future<List<UserModel>> getAllUsers({bool includeInactive = false}) async {
    return users.where((u) => includeInactive || u.isActive).toList();
  }

  @override
  Future<UserModel?> getUserById(String id) async {
    return users.where((u) => u.id == id).firstOrNull;
  }

  @override
  Future<UserModel?> getUserByEmail(String email) async {
    return users.where((u) => u.email == email).firstOrNull;
  }

  @override
  Future<UserModel> createUser({required UserModel user, required String adminUserId, required String deviceId}) async {
    users.add(user);
    return user;
  }

  @override
  Future<UserModel> updateUser({required UserModel user, required String adminUserId, required String deviceId}) async {
    final idx = users.indexWhere((u) => u.id == user.id);
    if (idx != -1) users[idx] = user;
    return user;
  }

  @override
  Future<UserModel?> login({required String email, String? password, required String deviceId}) async => users.first;

  @override
  Future<UserModel?> loginAsRole({required UserRole role, required String deviceId}) async => users.first;

  @override
  Future<void> logout({required String deviceId}) async {}

  @override
  UserModel? get currentUser => users.first;

  @override
  void setCurrentUser(UserModel? user) {}
}

void main() {
  Widget createTestWidget(IAuthRepository authRepo) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        allUsersProvider.overrideWith((ref) => authRepo.getAllUsers(includeInactive: true)),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const UserManagementView(),
      ),
    );
  }

  testWidgets('UserManagementView renders staff metric counters and list cards', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeRepo = FakeAuthRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    expect(find.text('Staff & Personnel Management'), findsOneWidget);
    expect(find.text('Total Personnel'), findsOneWidget);
    expect(find.text('Active Field Nurses'), findsOneWidget);
    expect(find.text('Super Admins'), findsNWidgets(2));

    expect(find.text('Dr. Aarav Admin'), findsOneWidget);
    expect(find.text('Rita Sharma (Nurse)'), findsOneWidget);
    expect(find.text('Bikash Analyst'), findsOneWidget);
  });

  testWidgets('UserManagementView filter chips filter personnel by role', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeRepo = FakeAuthRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Tap 'Data Takers' filter chip
    await tester.tap(find.text('Data Takers'));
    await tester.pumpAndSettle();

    expect(find.text('Rita Sharma (Nurse)'), findsOneWidget);
    expect(find.text('Dr. Aarav Admin'), findsNothing);
    expect(find.text('Bikash Analyst'), findsNothing);

    // Tap 'All Roles' filter chip
    await tester.tap(find.text('All Roles'));
    await tester.pumpAndSettle();

    expect(find.text('Rita Sharma (Nurse)'), findsOneWidget);
    expect(find.text('Dr. Aarav Admin'), findsOneWidget);
    expect(find.text('Bikash Analyst'), findsOneWidget);
  });

  testWidgets('Search input filters staff by name in real time', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeRepo = FakeAuthRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Bikash');
    await tester.pumpAndSettle();

    expect(find.text('Bikash Analyst'), findsOneWidget);
    expect(find.text('Rita Sharma (Nurse)'), findsNothing);
    expect(find.text('Dr. Aarav Admin'), findsNothing);
  });
}
