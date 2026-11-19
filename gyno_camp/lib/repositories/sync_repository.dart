import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../core/services/central_api_service.dart';
import '../core/services/http_central_api_service.dart';
import '../core/services/session_service.dart';
import '../models/audit_log_model.dart';
import '../models/camp_model.dart';
import '../models/clinical_visit_model.dart';
import '../models/lookup_item_model.dart';
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

    int offlineScanCount = 0;
    try {
      offlineScanCount = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM ${DatabaseTables.tableOfflineScanQueue} WHERE status IN ('pending', 'failed')",
          )) ??
          0;
    } catch (_) {}

    int deletionCount = 0;
    try {
      deletionCount = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM ${DatabaseTables.tableDeletedEntitiesQueue}',
          )) ??
          0;
    } catch (_) {}

    return {
      'patients': patientCount,
      'visits': visitCount,
      'offline_scans': offlineScanCount,
      'deletions': deletionCount,
      'total': patientCount + visitCount + offlineScanCount + deletionCount,
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
    // Exclude any locally or remotely tombstoned camp IDs so deleted camps are never pushed back.
    final deletedCampIds = await _databaseService.getDeletedCampIds(db);
    final List<CampModel> camps;
    if (lastSynced != null) {
      final iso = lastSynced.toIso8601String();
      final campRows = await db.query(
        DatabaseTables.tableCamps,
        where: 'updated_at > ? OR created_at > ?',
        whereArgs: [iso, iso],
      );
      camps = campRows
          .map((r) => CampModel.fromMap(r))
          .where((c) => !deletedCampIds.contains(c.id))
          .toList();
    } else {
      final campRows = await db.query(DatabaseTables.tableCamps);
      camps = campRows
          .map((r) => CampModel.fromMap(r))
          .where((c) => !deletedCampIds.contains(c.id))
          .toList();
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

    // 5. Fetch unsynced lookup items (medicines, diagnoses, chief complaints, reasons for visit)
    final lookupRows = await db.query(
      DatabaseTables.tableLookupItems,
      where: 'is_synced = ?',
      whereArgs: [0],
    );
    final lookups = lookupRows.map((r) => LookupItemModel.fromMap(r)).toList();

    // 6. Fetch pending deleted patient & visit IDs from tombstone queue
    final deletedPatientIds = <String>[];
    final deletedVisitIds = <String>[];
    try {
      final delRows = await db.query(DatabaseTables.tableDeletedEntitiesQueue);
      for (final row in delRows) {
        final id = (row['entity_id']?.toString().isNotEmpty == true)
            ? row['entity_id']!.toString()
            : (row['id']?.toString() ?? '');
        final type = row['entity_type']?.toString() ?? '';
        if (id.isEmpty) continue;
        if (type == 'patient') {
          // Never push legacy Token-ID tombstones if an active patient uses that Token ID
          final activeMatch = await db.query(
            DatabaseTables.tablePatients,
            columns: ['id'],
            where: 'patient_id = ? COLLATE NOCASE',
            whereArgs: [id],
            limit: 1,
          );
          if (activeMatch.isEmpty && !id.toUpperCase().startsWith('GC-')) {
            deletedPatientIds.add(id);
          }
        }
        if (type == 'clinical_visit') deletedVisitIds.add(id);
      }
    } catch (_) {}

    if (patients.isEmpty &&
        visits.isEmpty &&
        camps.isEmpty &&
        logs.isEmpty &&
        lookups.isEmpty &&
        deletedPatientIds.isEmpty &&
        deletedVisitIds.isEmpty) {
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
      lookupItems: lookups,
      deletedPatientIds: deletedPatientIds,
      deletedVisitIds: deletedVisitIds,
    );

    // 7. Send delta to central server (single path for all platforms)
    final response = await _centralApiService.pushDelta(payload);

    // 8. Update local SQLite records to synced
    if (response.success) {
      final syncIso = response.serverTimestamp.toIso8601String();
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final pId in response.syncedPatientIds) {
          batch.rawUpdate(
            'UPDATE ${DatabaseTables.tablePatients} SET is_synced = 1, synced_at = ? WHERE id = ?',
            [syncIso, pId],
          );
        }

        for (final vId in response.syncedVisitIds) {
          batch.rawUpdate(
            'UPDATE ${DatabaseTables.tableClinicalVisits} SET is_synced = 1 WHERE id = ?',
            [vId],
          );
        }

        for (final lId in response.syncedLookupIds) {
          batch.rawUpdate(
            'UPDATE ${DatabaseTables.tableLookupItems} SET is_synced = 1 WHERE id = ?',
            [lId],
          );
        }

        await batch.commit(noResult: true);

        await _databaseService.purgeConfirmedDeletedTombstones(
          txn,
          entityType: 'patient',
          pushedIds: deletedPatientIds,
          confirmedIds: response.deletedPatientIds,
        );
        await _databaseService.purgeConfirmedDeletedTombstones(
          txn,
          entityType: 'clinical_visit',
          pushedIds: deletedVisitIds,
          confirmedIds: response.deletedVisitIds,
        );
      });

      // 8. Audit log
      await _auditRepository.logActivity(
        userId: userId,
        userName: 'Sync Engine',
        userRole: AppConstants.roleDataTaker,
        action: AppConstants.auditActionSyncUpload,
        entityType: 'SyncPayload',
        entityId: deviceId,
        detailsJson: '{"patientsPushed":${response.syncedPatientIds.length},"visitsPushed":${response.syncedVisitIds.length},"lookupsPushed":${response.syncedLookupIds.length}}',
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
      String? syncedOrgName;
      for (final user in response.users) {
        if (user.tenantName.isNotEmpty &&
            !AppConstants.isLegacyDefaultOrganization(user.tenantName)) {
          syncedOrgName = user.tenantName;
          break;
        }
      }
      if (syncedOrgName != null) {
        await SessionService.current?.saveOrganizationName(syncedOrgName);
      }

      await db.transaction((txn) async {
        // 1. Persist remotely deleted camp IDs into local deleted_camp_ids tombstone metadata
        final allDeletedCampIds = await _databaseService.addDeletedCampIds(
          txn,
          response.deletedCampIds,
        );

        // Pre-load local state in single bulk queries instead of N per-row queries
        // to avoid 10s SQLite Web Worker transaction lock warnings on Flutter Web.
        final locallyDeletedPatientIds = <String>{...response.deletedPatientIds};
        final locallyDeletedVisitIds = <String>{...response.deletedVisitIds};
        try {
          final localDelRows = await txn.query(DatabaseTables.tableDeletedEntitiesQueue);
          for (final r in localDelRows) {
            final id = (r['entity_id']?.toString().isNotEmpty == true)
                ? r['entity_id']!.toString()
                : (r['id']?.toString() ?? '');
            final type = r['entity_type']?.toString() ?? '';
            if (id.isEmpty) continue;
            if (type == 'patient') locallyDeletedPatientIds.add(id);
            if (type == 'clinical_visit') locallyDeletedVisitIds.add(id);
          }
        } catch (_) {}

        final existingCampRows = await txn.query(DatabaseTables.tableCamps);
        final existingCampsById = <String, Map<String, Object?>>{
          for (final r in existingCampRows)
            if (r['id'] != null) r['id'].toString(): r,
        };

        final existingUserRows = await txn.query(
          DatabaseTables.tableUsers,
          columns: ['id', 'password_hash', 'pin_hash', 'updated_at', 'assigned_camp_ids'],
        );
        final existingUsersById = <String, Map<String, Object?>>{
          for (final r in existingUserRows)
            if (r['id'] != null) r['id'].toString(): r,
        };

        final existingPatientRows = await txn.query(
          DatabaseTables.tablePatients,
          columns: ['id', 'patient_id', 'is_synced', 'treatment_level'],
        );
        final existingPatientsById = <String, Map<String, Object?>>{
          for (final r in existingPatientRows)
            if (r['id'] != null) r['id'].toString(): r,
        };

        final existingVisitRows = await txn.query(
          DatabaseTables.tableClinicalVisits,
          columns: ['id', 'is_synced', 'treatment_level'],
        );
        final existingVisitsById = <String, Map<String, Object?>>{
          for (final r in existingVisitRows)
            if (r['id'] != null) r['id'].toString(): r,
        };

        final batch = txn.batch();

        // Process entity deletions from central server
        for (final campId in response.deletedCampIds) {
          batch.delete(
            DatabaseTables.tableCamps,
            where: 'id = ?',
            whereArgs: [campId],
          );
          batch.delete(
            DatabaseTables.tablePatients,
            where: 'camp_id = ?',
            whereArgs: [campId],
          );
          batch.delete(
            DatabaseTables.tableClinicalVisits,
            where: 'camp_id = ?',
            whereArgs: [campId],
          );
        }

        for (final campId in allDeletedCampIds) {
          batch.delete(
            DatabaseTables.tableCamps,
            where: 'id = ?',
            whereArgs: [campId],
          );
        }

        for (final lookupId in response.deletedLookupIds) {
          batch.delete(
            DatabaseTables.tableLookupItems,
            where: 'id = ?',
            whereArgs: [lookupId],
          );
        }

        for (final userId in response.deletedUserIds) {
          batch.delete(
            DatabaseTables.tableUsers,
            where: 'id = ?',
            whereArgs: [userId],
          );
        }

        for (final patientId in response.deletedPatientIds) {
          final matchingRow = existingPatientsById[patientId];
          if (matchingRow != null) {
            final tokenId = matchingRow['patient_id']?.toString() ?? '';
            if (tokenId.isNotEmpty) {
              batch.delete(
                DatabaseTables.tableClinicalVisits,
                where: 'patient_id = ? COLLATE NOCASE',
                whereArgs: [tokenId],
              );
            }
            batch.delete(
              DatabaseTables.tableClinicalVisits,
              where: 'patient_id = ?',
              whereArgs: [patientId],
            );
            batch.delete(
              DatabaseTables.tablePatients,
              where: 'id = ?',
              whereArgs: [patientId],
            );
            existingPatientsById.remove(patientId);
          } else {
            batch.rawDelete(
              'DELETE FROM ${DatabaseTables.tableClinicalVisits} '
              'WHERE patient_id = ? AND NOT EXISTS ('
              '  SELECT 1 FROM ${DatabaseTables.tablePatients} p '
              '  WHERE p.patient_id = ${DatabaseTables.tableClinicalVisits}.patient_id COLLATE NOCASE '
              '    AND p.id != ?'
              ')',
              [patientId, patientId],
            );
          }
        }

        for (final visitId in response.deletedVisitIds) {
          batch.delete(
            DatabaseTables.tableClinicalVisits,
            where: 'id = ?',
            whereArgs: [visitId],
          );
          existingVisitsById.remove(visitId);
        }

        // 2. Upsert camps (skipping any tombstoned / locally deleted camps)
        for (final camp in response.camps) {
          if (allDeletedCampIds.contains(camp.id)) continue;
          final existingMap = existingCampsById[camp.id];
          if (existingMap == null) {
            batch.insert(
              DatabaseTables.tableCamps,
              camp.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } else {
            final local = CampModel.fromMap(existingMap);
            final localUpdated = (local.updatedAt ?? local.createdAt).toUtc();
            final incomingUpdated = (camp.updatedAt ?? camp.createdAt).toUtc();
            if ((local.status == CampStatus.closed || local.status == CampStatus.archived) &&
                camp.status == CampStatus.open) {
              continue;
            }
            if (local.status == CampStatus.open && camp.status != CampStatus.open) {
              continue;
            }
            if (incomingUpdated.isAfter(localUpdated)) {
              batch.update(
                DatabaseTables.tableCamps,
                camp.toMap(),
                where: 'id = ?',
                whereArgs: [camp.id],
              );
            }
          }
        }

        // 3. Upsert lookup items (marked as synced)
        for (final item in response.lookupItems) {
          final itemMap = item.toMap();
          itemMap['is_synced'] = 1;
          batch.insert(
            DatabaseTables.tableLookupItems,
            itemMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // 4. Upsert users with server-authoritative credential preservation.
        final updatedUserIdsInPull = <String>{};
        for (final user in response.users) {
          updatedUserIdsInPull.add(user.id);
          final existing = existingUsersById[user.id];
          final userMap = user.toMap();
          if (existing != null) {
            final localPass = existing['password_hash']?.toString();
            final localPin = existing['pin_hash']?.toString();

            final incomingPassEmpty =
                userMap['password_hash'] == null || userMap['password_hash'].toString().isEmpty;
            final incomingPinEmpty =
                userMap['pin_hash'] == null || userMap['pin_hash'].toString().isEmpty;

            if (incomingPassEmpty && localPass != null && localPass.isNotEmpty) {
              userMap['password_hash'] = localPass;
            }
            if (incomingPinEmpty && localPin != null && localPin.isNotEmpty) {
              userMap['pin_hash'] = localPin;
            }
          }
          if (allDeletedCampIds.isNotEmpty) {
            final cleanedCamps = (userMap['assigned_camp_ids']?.toString() ?? '')
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty && !allDeletedCampIds.contains(s))
                .join(',');
            userMap['assigned_camp_ids'] = cleanedCamps;
          }
          batch.insert(
            DatabaseTables.tableUsers,
            userMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        if (allDeletedCampIds.isNotEmpty) {
          for (final uRow in existingUserRows) {
            final uid = uRow['id']?.toString() ?? '';
            if (uid.isEmpty || updatedUserIdsInPull.contains(uid)) continue;
            final raw = uRow['assigned_camp_ids']?.toString() ?? '';
            if (raw.isEmpty) continue;
            final parts = raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
            final filtered = parts.where((s) => !allDeletedCampIds.contains(s)).toList();
            if (filtered.length != parts.length) {
              batch.update(
                DatabaseTables.tableUsers,
                {'assigned_camp_ids': filtered.join(',')},
                where: 'id = ?',
                whereArgs: [uid],
              );
            }
          }
        }

        final pullSyncIso = DateTime.now().toIso8601String();
        if (syncedOrgName != null) {
          batch.insert(
            DatabaseTables.tableMetadata,
            {
              'key': 'organization_name',
              'value': syncedOrgName,
              'updated_at': pullSyncIso,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Track active patient Token IDs after upserts
        final activeTokenIds = <String>{
          for (final r in existingPatientsById.values)
            if ((r['patient_id']?.toString().trim().isNotEmpty ?? false))
              r['patient_id']!.toString().trim().toLowerCase(),
        };

        // 5. Upsert patients from central cloud (R1 fix: guard local unsynced edits, skip deleted camps & deleted patients)
        for (final patient in response.patients) {
          if (allDeletedCampIds.contains(patient.campId)) continue;
          if (locallyDeletedPatientIds.contains(patient.id)) continue;

          final existingPat = existingPatientsById[patient.id];
          if (existingPat != null && (existingPat['is_synced'] as int? ?? 1) == 0) {
            // Local record has unsynced modifications: do not overwrite with remote copy
            continue;
          }

          final patientMap = patient.toMap();
          patientMap['is_synced'] = 1;
          patientMap['synced_at'] = pullSyncIso;

          // Preserve existing local treatment_level if incoming remote copy has null/empty
          if (patientMap['treatment_level'] == null ||
              (patientMap['treatment_level'] as String).trim().isEmpty) {
            final localTl = existingPat?['treatment_level']?.toString().trim();
            if (localTl != null && localTl.isNotEmpty) {
              patientMap['treatment_level'] = localTl;
            }
          }

          if (patient.patientId.trim().isNotEmpty) {
            activeTokenIds.add(patient.patientId.trim().toLowerCase());
          }

          batch.insert(
            DatabaseTables.tablePatients,
            patientMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // 6. Upsert clinical visits from central cloud (R1 fix: guard local unsynced edits, skip deleted camps & deleted visits)
        for (final visit in response.clinicalVisits) {
          if (allDeletedCampIds.contains(visit.campId)) continue;
          if (locallyDeletedVisitIds.contains(visit.id)) continue;
          final visitTokenLower = visit.patientId.trim().toLowerCase();
          if (locallyDeletedPatientIds.contains(visit.patientId) &&
              !activeTokenIds.contains(visitTokenLower)) {
            continue;
          }

          final existingVis = existingVisitsById[visit.id];
          if (existingVis != null && (existingVis['is_synced'] as int? ?? 1) == 0) {
            // Local visit has unsynced modifications: do not overwrite with remote copy
            continue;
          }

          final visitMap = visit.toMap();
          visitMap['is_synced'] = 1;

          // Preserve existing local treatment_level if incoming remote copy has null/empty
          if (visitMap['treatment_level'] == null ||
              (visitMap['treatment_level'] as String).trim().isEmpty) {
            final localTl = existingVis?['treatment_level']?.toString().trim();
            if (localTl != null && localTl.isNotEmpty) {
              visitMap['treatment_level'] = localTl;
            }
          }

          batch.insert(
            DatabaseTables.tableClinicalVisits,
            visitMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Cascade purge any orphaned records whose camps were deleted
        batch.rawDelete(
          'DELETE FROM ${DatabaseTables.tablePatients} WHERE camp_id NOT IN (SELECT id FROM ${DatabaseTables.tableCamps})',
        );
        batch.rawDelete(
          'DELETE FROM ${DatabaseTables.tableClinicalVisits} WHERE camp_id NOT IN (SELECT id FROM ${DatabaseTables.tableCamps})',
        );

        await batch.commit(noResult: true);
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
