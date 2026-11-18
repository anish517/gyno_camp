import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/constants/app_constants.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/database/database_tables.dart';
import 'package:gyno_camp/core/services/http_central_api_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/sync_payload_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/camp_repository.dart';
import 'package:gyno_camp/repositories/sync_repository.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../bin/server.dart';

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
      campRepo = CampRepository(
        databaseService: dbService,
        auditRepository: auditRepo,
        enableCentralSync: false,
      );
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

    test('getAllCamps supports multiple concurrent open camps without unintended mutations', () async {
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

      // getAllCamps is read-only and maintains multiple open camps independently
      final camps = await campRepo.getAllCamps();
      final openCamps = camps.where((c) => c.status == CampStatus.open).toList();
      expect(openCamps.length, 3);

      final countAfter = Sqflite.firstIntValue(await testDb.rawQuery(
        "SELECT COUNT(*) FROM ${DatabaseTables.tableCamps} WHERE status = 'OPEN'",
      ));
      expect(countAfter, 3);
    });

    test(
      'deleted camp is never resurrected by sync push, POST /api/camps, GET /api/camps, or closeCamp/openCamp/assignStaff/createCamp',
      () async {
        final server = GynoCampSyncServer(
          pgHost: '127.0.0.1',
          pgPort: 5432,
          pgDatabase: 'test',
          pgUsername: 'test',
          pgPassword: '',
        );
        final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async => httpServer.close(force: true));
        httpServer.listen((request) async {
          await server.handleRequest(request);
        });

        final baseUrl = 'http://127.0.0.1:${httpServer.port}';
        final api = HttpCentralApiService(baseUrl: baseUrl);
        final syncRepo = SyncRepository(
          databaseService: dbService,
          centralApiService: api,
          auditRepository: auditRepo,
        );

        final camp123 = CampModel(
          id: 'camp-123',
          campCode: '123',
          name: '1st testing camp',
          district: 'Sunsari',
          municipality: 'Barahakshetra',
          ward: '01',
          venue: 'Chitwan Medical college',
          startDate: DateTime(2026, 11, 19),
          endDate: DateTime(2026, 12, 15),
          status: CampStatus.open,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );
        final campAaa = CampModel(
          id: 'camp-aaa',
          campCode: 'AA',
          name: 'aaa',
          district: 'Kathmandu',
          municipality: 'Budhanilkantha',
          ward: '01',
          venue: 'Health Post',
          startDate: DateTime(2026, 11, 2),
          endDate: DateTime(2026, 11, 4),
          status: CampStatus.open,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        // Seed both camps on the server
        await api.pushDelta(
          SyncPushPayload(
            deviceId: 'dev-seed',
            generatedAt: DateTime.now().toUtc(),
            camps: [camp123, campAaa],
          ),
        );

        // Delete camp-aaa on the server (DELETE /api/camps?id=camp-aaa)
        final delRes = await http.delete(Uri.parse('$baseUrl/api/camps?id=${campAaa.id}'));
        expect(delRes.statusCode, 200);

        // Stale client attempts to push camp-aaa back via /api/sync/push AND POST /api/camps
        await api.pushDelta(
          SyncPushPayload(
            deviceId: 'dev-stale',
            generatedAt: DateTime.now().toUtc(),
            camps: [campAaa],
          ),
        );
        final postDeletedRes = await http.post(
          Uri.parse('$baseUrl/api/camps'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(campAaa.toMap()),
        );
        expect(postDeletedRes.statusCode, 410);

        // GET /api/camps must NOT return camp-aaa
        final getCampsRes = await http.get(Uri.parse('$baseUrl/api/camps'));
        final fetchedCamps = (jsonDecode(getCampsRes.body) as List)
            .map((e) => (e as Map<String, dynamic>)['id'])
            .toList();
        expect(fetchedCamps, contains(camp123.id));
        expect(fetchedCamps, isNot(contains(campAaa.id)));

        // Even if camp-aaa existed locally before pullDelta, pullDelta deletes it AND persists
        // its ID into local deleted_camp_ids tombstone metadata.
        await testDb.insert(
          DatabaseTables.tableCamps,
          camp123.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await testDb.insert(
          DatabaseTables.tableCamps,
          campAaa.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await syncRepo.executeFullSyncCycle(deviceId: 'dev-web-01', userId: 'usr-superadmin-01');

        final persistedTombstones = await dbService.getDeletedCampIds(testDb);
        expect(persistedTombstones, contains(campAaa.id));

        // Now perform closeCamp, openCamp, assignStaff, unassign staff, and createCamp:
        // camp-aaa must NEVER reappear in getAllCamps().
        await campRepo.closeCamp(camp123.id, adminUserId: 'usr-superadmin-01', deviceId: 'dev-web-01');
        expect((await campRepo.getAllCamps()).map((c) => c.id), isNot(contains(campAaa.id)));

        await campRepo.openCamp(camp123.id, adminUserId: 'usr-superadmin-01', deviceId: 'dev-web-01');
        expect((await campRepo.getAllCamps()).map((c) => c.id), isNot(contains(campAaa.id)));

        await campRepo.assignStaff(
          camp123.id,
          ['usr-datataker-01'],
          adminUserId: 'usr-superadmin-01',
          deviceId: 'dev-web-01',
        );
        expect((await campRepo.getAllCamps()).map((c) => c.id), isNot(contains(campAaa.id)));

        await campRepo.assignStaff(
          camp123.id,
          const [],
          adminUserId: 'usr-superadmin-01',
          deviceId: 'dev-web-01',
        );
        expect((await campRepo.getAllCamps()).map((c) => c.id), isNot(contains(campAaa.id)));

        await campRepo.createCamp(
          camp123.copyWith(id: 'camp-new-99', campCode: '999', name: 'New Camp'),
          createdByUserId: 'usr-superadmin-01',
          deviceId: 'dev-web-01',
        );
        final finalIds = (await campRepo.getAllCamps()).map((c) => c.id).toSet();
        expect(finalIds, containsAll(['camp-123', 'camp-new-99']));
        expect(finalIds, isNot(contains(campAaa.id)));
      },
    );
  });
}
