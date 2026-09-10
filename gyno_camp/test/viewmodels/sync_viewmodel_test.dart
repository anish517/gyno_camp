import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/database/database_tables.dart';
import 'package:gyno_camp/core/services/central_api_service.dart';
import 'package:gyno_camp/core/services/network_connectivity_service.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/sync_repository.dart';
import 'package:gyno_camp/viewmodels/sync_viewmodel.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SyncViewModel Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late CentralApiService centralApi;
    late NetworkConnectivityService connectivityService;
    late SyncRepository syncRepo;
    late SyncViewModel viewModel;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      final auditRepo = AuditRepository(databaseService: dbService);
      centralApi = CentralApiService();
      connectivityService = NetworkConnectivityService(initialOnline: true);
      syncRepo = SyncRepository(
        databaseService: dbService,
        centralApiService: centralApi,
        auditRepository: auditRepo,
      );

      viewModel = SyncViewModel(
        syncRepository: syncRepo,
        connectivityService: connectivityService,
      );
    });

    tearDown(() async {
      viewModel.dispose();
      await testDb.close();
    });

    PatientModel buildTestPatient({
      required String id,
      required String patientId,
      required String firstName,
      required String surname,
      bool isSynced = false,
    }) {
      return PatientModel(
        id: id,
        patientId: patientId,
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        intakeDate: DateTime(2026, 3, 15),
        firstName: firstName,
        surname: surname,
        age: 30,
        ward: '03',
        maritalStatus: 'married',
        mobile: '9841000000',
        createdByUserId: 'usr-01',
        createdByDeviceId: 'dev-001',
        isSynced: isSynced,
        createdAt: DateTime.now(),
      );
    }

    test('initial state reflects connectivity and empty pending queues', () async {
      expect(viewModel.state.isOnline, isTrue);
      expect(viewModel.state.isSyncing, isFalse);
      expect(viewModel.state.pendingTotalCount, 0);
      expect(viewModel.state.hasPendingRecords, isFalse);
      expect(viewModel.state.isFullySynced, isTrue);
    });

    test('refreshPendingCounts detects newly saved offline records', () async {
      final p = buildTestPatient(
        id: 'pat-vm-01',
        patientId: 'GC-KTM01-2026-0010',
        firstName: 'Radhika',
        surname: 'Gurung',
      );
      await testDb.insert(DatabaseTables.tablePatients, p.toMap());

      await viewModel.refreshPendingCounts();

      expect(viewModel.state.pendingPatientsCount, 1);
      expect(viewModel.state.pendingTotalCount, 1);
      expect(viewModel.state.hasPendingRecords, isTrue);
      expect(viewModel.state.isFullySynced, isFalse);
    });

    test('syncNow fails immediately if device is offline', () async {
      viewModel.toggleConnectionSimulation(false);
      await Future.delayed(const Duration(milliseconds: 20));
      expect(viewModel.state.isOnline, isFalse);

      final success = await viewModel.syncNow(deviceId: 'dev-01', userId: 'usr-01');

      expect(success, isFalse);
      expect(viewModel.state.errorMessage, contains('offline mode'));
    });

    test('syncNow successfully executes cycle and updates state when online', () async {
      final p = buildTestPatient(
        id: 'pat-vm-02',
        patientId: 'GC-KTM01-2026-0011',
        firstName: 'Meena',
        surname: 'Khadka',
      );
      await testDb.insert(DatabaseTables.tablePatients, p.toMap());
      await viewModel.refreshPendingCounts();
      expect(viewModel.state.pendingTotalCount, 1);

      final success = await viewModel.syncNow(deviceId: 'dev-01', userId: 'usr-01');

      expect(success, isTrue);
      expect(viewModel.state.isSyncing, isFalse);
      expect(viewModel.state.pendingTotalCount, 0);
      expect(viewModel.state.isFullySynced, isTrue);
      expect(viewModel.state.lastSyncedAt, isNotNull);
      expect(viewModel.state.lastSuccessMessage, contains('1 records uploaded'));
      expect(viewModel.state.history.length, 1);
    });

    test('auto-sync triggers automatically upon network reconnection', () async {
      // 1. Start online, register pending patient
      final p = buildTestPatient(
        id: 'pat-vm-03',
        patientId: 'GC-KTM01-2026-0012',
        firstName: 'Sarita',
        surname: 'Magar',
      );
      await testDb.insert(DatabaseTables.tablePatients, p.toMap());

      // 2. Go offline
      viewModel.toggleConnectionSimulation(false);
      await Future.delayed(const Duration(milliseconds: 20));
      expect(viewModel.state.isOnline, isFalse);

      await viewModel.refreshPendingCounts();
      expect(viewModel.state.pendingTotalCount, 1);

      // 3. Reconnect to internet
      viewModel.toggleConnectionSimulation(true);
      await Future.delayed(const Duration(milliseconds: 20));
      expect(viewModel.state.isOnline, isTrue);

      // Wait for auto-sync listener to trigger and complete execution
      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsedMilliseconds < 2000 &&
          (viewModel.state.isSyncing || viewModel.state.pendingTotalCount > 0)) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(viewModel.state.pendingTotalCount, 0);
      expect(viewModel.state.isFullySynced, isTrue);
    });

    test('syncNow handles central server failures gracefully', () async {
      centralApi.simulateNetworkFailure = true;

      final success = await viewModel.syncNow(deviceId: 'dev-01', userId: 'usr-01');

      expect(success, isFalse);
      expect(viewModel.state.isSyncing, isFalse);
      expect(viewModel.state.errorMessage, contains('Sync failed'));
      expect(viewModel.state.history.first.isSuccess, isFalse);
    });
  });
}
