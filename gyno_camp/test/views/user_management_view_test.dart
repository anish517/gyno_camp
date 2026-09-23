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
  Future<void> deleteUser({required String userId, required String adminUserId, required String deviceId}) async {
    users.removeWhere((u) => u.id == userId);
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

  @override
  Future<List<String>> getValidCampsForUser(List<String> assignedCampIds) async => assignedCampIds;
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

  testWidgets('Edit button opens Edit Profile modal, updates profile, and closes cleanly', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeRepo = FakeAuthRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Find all Edit buttons (one per user card)
    final editButtons = find.widgetWithText(OutlinedButton, 'Edit');
    expect(editButtons, findsNWidgets(3));

    // Tap the Edit button on Rita Sharma's card (index 1)
    await tester.tap(editButtons.at(1));
    await tester.pumpAndSettle();

    // Verify Edit Profile modal is visible
    expect(find.text('Edit Profile: Rita Sharma (Nurse)'), findsOneWidget);
    expect(find.text('Full Name / Staff Title *'), findsOneWidget);
    expect(find.text('Phone Number'), findsOneWidget);

    // Edit full name
    final nameField = find.widgetWithText(TextField, 'Rita Sharma (Nurse)');
    await tester.enterText(nameField, 'Rita Sharma (Senior Nurse)');
    await tester.pumpAndSettle();

    // Tap 'Save Changes'
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    // Dialog should be dismissed
    expect(find.text('Edit Profile: Rita Sharma (Nurse)'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);

    // Verify repo updated and updated name is visible
    expect(fakeRepo.users[1].name, 'Rita Sharma (Senior Nurse)');
    expect(find.text('Rita Sharma (Senior Nurse)'), findsOneWidget);
  });

  testWidgets('Security button opens Security dialog, updates password and PIN, and closes cleanly', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeRepo = FakeAuthRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Find all Security buttons
    final securityButtons = find.widgetWithText(OutlinedButton, 'Security');
    expect(securityButtons, findsNWidgets(3));

    // Tap Security button on Rita Sharma's card (index 1)
    await tester.tap(securityButtons.at(1));
    await tester.pumpAndSettle();

    // Verify Security modal is visible
    expect(find.text('Security & Credentials: Rita Sharma (Nurse)'), findsOneWidget);
    expect(find.text('New Master Password'), findsOneWidget);
    expect(find.text('New Station PIN'), findsOneWidget);

    // Enter new password and new PIN
    final passwordField = find.widgetWithText(TextField, 'Min 6 characters');
    final pinField = find.widgetWithText(TextField, 'Station PIN (4-6 digits)');

    await tester.enterText(passwordField, 'NewSecretPass123');
    await tester.enterText(pinField, '5678');
    await tester.pumpAndSettle();

    // Tap 'Update Credentials'
    await tester.tap(find.text('Update Credentials'));
    await tester.pumpAndSettle();

    // Dialog should be dismissed
    expect(find.text('Security & Credentials: Rita Sharma (Nurse)'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);

    // Verify credentials updated in repo
    expect(fakeRepo.users[1].passwordHash, isNotNull);
    expect(fakeRepo.users[1].pinHash, isNotNull);
  });

  testWidgets('Rapid double tap on Edit button does not open duplicate dialogs', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeRepo = FakeAuthRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    final editButtons = find.widgetWithText(OutlinedButton, 'Edit');

    // Rapidly tap the first Edit button twice without waiting for pumpAndSettle
    await tester.tap(editButtons.first);
    await tester.tap(editButtons.first, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Only one dialog should ever be opened
    expect(find.byType(AlertDialog), findsOneWidget);

    // Cancel should close it completely
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('UserManagementView renders staff cards cleanly on mobile viewport without layout errors', (tester) async {
    tester.view.physicalSize = const Size(380, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeRepo = FakeAuthRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Verify view renders cards and actions on mobile
    expect(find.text('Rita Sharma (Nurse)'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Edit'), findsNWidgets(3));
    expect(find.widgetWithText(OutlinedButton, 'Security'), findsNWidgets(3));
    expect(find.widgetWithText(OutlinedButton, 'Assign Camps'), findsNWidgets(3));
  });

  testWidgets('Delete Staff permanently removes staff member from directory', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeRepo = FakeAuthRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Verify Rita Sharma exists
    expect(find.text('Rita Sharma (Nurse)'), findsOneWidget);

    // Open popup menu on Rita's card (index 0 among non-root users)
    final popupButtons = find.byType(PopupMenuButton<String>);
    expect(popupButtons, findsWidgets);
    await tester.tap(popupButtons.first);
    await tester.pumpAndSettle();

    // Tap 'Delete Staff...'
    expect(find.text('Delete Staff...'), findsOneWidget);
    await tester.tap(find.text('Delete Staff...'));
    await tester.pumpAndSettle();

    // Verify confirmation dialog
    expect(find.text('Delete Staff Member'), findsOneWidget);
    expect(find.text('Delete Permanently'), findsOneWidget);

    // Tap 'Delete Permanently'
    await tester.tap(find.text('Delete Permanently'));
    await tester.pumpAndSettle();

    // Verify user is deleted from repo and removed from list
    expect(fakeRepo.users.any((u) => u.id == 'usr-nurse-01'), isFalse);
    expect(find.text('Rita Sharma (Nurse)'), findsNothing);
  });
}
