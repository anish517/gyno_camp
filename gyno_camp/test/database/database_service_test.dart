import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/database/database_tables.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseService Tests', () {
    late Database testDb;
    late DatabaseService dbService;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('Initial database seeding creates standard 3 roles and active camp', () async {
      final users = await testDb.query(DatabaseTables.tableUsers);
      expect(users.length, greaterThanOrEqualTo(3));

      final roles = users.map((u) => u['role']).toList();
      expect(roles, contains('SUPER_ADMIN'));
      expect(roles, contains('DATA_TAKER'));
      expect(roles, contains('DATA_ANALYST'));

      final camps = await testDb.query(DatabaseTables.tableCamps);
      expect(camps.length, greaterThanOrEqualTo(1));
      expect(camps.first['status'], 'OPEN');
    });

    test('Initial database seeding inserts Yellow Form diagnoses and medicines', () async {
      final diagnoses = await testDb.query(
        DatabaseTables.tableLookupItems,
        where: 'category = ?',
        whereArgs: ['diagnosis'],
      );
      expect(diagnoses.length, 21); // Exactly 21 diagnoses from Yellow Form

      final medicines = await testDb.query(
        DatabaseTables.tableLookupItems,
        where: 'category = ?',
        whereArgs: ['medicine'],
      );
      expect(medicines.length, 10); // Exactly 10 medications from Yellow Form
    });

    test('Patient insertion and querying with duplicate criteria in SQLite', () async {
      await testDb.insert(
        DatabaseTables.tablePatients,
        {
          'id': 'pat-100',
          'patient_id': 'GC-KTM01-2026-00100',
          'camp_id': 'camp-ktm-01',
          'camp_code': 'KTM01',
          'intake_date': DateTime.now().toIso8601String(),
          'first_name': 'Maya',
          'surname': 'Magar',
          'age': 32,
          'spouse_or_father_name': 'Khem Magar',
          'mobile': '9849999999',
          'ward': '03',
          'consent_treatment': 1,
          'consent_store_medical_info': 1,
          'created_at': DateTime.now().toIso8601String(),
          'created_by_user_id': 'usr-datataker-01',
          'created_by_device_id': 'dev-001',
          'is_synced': 0,
        },
      );

      final result = await testDb.query(
        DatabaseTables.tablePatients,
        where: 'mobile = ?',
        whereArgs: ['9849999999'],
      );

      expect(result.length, 1);
      expect(result.first['first_name'], 'Maya');
      expect(result.first['patient_id'], 'GC-KTM01-2026-00100');
    });
  });
}
