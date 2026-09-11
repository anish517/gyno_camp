import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../core/database/postgres_database_service.dart';
import '../core/services/central_api_service.dart';
import '../core/services/http_central_api_service.dart';
import '../models/audit_log_model.dart';
import '../models/clinical_visit_model.dart';
import '../models/patient_model.dart';
import '../models/sync_payload_model.dart';
import 'audit_repository.dart';

abstract class ISyncRepository {
  Future<Map<String, int>> getPendingCounts();
  Future<SyncPushResponse> pushDelta({required String deviceId, required String userId});
  Future<SyncPullResponse> pullDelta({required String deviceId, required String userId});
  Future<SyncHistoryItem> executeFullSyncCycle({required String deviceId, required String userId});
  Future<List<SyncHistoryItem>> getSyncHistory();
  Future<DateTime?> getLastSyncedAt();
}

class SyncRepository implements ISyncRepository {
  final DatabaseService _databaseService;
  final ICentralApiService _centralApiService;
  final AuditRepository _auditRepository;
  final List<SyncHistoryItem> _history = [];
  final Uuid _uuid = const Uuid();

  SyncRepository({
    DatabaseService? databaseService,
    ICentralApiService? centralApiService,
    AuditRepository? auditRepository,
  })  : _databaseService = databaseService ?? DatabaseService(),
        _centralApiService = centralApiService ?? HttpCentralApiService(),
        _auditRepository = auditRepository ?? AuditRepository();

