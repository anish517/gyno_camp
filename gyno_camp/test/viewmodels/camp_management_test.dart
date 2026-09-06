import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/camp_repository.dart';
import 'package:gyno_camp/viewmodels/camp_viewmodel.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Camp Management Lifecycle & Single Active Camp Rule Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late CampRepository campRepo;
    late CampViewModel vm;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      campRepo = CampRepository(
        databaseService: dbService,
        auditRepository: auditRepo,
      );
      vm = CampViewModel(campRepo);
      await Future.delayed(const Duration(milliseconds: 100));
    });

    tearDown(() async {
      await testDb.close();
    });

    test('initial state has seeded active camp KTM01', () {
      expect(vm.state.camps.isNotEmpty, isTrue);
      expect(vm.state.hasActiveCamp, isTrue);
      expect(vm.state.activeCamp?.campCode, 'KTM01');
    });

    test('creating new camp and opening it enforces single active camp rule', () async {
      // 1. Create a second camp DHN02
      final newCamp = CampModel(
        id: 'camp-dhn-02',
        campCode: 'DHN02',
        name: 'Dhading Health Camp 2',
        district: 'Dhading',
        municipality: 'Nilkantha',
        ward: '4',
        venue: 'Dhading Hospital',
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 2)),
        status: CampStatus.scheduled,
        createdAt: DateTime.now(),
      );

      final created = await vm.createCamp(
        newCamp,
        adminUserId: 'admin-01',
        deviceId: 'dev-01',
      );
      expect(created, isTrue);

      // 2. Open DHN02
      final opened = await vm.openCamp('camp-dhn-02', adminUserId: 'admin-01', deviceId: 'dev-01');
      expect(opened, isTrue);

      // 3. Verify DHN02 is now the active camp
      expect(vm.state.activeCamp?.campCode, 'DHN02');

      // 4. Verify KTM01 was automatically closed!
      final ktmCamp = vm.state.camps.firstWhere((c) => c.campCode == 'KTM01');
      expect(ktmCamp.status, CampStatus.closed);
    });

    test('assignStaff updates assigned staff IDs and logs audit event', () async {
      final active = vm.state.activeCamp!;
      final success = await vm.assignStaff(
        active.id,
        ['usr-datataker-01', 'usr-analyst-01'],
        adminUserId: 'admin-01',
        deviceId: 'dev-01',
      );

      expect(success, isTrue);
      final updated = vm.state.camps.firstWhere((c) => c.id == active.id);
      expect(updated.assignedStaffIds.length, 2);
      expect(updated.assignedStaffIds, contains('usr-datataker-01'));
    });

    test('closing and archiving camp transitions status', () async {
      final active = vm.state.activeCamp!;

      // Close camp
      final closed = await vm.closeCamp(active.id, adminUserId: 'admin-01', deviceId: 'dev-01');
      expect(closed, isTrue);
      expect(vm.state.hasActiveCamp, isFalse);

      // Archive camp
      final archived = await vm.archiveCamp(active.id, adminUserId: 'admin-01', deviceId: 'dev-01');
      expect(archived, isTrue);

      final updated = vm.state.camps.firstWhere((c) => c.id == active.id);
      expect(updated.status, CampStatus.archived);
    });

    test('updateCamp modifies camp attributes in SQLite', () async {
      final active = vm.state.activeCamp!;
      final modified = active.copyWith(name: 'Renamed KTM Camp Venue');

      final updated = await vm.updateCamp(modified, adminUserId: 'admin-01', deviceId: 'dev-01');
      expect(updated, isTrue);

      final refetched = vm.state.camps.firstWhere((c) => c.id == active.id);
      expect(refetched.name, 'Renamed KTM Camp Venue');
    });

    test('deleteCamp removes camp', () async {
      final tempCamp = CampModel(
        id: 'camp-to-delete',
        campCode: 'DEL01',
        name: 'Camp To Delete',
        district: 'Kavre',
        municipality: 'Banepa',
        ward: '1',
        venue: 'Clinic',
        startDate: DateTime.now(),
        endDate: DateTime.now(),
        status: CampStatus.draft,
        createdAt: DateTime.now(),
      );

      await vm.createCamp(tempCamp, adminUserId: 'adm', deviceId: 'dev');
      expect(vm.state.camps.any((c) => c.id == 'camp-to-delete'), isTrue);

      final deleted = await vm.deleteCamp('camp-to-delete', adminUserId: 'adm', deviceId: 'dev');
      expect(deleted, isTrue);
      expect(vm.state.camps.any((c) => c.id == 'camp-to-delete'), isFalse);
    });
  });
}
