import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/models/lookup_item_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/lookup_repository.dart';
import 'package:gyno_camp/viewmodels/master_lookup_viewmodel.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('MasterLookupViewModel Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late LookupRepository lookupRepo;
    late MasterLookupViewModel vm;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      lookupRepo = LookupRepository(
        databaseService: dbService,
        auditRepository: auditRepo,
      );
      vm = MasterLookupViewModel(lookupRepo);
      // Wait for initial load
      await Future.delayed(const Duration(milliseconds: 100));
    });

    tearDown(() async {
      await testDb.close();
    });

    test('initial state loads categories and populates active lists', () async {
      expect(vm.state.isLoading, isFalse);
      expect(vm.state.diagnoses.length, greaterThanOrEqualTo(21));
      expect(vm.state.medicines.length, greaterThanOrEqualTo(10));
      expect(vm.state.referralHospitals.length, greaterThanOrEqualTo(3));
      expect(vm.state.activeDiagnoses.length, greaterThanOrEqualTo(21));
    });

    test('setCategory updates selected category and clears query', () {
      vm.setSearchQuery('candid');
      vm.setCategory('medicine');
      expect(vm.state.selectedCategory, 'medicine');
      expect(vm.state.searchQuery, isEmpty);
    });

    test('searchQuery filters items across languages', () {
      vm.setSearchQuery('vagin');
      expect(vm.state.filteredDiagnoses.isNotEmpty, isTrue);
      expect(vm.state.filteredDiagnoses.any((d) => d.labelEn.toLowerCase().contains('vagin')), isTrue);

      vm.setSearchQuery('पाठेघर');
      expect(vm.state.filteredDiagnoses.isNotEmpty, isTrue);
    });

    test('addItem adds item and updates lists', () async {
      final item = const LookupItemModel(
        id: 'new-diag-1',
        category: 'diagnosis',
        code: 'endometriosis',
        labelEn: 'Endometriosis',
        labelNe: 'इन्डोमेट्रिओसिस',
      );

      final success = await vm.addItem(
        item,
        userId: 'admin-01',
        userName: 'Admin',
        deviceId: 'dev-01',
      );

      expect(success, isTrue);
      expect(vm.state.diagnoses.any((d) => d.code == 'endometriosis'), isTrue);
      expect(vm.state.successMessage, contains('Endometriosis'));
    });

    test('toggleItemStatus updates active status in state', () async {
      final first = vm.state.diagnoses.first;
      final success = await vm.toggleItemStatus(
        first.id,
        false,
        userId: 'admin-01',
        userName: 'Admin',
        deviceId: 'dev-01',
      );

      expect(success, isTrue);
      final updated = vm.state.diagnoses.firstWhere((d) => d.id == first.id);
      expect(updated.isActive, isFalse);
      expect(vm.state.activeDiagnoses.any((d) => d.id == first.id), isFalse);
    });

    test('deleteItem removes item from state', () async {
      final item = const LookupItemModel(
        id: 'item-del-test',
        category: 'medicine',
        code: 'temp',
        labelEn: 'Temp Med',
        labelNe: 'अस्थायी',
      );

      await vm.addItem(item, userId: 'adm', userName: 'Admin', deviceId: 'dev');
      expect(vm.state.medicines.any((m) => m.id == 'item-del-test'), isTrue);

      final deleted = await vm.deleteItem('item-del-test', userId: 'adm', userName: 'Admin', deviceId: 'dev');
      expect(deleted, isTrue);
      expect(vm.state.medicines.any((m) => m.id == 'item-del-test'), isFalse);
    });
  });
}
