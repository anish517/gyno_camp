import 'package:flutter/foundation.dart';
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
    final lastSynced = await getLastSyncedAt();

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

    // 3. Fetch modified camps since last sync (R2 & R4 fix: avoid pushing full camp table every cycle)
    final List<CampModel> camps;
    if (lastSynced != null) {
      final iso = lastSynced.toIso8601String();
      final campRows = await db.query(
        DatabaseTables.tableCamps,
        where: 'updated_at > ? OR created_at > ?',
        whereArgs: [iso, iso],
      );
      camps = campRows.map((r) => CampModel.fromMap(r)).toList();
    } else {
      final campRows = await db.query(DatabaseTables.tableCamps);
      camps = campRows.map((r) => CampModel.fromMap(r)).toList();
    }

    // 4. Fetch recent unsynced audit logs since last sync (R5 fix)
    final List<Map<String, dynamic>> logRows;
    if (lastSynced != null) {
      logRows = await db.query(
        DatabaseTables.tableAuditLogs,
        where: 'timestamp > ?',
        whereArgs: [lastSynced.toIso8601String()],
        limit: 50,
        orderBy: 'timestamp DESC',
      );
    } else {
      logRows = await db.query(
        DatabaseTables.tableAuditLogs,
        limit: 50,
        orderBy: 'timestamp DESC',
      );
    }
    final logs = logRows.map((r) => AuditLogModel.fromMap(r)).toList();

    if (patients.isEmpty && visits.isEmpty && camps.isEmpty && logs.isEmpty) {
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

    // 5. Send delta to central server (single path for all platforms)
    final response = await _centralApiService.pushDelta(payload);

    // 6. Update local SQLite records to synced
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

      // 7. Audit log
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
        // 1. Process entity deletions from central server
        for (final campId in response.deletedCampIds) {
          await txn.delete(
            DatabaseTables.tableCamps,
            where: 'id = ?',
            whereArgs: [campId],
          );
          await txn.delete(
            DatabaseTables.tablePatients,
            where: 'camp_id = ?',
            whereArgs: [campId],
          );
          await txn.delete(
            DatabaseTables.tableClinicalVisits,
            where: 'camp_id = ?',
            whereArgs: [campId],
          );
        }

        for (final lookupId in response.deletedLookupIds) {
          await txn.delete(
            DatabaseTables.tableLookupItems,
            where: 'id = ?',
            whereArgs: [lookupId],
          );
        }

        for (final userId in response.deletedUserIds) {
          await txn.delete(
            DatabaseTables.tableUsers,
            where: 'id = ?',
            whereArgs: [userId],
          );
        }

        // 2. Upsert camps
        for (final camp in response.camps) {
          await txn.insert(
            DatabaseTables.tableCamps,
            camp.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // 3. Upsert lookup items
        for (final item in response.lookupItems) {
          await txn.insert(
            DatabaseTables.tableLookupItems,
            item.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // 4. Upsert users with local credential preservation
        for (final user in response.users) {
          final existingRows = await txn.query(
            DatabaseTables.tableUsers,
            columns: ['password_hash', 'pin_hash'],
            where: 'id = ?',
            whereArgs: [user.id],
            limit: 1,
          );
          final userMap = user.toMap();
          if (existingRows.isNotEmpty) {
            final existing = existingRows.first;
            if ((userMap['password_hash'] == null || userMap['password_hash'].toString().isEmpty) &&
                existing['password_hash'] != null &&
                existing['password_hash'].toString().isNotEmpty) {
              userMap['password_hash'] = existing['password_hash'];
            }
            if ((userMap['pin_hash'] == null || userMap['pin_hash'].toString().isEmpty) &&
                existing['pin_hash'] != null &&
                existing['pin_hash'].toString().isNotEmpty) {
              userMap['pin_hash'] = existing['pin_hash'];
            }
          }
          await txn.insert(
            DatabaseTables.tableUsers,
            userMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        final pullSyncIso = DateTime.now().toIso8601String();

        // Upsert patients from central cloud (R1 fix: guard local unsynced edits)
        for (final patient in response.patients) {
          final unsyncedLocal = await txn.query(
            DatabaseTables.tablePatients,
            columns: ['id'],
            where: 'id = ? AND is_synced = 0',
            whereArgs: [patient.id],
            limit: 1,
          );
          if (unsyncedLocal.isNotEmpty) {
            // Local record has unsynced modifications: do not overwrite with remote copy
            continue;
          }

          final patientMap = patient.toMap();
          patientMap['is_synced'] = 1;
          patientMap['synced_at'] = pullSyncIso;
          await txn.insert(
            DatabaseTables.tablePatients,
            patientMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Upsert clinical visits from central cloud (R1 fix: guard local unsynced edits)
        for (final visit in response.clinicalVisits) {
          final unsyncedLocal = await txn.query(
            DatabaseTables.tableClinicalVisits,
            columns: ['id'],
            where: 'id = ? AND is_synced = 0',
            whereArgs: [visit.id],
            limit: 1,
          );
          if (unsyncedLocal.isNotEmpty) {
            // Local visit has unsynced modifications: do not overwrite with remote copy
            continue;
          }

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
      // Step 1: Pull remote deltas from central server first (R3 fix: pull before push)
      final pullRes = await pullDelta(deviceId: deviceId, userId: userId);

      // Step 2: Push local deltas to central server
      final pushRes = await pushDelta(deviceId: deviceId, userId: userId);

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
    } catch (e) { debugPrint('[SyncRepo] Metadata error: $e'); }
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
    } catch (e) { debugPrint('[SyncRepo] Metadata error: $e'); }
  }
}
