import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/database/database_tables.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/camp_repository.dart';
import 'package:gyno_camp/viewmodels/camp_viewmodel.dart';
import 'package:gyno_camp/views/admin/camp_management_view.dart';

class FakeCampRepository implements ICampRepository, IDefaultCampRosterRepository {
  DefaultCampRoster? _defaultRoster;
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
  Future<List<CampModel>> getAllCamps({String? tenantId}) async => camps;

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
  Future<DefaultCampRoster?> getDefaultCampRoster() async => _defaultRoster;

  @override
  Future<void> saveDefaultCampRoster(DefaultCampRoster roster) async {
    _defaultRoster = roster;
  }

  @override
  Future<CampModel> createCamp(CampModel camp, {required String createdByUserId, required String deviceId}) async {
    final saved = camp.id.isEmpty ? camp.copyWith(id: 'camp-${camps.length + 1}') : camp;
    camps.add(saved);
    final candidate = DefaultCampRoster.fromCamp(saved);
    if (_defaultRoster != null || candidate.hasAnyDefaults) {
      _defaultRoster = candidate;
    }
    return saved;
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
    if (idx != -1) {
      camps[idx] = camp;
    }
    if (!camp.status.isLocked) {
      final candidate = (_defaultRoster ?? DefaultCampRoster.fromCamp(camp)).copyWith(
        doctorNames: camp.doctorNames,
        showDoctorOnForms: camp.showDoctorOnForms,
        nurseNames: camp.nurseNames,
        showNurseOnForms: camp.showNurseOnForms,
        sourceCampId: camp.id,
        sourceCampCode: camp.campCode,
      );
      if (_defaultRoster != null || candidate.hasAnyDefaults) {
        _defaultRoster = candidate;
      }
    }
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
      final updated = camps[idx].copyWith(assignedStaffIds: staffIds);
      camps[idx] = updated;
      if (!updated.status.isLocked) {
        final candidate = (_defaultRoster ?? DefaultCampRoster.fromCamp(updated)).copyWith(
          assignedStaffIds: List<String>.from(staffIds),
          sourceCampId: updated.id,
          sourceCampCode: updated.campCode,
        );
        if (_defaultRoster != null || candidate.hasAnyDefaults) {
          _defaultRoster = candidate;
        }
      }
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
    expect(find.text('नयाँ स्वास्थ्य शिविर तालिका, स्थान र कर्मचारी परिचालन'), findsOneWidget);

    // Verify bilingual date labels
    expect(find.text('START DATE'), findsWidgets);
    expect(find.text('सुरु मिति'), findsWidgets);
    expect(find.text('END DATE'), findsWidgets);
    expect(find.text('समापन मिति'), findsWidgets);

    // Verify staff assignment starts completely empty by default
    expect(find.text('Optional (0 selected)'), findsOneWidget);
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
    await tester.tap(find.text('Interactive Calendar'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Scroll to calendar grid if day 15 is present
    final day15 = find.text('15');
    if (day15.evaluate().isNotEmpty) {
      await tester.ensureVisible(day15.first);
      await tester.pumpAndSettle();
      await tester.tap(day15.first, warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('New Camp modal hides Ward No., orders Geographic Location above Camp Identity, and auto-fills Official Camp Name from Palika, District, and Province while allowing manual edits', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeCampRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Camp').first);
    await tester.pumpAndSettle();

    // 1. Ward No. is hidden
    expect(find.text('Ward No.'), findsNothing);

    // 2. Geographic Location appears above Camp Identity
    final geoY = tester.getTopLeft(find.text('Geographic Location (नेपाल स्थान विवरण)')).dy;
    final idY = tester.getTopLeft(find.text('Camp Identity (शिविर पहिचान)')).dy;
    expect(geoY, lessThan(idY));

    // 3. Official Camp Name auto-populates from initial Palika, District, Province
    final nameFieldFinder = find.widgetWithText(TextField, 'Official Camp Name *');
    expect(nameFieldFinder, findsOneWidget);
    expect(tester.widget<TextField>(nameFieldFinder).controller?.text, 'Budhanilkantha, Kathmandu, Bagmati');

    // 4. Changing Province updates District, Palika, and Official Camp Name automatically
    await tester.tap(find.byKey(const ValueKey('create_prov_Bagmati')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gandaki').last);
    await tester.pumpAndSettle();

    final autoGandakiName = tester.widget<TextField>(nameFieldFinder).controller?.text ?? '';
    expect(autoGandakiName, endsWith(', Gandaki'));
    expect(autoGandakiName, isNot(equals('Budhanilkantha, Kathmandu, Bagmati')));

    // 5. Manual editing is preserved even when location changes, and can be saved with empty ward
    await tester.enterText(nameFieldFinder, 'Custom Gandaki Outreach Camp');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(nameFieldFinder).controller?.text, 'Custom Gandaki Outreach Camp');

    final codeFieldFinder = find.widgetWithText(TextField, 'Camp Code *');
    await tester.enterText(codeFieldFinder, 'GND99');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Schedule Camp'));
    await tester.pumpAndSettle();

    final savedCamp = fakeRepo.camps.firstWhere((c) => c.campCode == 'GND99');
    expect(savedCamp.name, 'Custom Gandaki Outreach Camp');
    expect(savedCamp.province, 'Gandaki');
    expect(savedCamp.ward, isEmpty);
    expect(savedCamp.showNurseOnForms, isFalse);
  });

  testWidgets('Attending Nurses & NNC toggle defaults to OFF (inputs hidden) and reveals inputs when toggled ON', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeCampRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Camp').first);
    await tester.pumpAndSettle();

    expect(find.text('Attending Nurses & NNC Numbers'), findsOneWidget);
    expect(find.text('Show in UI & Forms'), findsOneWidget);
    // Default OFF: Nurse Name and NNC No. fields are hidden
    expect(find.widgetWithText(TextField, 'Nurse Name'), findsNothing);
    expect(find.widgetWithText(TextField, 'NNC No. (optional)'), findsNothing);

    // Toggle Switch ON (2nd Switch in dialog; 1st is Examining Doctors)
    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(2));
    expect(tester.widget<Switch>(switches.at(1)).value, isFalse);

    await tester.tap(switches.at(1));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(switches.at(1)).value, isTrue);
    expect(find.widgetWithText(TextField, 'Nurse Name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'NNC No. (optional)'), findsOneWidget);
  });

  testWidgets('Default doctor and staff assignments carry over to every new camp until changed, preserving staff roles', (tester) async {
    tester.view.physicalSize = const Size(1280, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeCampRepository()..camps = [];
    const multiRoleStaff = [
      UserModel(
        id: 'u-dt',
        name: 'Bikash Adhikari',
        email: 'bikash@example.com',
        phone: '9800000001',
        role: UserRole.dataTaker,
      ),
      UserModel(
        id: 'u-coord',
        name: 'Mina Gurung',
        email: 'mina@example.com',
        phone: '9800000002',
        role: UserRole.staff,
        grantedRoles: {UserRole.staff, UserRole.dataAnalyst},
      ),
      UserModel(
        id: 'u-extra',
        name: 'Ramesh Thapa',
        email: 'ramesh@example.com',
        phone: '9800000003',
        role: UserRole.dataAnalyst,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          campRepositoryProvider.overrideWithValue(fakeRepo),
          staffUsersProvider.overrideWith((ref) async => multiRoleStaff),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const CampManagementView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Create First Camp (CAMP01): starts empty, assign Dr. Anita Sharma (NMC 14256) + Bikash & Mina
    await tester.tap(find.text('New Camp').first);
    await tester.pumpAndSettle();

    expect(find.text('Optional (0 selected)'), findsOneWidget);
    expect(find.text('Starts empty — select staff explicitly:'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Camp Code *'), 'CAMP01');
    await tester.enterText(find.widgetWithText(TextField, 'Doctor Name'), 'Anita Sharma');
    await tester.enterText(find.widgetWithText(TextField, 'NMC No.'), '14256');
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('Dr. Anita Sharma'), findsOneWidget);
    expect(find.text('NMC: 14256'), findsOneWidget);

    // Select Bikash (Data Taker) and Mina (Staff Coordinator, Data Analyst)
    final bikashRow = find.text('Bikash Adhikari');
    await tester.ensureVisible(bikashRow);
    await tester.tap(bikashRow);
    await tester.pumpAndSettle();
    final minaRow = find.text('Mina Gurung');
    await tester.ensureVisible(minaRow);
    await tester.tap(minaRow);
    await tester.pumpAndSettle();

    expect(find.text('2 Assigned'), findsOneWidget);

    await tester.tap(find.text('Schedule Camp'));
    await tester.pumpAndSettle();

    final camp1 = fakeRepo.camps.firstWhere((c) => c.campCode == 'CAMP01');
    expect(camp1.doctorNames, ['Dr. Anita Sharma (NMC: 14256)']);
    expect(camp1.assignedStaffIds, containsAll(['u-dt', 'u-coord']));
    expect(camp1.assignedStaffIds.length, 2);

    // 2. Open New Camp for Second Camp (CAMP02): Dr. Anita Sharma + Bikash & Mina (with roles) are pre-filled!
    await tester.tap(find.text('New Camp').first);
    await tester.pumpAndSettle();

    expect(find.text('Dr. Anita Sharma'), findsOneWidget);
    expect(find.text('NMC: 14256'), findsOneWidget);
    expect(find.text('2 Assigned'), findsOneWidget);
    expect(find.text('Default team pre-selected (same roles) — adjust anytime:'), findsOneWidget);
    expect(find.text('Reset Default'), findsOneWidget);
    // Role badges are preserved on the pre-selected staff rows
    expect(find.text('Data Taker'), findsOneWidget);
    expect(find.text('Staff Coordinator, Data Analyst'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Camp Code *'), 'CAMP02');
    await tester.tap(find.text('Schedule Camp'));
    await tester.pumpAndSettle();

    final camp2 = fakeRepo.camps.firstWhere((c) => c.campCode == 'CAMP02');
    expect(camp2.doctorNames, ['Dr. Anita Sharma (NMC: 14256)']);
    expect(camp2.assignedStaffIds, containsAll(['u-dt', 'u-coord']));
    expect(camp2.assignedStaffIds.length, 2);

    // 3. Change Doctor & Staff on Third Camp (CAMP03) -> updates sticky default for Fourth Camp (CAMP04)
    await tester.tap(find.text('New Camp').first);
    await tester.pumpAndSettle();

    // Remove Dr. Anita Sharma chip (close icon inside doctor chip) and add Dr. Ram Karki (NMC 55112)
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Dr. Anita Sharma'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Doctor Name'), 'Ram Karki');
    await tester.enterText(find.widgetWithText(TextField, 'NMC No.'), '55112');
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();

    // Clear default staff and select only Ramesh Thapa (Data Analyst)
    await tester.ensureVisible(find.text('Clear'));
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Optional (0 selected)'), findsOneWidget);

    await tester.ensureVisible(find.text('Ramesh Thapa'));
    await tester.tap(find.text('Ramesh Thapa'));
    await tester.pumpAndSettle();
    expect(find.text('1 Assigned'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Camp Code *'), 'CAMP03');
    await tester.tap(find.text('Schedule Camp'));
    await tester.pumpAndSettle();

    // 4. Open New Camp for Fourth Camp (CAMP04): now pre-fills Dr. Ram Karki (NMC 55112) + Ramesh Thapa (1 Assigned)!
    await tester.tap(find.text('New Camp').first);
    await tester.pumpAndSettle();

    expect(find.text('Dr. Anita Sharma'), findsNothing);
    expect(find.text('Dr. Ram Karki'), findsOneWidget);
    expect(find.text('NMC: 55112'), findsOneWidget);
    expect(find.text('1 Assigned'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  test('CampRepository SQLite integration persists default roster, syncs users.assigned_camp_ids on createCamp, and protects against closed-camp overwrites', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async => db.close());

    final dbService = DatabaseService();
    await dbService.initializeTestDb(db);
    final auditRepo = AuditRepository(databaseService: dbService);
    final campRepo = CampRepository(
      databaseService: dbService,
      auditRepository: auditRepo,
      enableCentralSync: false,
    );

    const staff1 = UserModel(
      id: 'usr-s1',
      name: 'Sita Nurse',
      email: 'sita@camp.org',
      phone: '9800000011',
      role: UserRole.dataTaker,
    );
    const staff2 = UserModel(
      id: 'usr-s2',
      name: 'Hari Coord',
      email: 'hari@camp.org',
      phone: '9800000022',
      role: UserRole.staff,
    );
    await db.insert(DatabaseTables.tableUsers, staff1.toMap());
    await db.insert(DatabaseTables.tableUsers, staff2.toMap());

    // Create Camp 1 with doctor + staff1
    final created1 = await campRepo.createCamp(
      CampModel(
        id: '',
        campCode: 'C001',
        name: 'First Camp',
        district: 'Kathmandu',
        municipality: 'Budhanilkantha',
        ward: '',
        venue: 'Health Post',
        startDate: DateTime(2026, 11, 25),
        endDate: DateTime(2026, 11, 27),
        status: CampStatus.scheduled,
        doctorName: 'Dr. Anita Sharma (NMC: 14256)',
        doctorNames: const ['Dr. Anita Sharma (NMC: 14256)'],
        assignedStaffIds: const ['usr-s1'],
        createdAt: DateTime.now(),
      ),
      createdByUserId: 'admin',
      deviceId: 'dev-1',
    );

    // Verify SQLite users.assigned_camp_ids immediately received created1.id
    final s1Row = (await db.query(DatabaseTables.tableUsers, where: 'id = ?', whereArgs: ['usr-s1'])).first;
    expect(UserModel.fromMap(s1Row).assignedCampIds, [created1.id]);

    // Verify default roster saved
    var def = await campRepo.getDefaultCampRoster();
    expect(def, isNotNull);
    expect(def!.doctorNames, ['Dr. Anita Sharma (NMC: 14256)']);
    expect(def.assignedStaffIds, ['usr-s1']);

    // Post-creation assignStaff adds usr-s2 -> updates default staff while preserving default doctor
    await campRepo.assignStaff(
      created1.id,
      ['usr-s1', 'usr-s2'],
      adminUserId: 'admin',
      deviceId: 'dev-1',
    );
    def = await campRepo.getDefaultCampRoster();
    expect(def!.doctorNames, ['Dr. Anita Sharma (NMC: 14256)']);
    expect(def.assignedStaffIds, ['usr-s1', 'usr-s2']);

    // Closing Camp 1 and editing it while CLOSED must NOT overwrite the active default roster
    await campRepo.closeCamp(created1.id, adminUserId: 'admin', deviceId: 'dev-1');
    final closedCamp1 = (await campRepo.getCampById(created1.id))!;
    await campRepo.updateCamp(
      closedCamp1.copyWith(
        doctorName: 'Dr. Historical Typo Fix',
        doctorNames: const ['Dr. Historical Typo Fix'],
      ),
      adminUserId: 'admin',
      deviceId: 'dev-1',
    );
    def = await campRepo.getDefaultCampRoster();
    expect(def!.doctorNames, ['Dr. Anita Sharma (NMC: 14256)']);
    expect(def.assignedStaffIds, ['usr-s1', 'usr-s2']);
  });
}
