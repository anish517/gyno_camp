import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/models/lookup_item_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/lookup_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('LookupRepository SQLite Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late LookupRepository lookupRepo;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      lookupRepo = LookupRepository(
        databaseService: dbService,
        auditRepository: auditRepo,
      );
    });

    tearDown(() async {
      await testDb.close();
    });

    test('getAllItems and getItemsByCategory fetch seeded default items', () async {
      final all = await lookupRepo.getAllItems();
      expect(all.isNotEmpty, isTrue);

      final diags = await lookupRepo.getItemsByCategory('diagnosis');
      expect(diags.length, greaterThanOrEqualTo(21));

      final meds = await lookupRepo.getItemsByCategory('medicine');
      expect(meds.length, greaterThanOrEqualTo(10));
    });

    test('addItem creates a new custom item and records an audit log', () async {
      final newItem = const LookupItemModel(
        id: 'diag-custom-pcos',
        category: 'diagnosis',
        code: 'pcos',
        labelEn: 'Polycystic Ovary Syndrome',
        labelNe: 'पीसीओएस',
        isActive: true,
        sortOrder: 99,
      );

      final added = await lookupRepo.addItem(
        newItem,
        userId: 'admin-01',
        userName: 'Super Admin',
        deviceId: 'dev-admin-01',
      );

      expect(added.labelEn, 'Polycystic Ovary Syndrome');

      final diags = await lookupRepo.getItemsByCategory('diagnosis');
      expect(diags.any((d) => d.code == 'pcos'), isTrue);

      final logs = await auditRepo.getRecentLogs();
      expect(logs.isNotEmpty, isTrue);
      expect(logs.any((l) => l.action == 'LOOKUP_ITEM_ADDED'), isTrue);
    });

    test('toggleItemStatus toggles active state and activeOnly filter works', () async {
      final diags = await lookupRepo.getItemsByCategory('diagnosis');
      final first = diags.first;

      // Deactivate first item
      final success = await lookupRepo.toggleItemStatus(
        first.id,
        false,
        userId: 'admin-01',
        userName: 'Super Admin',
        deviceId: 'dev-admin-01',
      );
      expect(success, isTrue);

      final activeOnly = await lookupRepo.getItemsByCategory('diagnosis', activeOnly: true);
      expect(activeOnly.any((d) => d.id == first.id), isFalse);

      final allDiags = await lookupRepo.getItemsByCategory('diagnosis', activeOnly: false);
      expect(allDiags.any((d) => d.id == first.id), isTrue);
    });

    test('updateItem updates labels in SQLite', () async {
      final diags = await lookupRepo.getItemsByCategory('diagnosis');
      final target = diags.first.copyWith(labelEn: 'Updated Bacterial Vaginosis');

      final updated = await lookupRepo.updateItem(
        target,
        userId: 'admin-01',
        userName: 'Super Admin',
        deviceId: 'dev-admin-01',
      );

      expect(updated.labelEn, 'Updated Bacterial Vaginosis');

      final refetched = await lookupRepo.getItemsByCategory('diagnosis');
      expect(refetched.any((d) => d.labelEn == 'Updated Bacterial Vaginosis'), isTrue);
    });

    test('deleteItem permanently removes an item', () async {
      final newItem = const LookupItemModel(
        id: 'to-delete',
        category: 'medicine',
        code: 'temp_med',
        labelEn: 'Temporary Med',
        labelNe: 'अस्थायी',
      );

      await lookupRepo.addItem(
        newItem,
        userId: 'admin-01',
        userName: 'Super Admin',
        deviceId: 'dev-admin-01',
      );

      final deleted = await lookupRepo.deleteItem(
        'to-delete',
        userId: 'admin-01',
        userName: 'Super Admin',
        deviceId: 'dev-admin-01',
      );
      expect(deleted, isTrue);

      final meds = await lookupRepo.getItemsByCategory('medicine');
      expect(meds.any((m) => m.id == 'to-delete'), isFalse);
    });
  });
}
