import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/constants/app_constants.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/database/database_tables.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/camp_repository.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Camp Status Persistence & Single Active Camp Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late CampRepository campRepo;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      campRepo = CampRepository(databaseService: dbService, auditRepository: auditRepo);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('closeCamp changes status to CLOSED and persists across getAllCamps calls', () async {
      // 1. Initial seeded camp is open
      final initialActive = await campRepo.getActiveCamp();
      expect(initialActive, isNotNull);
      expect(initialActive!.status, CampStatus.open);

      // 2. Close the camp
      final closed = await campRepo.closeCamp(
        initialActive.id,
        adminUserId: 'usr-superadmin-01',
        deviceId: 'dev-test-01',
      );
      expect(closed, isTrue);

      // 3. Verify getActiveCamp returns null immediately
      final activeAfterClose = await campRepo.getActiveCamp();
      expect(activeAfterClose, isNull);

      // 4. Verify getAllCamps reflects CLOSED status and does NOT resurrect it
      final allCamps = await campRepo.getAllCamps();
      final closedCamp = allCamps.firstWhere((c) => c.id == initialActive.id);
      expect(closedCamp.status, CampStatus.closed);

      // 5. Querying directly from SQLite table confirms status is 'CLOSED'
      final rows = await testDb.query(
        DatabaseTables.tableCamps,
        where: 'id = ?',
        whereArgs: [initialActive.id],
      );
      expect(rows.first['status'], AppConstants.campStatusClosed);
    });

    test('getAllCamps enforces single active camp invariant when duplicate open camps exist', () async {
      // Manually insert two additional camps with status 'OPEN' in SQLite
      final now = DateTime.now();
      await testDb.insert(DatabaseTables.tableCamps, {
        'id': 'camp-dup-01',
        'camp_code': 'DUP01',
        'name': 'Duplicate Camp 1',
        'district': 'Kathmandu',
        'start_date': now.subtract(const Duration(days: 2)).toIso8601String(),
        'end_date': now.add(const Duration(days: 2)).toIso8601String(),
        'status': AppConstants.campStatusOpen,
        'created_at': now.toIso8601String(),
      });
      await testDb.insert(DatabaseTables.tableCamps, {
        'id': 'camp-dup-02',
        'camp_code': 'DUP02',
        'name': 'Duplicate Camp 2',
        'district': 'Lalitpur',
        'start_date': now.add(const Duration(days: 1)).toIso8601String(),
        'end_date': now.add(const Duration(days: 4)).toIso8601String(),
        'status': AppConstants.campStatusOpen,
        'created_at': now.toIso8601String(),
      });

      // Initially SQLite has 3 open camps
      final countBefore = Sqflite.firstIntValue(await testDb.rawQuery(
        "SELECT COUNT(*) FROM ${DatabaseTables.tableCamps} WHERE status = 'OPEN'",
      ));
      expect(countBefore, 3);

      // getAllCamps should automatically clean up duplicate open camps
      final camps = await campRepo.getAllCamps();
      final openCamps = camps.where((c) => c.status == CampStatus.open).toList();
      expect(openCamps.length, 1);

      // The most recent one (DUP02) remains open, older ones become closed
      expect(openCamps.first.id, 'camp-dup-02');

      final countAfter = Sqflite.firstIntValue(await testDb.rawQuery(
        "SELECT COUNT(*) FROM ${DatabaseTables.tableCamps} WHERE status = 'OPEN'",
      ));
      expect(countAfter, 1);
    });
  });
}
