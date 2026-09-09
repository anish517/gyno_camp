import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/camp_repository.dart';
import 'package:gyno_camp/repositories/auth_repository.dart';
import 'package:gyno_camp/viewmodels/auth_viewmodel.dart';
import 'package:gyno_camp/viewmodels/camp_viewmodel.dart';
import 'package:gyno_camp/views/dashboard/home_gateway_view.dart';

class FakeCampRepoForHome implements ICampRepository {
  List<CampModel> testCamps = [
    CampModel(
      id: 'camp-1',
      campCode: 'KTM01',
      name: 'Outreach Gyno Health Camp',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha',
      ward: '03',
      venue: 'Primary Health Care Center',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 5),
      status: CampStatus.open,
      assignedStaffIds: const ['u1', 'u2'],
      createdAt: DateTime.now(),
      totalPatientsRegistered: 42,
    ),
    CampModel(
      id: 'camp-2',
      campCode: 'PKR02',
      name: 'Pokhara Women Care Camp',
      district: 'Kaski',
      municipality: 'Pokhara',
      ward: '08',
      venue: 'District Hospital',
      startDate: DateTime(2026, 9, 20),
      endDate: DateTime(2026, 9, 24),
      status: CampStatus.scheduled,
      assignedStaffIds: const ['u1'],
      createdAt: DateTime.now(),
      totalPatientsRegistered: 0,
    ),
  ];

  @override
  Future<List<CampModel>> getAllCamps() async => testCamps;

  @override
  Future<CampModel?> getActiveCamp() async =>
      testCamps.firstWhere((c) => c.status == CampStatus.open, orElse: () => testCamps.first);

  @override
  Future<CampModel?> getCampById(String id) async =>
      testCamps.firstWhere((c) => c.id == id, orElse: () => testCamps.first);

  @override
  Future<CampModel> createCamp(CampModel camp, {required String createdByUserId, required String deviceId}) async {
    testCamps.add(camp);
    return camp;
  }

  @override
  Future<CampModel> updateCamp(CampModel camp, {required String adminUserId, required String deviceId}) async {
    final idx = testCamps.indexWhere((c) => c.id == camp.id);
    if (idx != -1) {
      testCamps[idx] = camp;
    }
    return camp;
  }

  @override
  Future<bool> deleteCamp(String campId, {required String adminUserId, required String deviceId}) async {
    testCamps.removeWhere((c) => c.id == campId);
    return true;
  }

  @override
  Future<bool> archiveCamp(String campId, {required String adminUserId, required String deviceId}) async => true;

  @override
  Future<bool> assignStaff(String campId, List<String> staffIds, {required String adminUserId, required String deviceId}) async => true;

  @override
  Future<bool> openCamp(String campId, {required String adminUserId, required String deviceId}) async {
    for (int i = 0; i < testCamps.length; i++) {
      if (testCamps[i].id == campId) {
        testCamps[i] = testCamps[i].copyWith(status: CampStatus.open);
      } else if (testCamps[i].status == CampStatus.open) {
        testCamps[i] = testCamps[i].copyWith(status: CampStatus.closed);
      }
    }
    return true;
  }

  @override
  Future<bool> closeCamp(String campId, {required String adminUserId, required String deviceId}) async => true;
}

void main() {
  final testAdmin = UserModel(
    id: 'u-admin-1',
    name: 'Dr. Aarav Sharma',
    email: 'admin@gynocamp.org',
    phone: '9841000000',
    role: UserRole.superAdmin,
    tenantId: 'tenant_bir',
    tenantName: 'Kathmandu Outreach Center',
    isActive: true,
  );

  Widget createTestWidget() {
    final fakeRepo = FakeCampRepoForHome();
    return ProviderScope(
      overrides: [
        campRepositoryProvider.overrideWithValue(fakeRepo),
        authStateProvider.overrideWith((ref) {
          final vm = AuthViewModel(FakeAuthRepositorySimple(testAdmin));
          return vm;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const HomeGatewayView(),
      ),
    );
  }

  group('HomeGatewayView Super Admin Dashboard Widget Tests', () {
    testWidgets('renders Executive Command Header with user identity and live pulse', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('SECURE ROOT SESSION ACTIVE'), findsOneWidget);
      expect(find.text('Dr. Aarav Sharma'), findsWidgets);
      expect(find.text('Super Admin Command Console • Field Operations & Clinical Governance'), findsOneWidget);
      expect(find.text('New Camp'), findsOneWidget);
      expect(find.text('Switch Camp'), findsWidgets);
    });

    testWidgets('renders 4 Telemetry Metric cards and Active Camp Spotlight', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Camp Operations'), findsOneWidget);
      expect(find.text('Hardware Security'), findsOneWidget);
      expect(find.text('Intake Throughput'), findsOneWidget);
      expect(find.text('Cryptographic Ledger'), findsOneWidget);
      expect(find.text('SHA-256 Verified'), findsOneWidget);

      // Active Camp Spotlight
      expect(find.text('KTM01'), findsWidgets);
      expect(find.text('LIVE OPERATIONAL STATION'), findsOneWidget);
      expect(find.text('Outreach Gyno Health Camp'), findsWidgets);
      expect(find.text('Register Patient'), findsWidgets);
      expect(find.text('Scan Yellow Form'), findsWidgets);
      expect(find.text('Patient Roll & Charts'), findsWidgets);
    });

    testWidgets('renders 6 Administrative Module Cards', (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Camp Lifecycle & Interactive Calendar'), findsOneWidget);
      expect(find.text('Field Hardware Whitelist & Terminal Security'), findsOneWidget);
      expect(find.text('Staff & Personnel Directory (RBAC)'), findsOneWidget);
      expect(find.text('Clinical Master Data & Formulary'), findsOneWidget);
      expect(find.text('Executive Reports & Cohort Analytics'), findsOneWidget);
      expect(find.text('Tamper-Evident System Audit Ledger'), findsOneWidget);
    });

    testWidgets('renders Disaster Recovery dock and opening Quick Camp Switcher modal', (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Disaster Recovery & Data Export Operations'), findsOneWidget);
      expect(find.text('Export Audit Log'), findsOneWidget);
      expect(find.text('Database Backup'), findsOneWidget);

      // Tap Switch Camp button in header
      final switchBtn = find.widgetWithText(OutlinedButton, 'Switch Camp').first;
      await tester.tap(switchBtn);
      await tester.pumpAndSettle();

      expect(find.text('Switch Active Field Camp'), findsOneWidget);
      expect(find.text('PKR02'), findsOneWidget);
      expect(find.text('Set Active'), findsOneWidget);
    });
  });
}

class FakeAuthRepositorySimple implements IAuthRepository {
  final UserModel admin;
  FakeAuthRepositorySimple(this.admin);

  @override
  UserModel? get currentUser => admin;

  @override
  Future<UserModel?> login({required String email, String? password, required String deviceId}) async => admin;

  @override
  Future<UserModel?> loginAsRole({required UserRole role, required String deviceId}) async => admin;

  @override
  Future<void> logout({required String deviceId}) async {}

  @override
  Future<UserModel?> getUserByEmail(String email) async => admin;

  @override
  Future<UserModel?> getUserById(String id) async => admin;

  @override
  Future<List<UserModel>> getAllUsers({bool includeInactive = false}) async => [admin];

  @override
  Future<UserModel> createUser({
    required UserModel user,
    required String adminUserId,
    required String deviceId,
  }) async => user;

  @override
  Future<UserModel> updateUser({
    required UserModel user,
    required String adminUserId,
    required String deviceId,
  }) async => user;
}