  @override
  Future<Map<String, int>> getPendingCounts() async {
    final db = await _databaseService.database;

    final patientCount = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM ${DatabaseTables.tablePatients} WHERE is_synced = 0',
        )) ??
        0;

    final visitCount = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM ${DatabaseTables.tableClinicalVisits} WHERE is_synced = 0',
        )) ??
        0;

    return {
      'patients': patientCount,
      'visits': visitCount,
      'total': patientCount + visitCount,
    };
  }

  @override
  Future<SyncPushResponse> pushDelta({required String deviceId, required String userId}) async {
    final db = await _databaseService.database;

    // 1. Fetch unsynced patients
    final patientRows = await db.query(
      DatabaseTables.tablePatients,
      where: 'is_synced = ?',
      whereArgs: [0],
    );
    final patients = patientRows.map((r) => PatientModel.fromMap(r)).toList();

    // 2. Fetch unsynced clinical visits
    final visitRows = await db.query(
      DatabaseTables.tableClinicalVisits,
      where: 'is_synced = ?',
      whereArgs: [0],
    );
    final visits = visitRows.map((r) => ClinicalVisitModel.fromMap(r)).toList();

    // 3. Fetch recent audit logs to archive to cloud
    final logRows = await db.query(
      DatabaseTables.tableAuditLogs,
      limit: 50,
      orderBy: 'timestamp DESC',
    );
    final logs = logRows.map((r) => AuditLogModel.fromMap(r)).toList();

    if (patients.isEmpty && visits.isEmpty) {
      return SyncPushResponse(
        success: true,
        serverTimestamp: DateTime.now(),
        message: 'No pending records to push. Local database fully synced.',
      );
    }

    final payload = SyncPushPayload(
      deviceId: deviceId,
      generatedAt: DateTime.now(),
      patients: patients,
      clinicalVisits: visits,
      auditLogs: logs,
    );

    // 4. Send delta to central server
    final response = await _centralApiService.pushDelta(payload);

    // Automatically sync to PostgreSQL central database
    try {
      await PostgresDatabaseService().syncSqliteToPostgres();
    } catch (_) {
      // Continues gracefully if PostgreSQL is not currently running or in mock tests
    }

    // 5. Update local SQLite records to synced
    if (response.success) {
      final syncIso = response.serverTimestamp.toIso8601String();
      await db.transaction((txn) async {
        for (final pId in response.syncedPatientIds) {
          await txn.rawUpdate(
            'UPDATE ${DatabaseTables.tablePatients} SET is_synced = 1, synced_at = ? WHERE id = ?',
            [syncIso, pId],
          );
        }

        for (final vId in response.syncedVisitIds) {
          await txn.rawUpdate(
            'UPDATE ${DatabaseTables.tableClinicalVisits} SET is_synced = 1 WHERE id = ?',
            [vId],
          );
        }
      });

      // 6. Audit log
      await _auditRepository.logActivity(
        userId: userId,
        userName: 'Sync Engine',
        userRole: AppConstants.roleDataTaker,
        action: AppConstants.auditActionSyncUpload,
        entityType: 'SyncPayload',
        entityId: deviceId,
        detailsJson: '{"patientsPushed":${response.syncedPatientIds.length},"visitsPushed":${response.syncedVisitIds.length}}',
        deviceId: deviceId,
      );
    }

    return response;
  }

  @override
  Future<SyncPullResponse> pullDelta({required String deviceId, required String userId}) async {
    final db = await _databaseService.database;

    final lastSynced = await getLastSyncedAt();
    final response = await _centralApiService.pullDelta(
      since: lastSynced,
      deviceId: deviceId,
    );

    if (response.success) {
      await db.transaction((txn) async {
        // Upsert camps
        for (final camp in response.camps) {
          await txn.insert(
            DatabaseTables.tableCamps,
            camp.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Upsert lookup items
        for (final item in response.lookupItems) {
          await txn.insert(
            DatabaseTables.tableLookupItems,
            item.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Upsert users
        for (final user in response.users) {
          await txn.insert(
            DatabaseTables.tableUsers,
            user.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

      await _auditRepository.logActivity(
        userId: userId,
        userName: 'Sync Engine',
        userRole: AppConstants.roleDataTaker,
        action: AppConstants.auditActionSyncDownload,
        entityType: 'SyncPull',
        entityId: deviceId,
        detailsJson: '{"campsPulled":${response.camps.length},"lookupItemsPulled":${response.lookupItems.length}}',
        deviceId: deviceId,
      );
    }

    return response;
  }

  @override
  Future<SyncHistoryItem> executeFullSyncCycle({
    required String deviceId,
    required String userId,
  }) async {
    final cycleStart = DateTime.now();
    try {
      // Step 1: Push local deltas
      final pushRes = await pushDelta(deviceId: deviceId, userId: userId);

      // Step 2: Auto-sync to PostgreSQL database
      int pgPatients = 0;
      int pgVisits = 0;
      try {
        final pgResult = await PostgresDatabaseService().syncSqliteToPostgres();
        if (pgResult.success) {
          pgPatients = pgResult.syncedPatients;
          pgVisits = pgResult.syncedVisits;
        }
      } catch (_) {
        // Continues gracefully if PostgreSQL is offline
      }

      // Step 3: Pull remote deltas
      final pullRes = await pullDelta(deviceId: deviceId, userId: userId);

      final totalPatients = pushRes.syncedPatientIds.isNotEmpty ? pushRes.syncedPatientIds.length : pgPatients;
      final totalVisits = pushRes.syncedVisitIds.isNotEmpty ? pushRes.syncedVisitIds.length : pgVisits;

      final historyItem = SyncHistoryItem(
        id: _uuid.v4(),
        timestamp: cycleStart,
        patientsPushed: totalPatients,
        visitsPushed: totalVisits,
        auditLogsPushed: pushRes.syncedAuditLogIds.length,
        campsPulled: pullRes.camps.length,
        isSuccess: true,
      );

      _history.insert(0, historyItem);
      return historyItem;
    } catch (e) {
      final failedItem = SyncHistoryItem(
        id: _uuid.v4(),
        timestamp: cycleStart,
        isSuccess: false,
        errorMessage: e.toString(),
      );
      _history.insert(0, failedItem);
      rethrow;
    }
  }

  @override
  Future<List<SyncHistoryItem>> getSyncHistory() async {
    return List.unmodifiable(_history);
  }

  @override
  Future<DateTime?> getLastSyncedAt() async {
    if (_history.isEmpty) return null;
    final successfulRuns = _history.where((h) => h.isSuccess).toList();
    if (successfulRuns.isEmpty) return null;
    return successfulRuns.first.timestamp;
  }
}
