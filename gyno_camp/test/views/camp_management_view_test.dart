import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/camp_repository.dart';
import 'package:gyno_camp/viewmodels/camp_viewmodel.dart';
import 'package:gyno_camp/views/admin/camp_management_view.dart';

class FakeCampRepository implements ICampRepository {
  List<CampModel> camps = [
    CampModel(
      id: 'c1',
      campCode: 'KTM01',
      name: 'Kathmandu Central Camp',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha',
      ward: '2',
      venue: 'Health Post',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 5),
      status: CampStatus.open,
      createdAt: DateTime.now(),
      totalPatientsRegistered: 45,
    ),
    CampModel(
      id: 'c2',
      campCode: 'DHN02',
      name: 'Dhading Rural Camp',
      district: 'Dhading',
      municipality: 'Nilkantha',
      ward: '4',
      venue: 'Primary Care Center',
      startDate: DateTime(2026, 9, 15),
      endDate: DateTime(2026, 9, 18),
      status: CampStatus.scheduled,
      createdAt: DateTime.now(),
      totalPatientsRegistered: 0,
    ),
  ];

  @override
  Future<List<CampModel>> getAllCamps() async => camps;

  @override
  Future<CampModel?> getActiveCamp() async {
    try {
      return camps.firstWhere((c) => c.status == CampStatus.open);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<CampModel?> getCampById(String id) async {
    try {
      return camps.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<CampModel> createCamp(CampModel camp, {required String createdByUserId, required String deviceId}) async {
    camps.add(camp);
    return camp;
  }

  @override
  Future<bool> openCamp(String campId, {required String adminUserId, required String deviceId}) async {
    for (int i = 0; i < camps.length; i++) {
      if (camps[i].id == campId) {
        camps[i] = camps[i].copyWith(status: CampStatus.open);
      } else if (camps[i].status == CampStatus.open) {
        camps[i] = camps[i].copyWith(status: CampStatus.closed);
      }
    }
    return true;
  }

  @override
  Future<bool> closeCamp(String campId, {required String adminUserId, required String deviceId}) async {
    final idx = camps.indexWhere((c) => c.id == campId);
    if (idx != -1) {
      camps[idx] = camps[idx].copyWith(status: CampStatus.closed);
      return true;
    }
    return false;
  }

  @override
  Future<bool> archiveCamp(String campId, {required String adminUserId, required String deviceId}) async {
    final idx = camps.indexWhere((c) => c.id == campId);
    if (idx != -1) {
      camps[idx] = camps[idx].copyWith(status: CampStatus.archived);
      return true;
    }
    return false;
  }

  @override
  Future<CampModel> updateCamp(CampModel camp, {required String adminUserId, required String deviceId}) async {
    final idx = camps.indexWhere((c) => c.id == camp.id);
    if (idx != -1) camps[idx] = camp;
    return camp;
  }

  @override
  Future<bool> deleteCamp(String campId, {required String adminUserId, required String deviceId}) async {
    camps.removeWhere((c) => c.id == campId);
    return true;
  }

  @override
  Future<bool> assignStaff(String campId, List<String> staffIds, {required String adminUserId, required String deviceId}) async {
    final idx = camps.indexWhere((c) => c.id == campId);
    if (idx != -1) {
      camps[idx] = camps[idx].copyWith(assignedStaffIds: staffIds);
      return true;
    }
    return false;
  }
}

void main() {
  Widget createTestWidget(ICampRepository repo) {
    const mockStaff = [
      UserModel(
        id: 'u1',
        name: 'Bikash Adhikari',
        email: 'bikash@example.com',
        phone: '9800000001',
        role: UserRole.dataTaker,
      ),
      UserModel(
        id: 'u2',
        name: 'Dr. Sita Sharma',
        email: 'sita@example.com',
        phone: '9800000002',
        role: UserRole.dataTaker,
      ),
    ];

    return ProviderScope(
      overrides: [
        campRepositoryProvider.overrideWithValue(repo),
        staffUsersProvider.overrideWith((ref) async => mockStaff),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const CampManagementView(),
      ),
    );
  }

  testWidgets('CampManagementView renders Camp Roster tab with camp cards', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeCampRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    expect(find.text('Camp Lifecycle & Calendar'), findsOneWidget);
    expect(find.text('Camp Roster'), findsOneWidget);
    expect(find.text('Interactive Calendar'), findsOneWidget);

    expect(find.text('Kathmandu Central Camp'), findsOneWidget);
    expect(find.text('Dhading Rural Camp'), findsOneWidget);
    expect(find.text('45 Intakes'), findsOneWidget);
  });

  testWidgets('CampManagementView switches to Interactive Calendar tab and toggles Nepali BS / Gregorian AD', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeCampRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Interactive Calendar'));
    await tester.pumpAndSettle();

    // Verify Bikram Sambat Nepali calendar is active by default with explanation banner
    expect(find.text('🇳🇵 Bikram Sambat (BS)'), findsOneWidget);
    expect(find.text('🌐 Gregorian (AD)'), findsOneWidget);
    expect(find.text('Why are calendar dates marked?'), findsOneWidget);

    // Switch to Gregorian (AD) mode
    await tester.tap(find.text('🌐 Gregorian (AD)'));
    await tester.pumpAndSettle();

    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Sun'), findsOneWidget);

    // Switch back to Bikram Sambat (BS) mode
    await tester.tap(find.text('🇳🇵 Bikram Sambat (BS)'));
    await tester.pumpAndSettle();

    expect(find.text('Why are calendar dates marked?'), findsOneWidget);
  });

  testWidgets('New Camp modal opens with bilingual date fields, empty staff selection by default, and status options', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeCampRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Tap New Camp button in AppBar
    await tester.tap(find.text('New Camp').first);
    await tester.pumpAndSettle();

    // Verify dialog header
    expect(find.text('Schedule Community Outreach Camp'), findsOneWidget);
    expect(find.text('नयाँ स्वास्थ्य शिविर तालिका र कर्मचारी परिचालन'), findsOneWidget);

    // Verify bilingual date labels
    expect(find.text('Start Date (सुरु मिति)'), findsOneWidget);
    expect(find.text('End Date (समापन मिति)'), findsOneWidget);

    // Verify staff assignment starts completely empty by default
    expect(find.text('0 selected'), findsOneWidget);
    expect(find.text('Select All'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);

    // Verify lifecycle status options
    expect(find.text('Scheduled'), findsWidgets);
    expect(find.text('Draft'), findsWidgets);

    // Cancel modal
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Draft tab displays rich contextual empty state with create shortcut when no draft camps exist', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeCampRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Tap Draft filter chip
    await tester.tap(find.text('Draft'));
    await tester.pumpAndSettle();

    expect(find.text('No Draft Camps'), findsOneWidget);
    expect(find.text('कुनै मस्यौदा शिविर फेला परेन'), findsOneWidget);
    expect(find.text('Create Draft Camp (नयाँ मस्यौदा)'), findsOneWidget);

    // Tap the shortcut button to verify it opens creation dialog
    await tester.tap(find.text('Create Draft Camp (नयाँ मस्यौदा)'));
    await tester.pumpAndSettle();

    expect(find.text('Schedule Community Outreach Camp'), findsOneWidget);

    // Cancel modal
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Archived tab displays rich contextual empty state with reset shortcut when no archived camps exist', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeCampRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Tap Archived filter chip
    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();

    expect(find.text('No Archived Camps'), findsOneWidget);
    expect(find.text('कुनै अभिलेखिकृत शिविर छैन'), findsOneWidget);
    expect(find.text('View All Active Camps'), findsOneWidget);

    // Tapping shortcut switches back to ALL
    await tester.tap(find.text('View All Active Camps'));
    await tester.pumpAndSettle();

    expect(find.text('Kathmandu Central Camp'), findsOneWidget);
  });

  testWidgets('Interactive Calendar tab date tap does not overflow RenderFlex on small mobile viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeCampRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Verify initial camp roster renders without overflow on mobile viewport
    expect(tester.takeException(), isNull);

    // Switch to Interactive Calendar
    await tester.tap(find.text('Interactive Calendar'));
    await tester.pumpAndSettle();

    // Scroll to calendar grid so day 15 is within viewport on small screen
    await tester.ensureVisible(find.text('15').first);
    await tester.pumpAndSettle();

    // Tap day 15 in the calendar grid
    await tester.tap(find.text('15').first);
    await tester.pumpAndSettle();

    // Scroll down to verify the schedule card without overflow
    await tester.ensureVisible(find.text('Schedule Camp').first);
    await tester.pumpAndSettle();

    // Verify that the empty/scheduled detail section renders without overflow
    expect(find.text('Schedule Camp'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
