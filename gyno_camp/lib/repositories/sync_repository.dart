import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../core/services/central_api_service.dart';
import '../core/services/http_central_api_service.dart';
import '../models/audit_log_model.dart';
import '../models/camp_model.dart';
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

    // 3. Fetch all camps to ensure central server is up to date
    final campRows = await db.query(DatabaseTables.tableCamps);
    final camps = campRows.map((r) => CampModel.fromMap(r)).toList();

    // 4. Fetch recent audit logs to archive to cloud
    final logRows = await db.query(
      DatabaseTables.tableAuditLogs,
      limit: 50,
      orderBy: 'timestamp DESC',
    );
    final logs = logRows.map((r) => AuditLogModel.fromMap(r)).toList();

    if (patients.isEmpty && visits.isEmpty && camps.isEmpty) {
      return SyncPushResponse(
        success: true,
        serverTimestamp: DateTime.now(),
        message: 'No pending records to push. Local database fully synced.',
      );
    }

    final payload = SyncPushPayload(
      deviceId: deviceId,
      generatedAt: DateTime.now(),
      camps: camps,
      patients: patients,
      clinicalVisits: visits,
      auditLogs: logs,
    );

    // 4. Send delta to central server (single path for all platforms)
    final response = await _centralApiService.pushDelta(payload);

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

        final pullSyncIso = DateTime.now().toIso8601String();

        // Upsert patients from central cloud (marked as synced to prevent echo-push loops)
        for (final patient in response.patients) {
          final patientMap = patient.toMap();
          patientMap['is_synced'] = 1;
          patientMap['synced_at'] = pullSyncIso;
          await txn.insert(
            DatabaseTables.tablePatients,
            patientMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Upsert clinical visits from central cloud (marked as synced to prevent echo-push loops)
        for (final visit in response.clinicalVisits) {
          final visitMap = visit.toMap();
          visitMap['is_synced'] = 1;
          await txn.insert(
            DatabaseTables.tableClinicalVisits,
            visitMap,
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

      // Step 2: Pull remote deltas from central server
      final pullRes = await pullDelta(deviceId: deviceId, userId: userId);

      final totalPatients = pushRes.syncedPatientIds.length;
      final totalVisits = pushRes.syncedVisitIds.length;

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
      await _persistLastSyncedAt(cycleStart);
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
    // First check in-memory history for this session
    final successfulRuns = _history.where((h) => h.isSuccess).toList();
    if (successfulRuns.isNotEmpty) return successfulRuns.first.timestamp;
    // Fall back to persisted value in SQLite (survives app restarts)
    try {
      final db = await _databaseService.database;
      final rows = await db.query(
        DatabaseTables.tableMetadata,
        where: 'key = ?',
        whereArgs: ['last_sync_at'],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final val = rows.first['value'] as String?;
        if (val != null) return DateTime.tryParse(val);
      }
    } catch (_) {}
    return null;
  }

  /// Persists the last successful sync timestamp to SQLite metadata.
  Future<void> _persistLastSyncedAt(DateTime timestamp) async {
    try {
      final db = await _databaseService.database;
      await db.insert(
        DatabaseTables.tableMetadata,
        {
          'key': 'last_sync_at',
          'value': timestamp.toIso8601String(),
          'updated_at': timestamp.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }
}
