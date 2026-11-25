import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../core/services/http_central_api_service.dart';
import '../models/camp_model.dart';
import '../models/user_model.dart';
import 'audit_repository.dart';
import 'lookup_repository.dart';

abstract class ICampRepository {
  Future<List<CampModel>> getAllCamps({String? tenantId});
  Future<CampModel?> getCampById(String id);
  Future<CampModel?> getActiveCamp();
  Future<CampModel> createCamp(CampModel camp, {required String createdByUserId, required String deviceId});
  Future<bool> openCamp(String campId, {required String adminUserId, required String deviceId});
  Future<bool> closeCamp(String campId, {required String adminUserId, required String deviceId});
  Future<bool> archiveCamp(String campId, {required String adminUserId, required String deviceId});
  Future<CampModel> updateCamp(CampModel camp, {required String adminUserId, required String deviceId});
  Future<bool> deleteCamp(String campId, {required String adminUserId, required String deviceId});
  Future<bool> assignStaff(String campId, List<String> staffIds, {required String adminUserId, required String deviceId});
}

/// Optional capability implemented by repositories that persist sticky default
/// doctor, nurse, and staff assignments across camp creations.
abstract class IDefaultCampRosterRepository {
  Future<DefaultCampRoster?> getDefaultCampRoster();
  Future<void> saveDefaultCampRoster(DefaultCampRoster roster);
}

class CampRepository implements ICampRepository, IDefaultCampRosterRepository {
  final DatabaseService _databaseService;
  final AuditRepository _auditRepository;
  final bool enableCentralSync;
  final Uuid _uuid = const Uuid();

  CampRepository({
    DatabaseService? databaseService,
    AuditRepository? auditRepository,
    this.enableCentralSync = true,
  })  : _databaseService = databaseService ?? DatabaseService(),
        _auditRepository = auditRepository ?? AuditRepository();

  Future<Set<String>> _getDeletedCampIds(Database db) =>
      _databaseService.getDeletedCampIds(db);

  Future<void> _addDeletedCampId(Database db, String campId) =>
      _databaseService.addDeletedCampIds(db, [campId]);

  Future<void> _removeDeletedCampId(Database db, String campId) =>
      _databaseService.removeDeletedCampId(db, campId);

  Future<DefaultCampRoster?> _readStoredDefaultRoster(DatabaseExecutor db) async {
    try {
      final rows = await db.query(
        DatabaseTables.tableMetadata,
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [DatabaseTables.metaKeyDefaultCampRoster],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      return DefaultCampRoster.tryParseJson(rows.first['value'] as String?);
    } catch (e) {
      debugPrint('[CampRepo] Read default roster error: $e');
      return null;
    }
  }

  Future<void> _writeStoredDefaultRoster(
    DatabaseExecutor db,
    DefaultCampRoster roster,
  ) async {
    try {
      await db.insert(
        DatabaseTables.tableMetadata,
        {
          'key': DatabaseTables.metaKeyDefaultCampRoster,
          'value': roster.toJsonString(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('[CampRepo] Write default roster error: $e');
    }
  }

  @override
  Future<DefaultCampRoster?> getDefaultCampRoster() async {
    final db = await _databaseService.database;
    return _readStoredDefaultRoster(db);
  }

  @override
  Future<void> saveDefaultCampRoster(DefaultCampRoster roster) async {
    final db = await _databaseService.database;
    await _writeStoredDefaultRoster(db, roster);
  }

  /// Synchronizes `users.assigned_camp_ids` in SQLite (and broadcasts updated
  /// users to Central Cloud) so every staff member's RBAC profile immediately
  /// reflects their assignment to [campId].
  Future<void> _syncUsersForCampAssignment(
    Database db, {
    required String campId,
    required List<String> staffIds,
  }) async {
    try {
      final allUserMaps = await db.query(DatabaseTables.tableUsers);
      final staffIdSet = staffIds.toSet();
      final nowUtc = DateTime.now().toUtc();

      for (final uMap in allUserMaps) {
        final user = UserModel.fromMap(uMap);
        final existingCamps = List<String>.from(user.assignedCampIds);
        bool userChanged = false;

        if (staffIdSet.contains(user.id)) {
          if (!existingCamps.contains(campId)) {
            existingCamps.add(campId);
            userChanged = true;
          }
        } else {
          if (existingCamps.contains(campId)) {
            existingCamps.remove(campId);
            userChanged = true;
          }
        }

        if (userChanged) {
          final updatedUser = user.copyWith(
            assignedCampIds: existingCamps,
            updatedAt: nowUtc,
          );
          await db.update(
            DatabaseTables.tableUsers,
            updatedUser.toMap(),
            where: 'id = ?',
            whereArgs: [user.id],
          );
          if (enableCentralSync) {
            try {
              await HttpCentralApiService().broadcastUser(updatedUser);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[CampRepo] User camp assignment sync error: $e');
    }
  }

  @override
  Future<List<CampModel>> getAllCamps({String? tenantId}) async {
    final db = await _databaseService.database;

    // Load tombstoned deleted camp IDs to guarantee deleted camps are never displayed or re-inserted
    final deletedCampIds = await _getDeletedCampIds(db);

    // 1. Sync latest camps from Central Cloud in background without blocking local return
    if (enableCentralSync && !HttpCentralApiService.isServerCooldownActive) {
      _syncCentralCampsInBackground(db);
    }
    // NOTE: Single-active-camp enforcement is intentionally NOT done here.
    // getAllCamps() is a READ-ONLY path — silently closing camps on every
    // list load caused unexpected data loss. Enforcement only happens in
    // openCamp() and updateCamp() when a camp is explicitly activated.


    final hasTenant = tenantId != null && tenantId.isNotEmpty && tenantId != 'tenant_default' && tenantId != 'global';
    final sql = '''
      SELECT c.*,
             COALESCE((SELECT COUNT(*) FROM ${DatabaseTables.tablePatients} p WHERE p.camp_id = c.id), 0) AS live_patient_count
      FROM ${DatabaseTables.tableCamps} c
      ${hasTenant ? "WHERE c.tenant_id = ? OR c.tenant_id = 'tenant_default' OR c.tenant_id = 'global'" : ""}
      ORDER BY 
        CASE 
          WHEN c.status = 'OPEN' THEN 1
          WHEN c.status = 'SCHEDULED' THEN 2
          WHEN c.status = 'DRAFT' THEN 3
          WHEN c.status = 'CLOSED' THEN 4
          WHEN c.status = 'ARCHIVED' THEN 5
          ELSE 6
        END ASC,
        c.created_at DESC,
        c.camp_code ASC,
        c.id ASC
    ''';
    final maps = await db.rawQuery(sql, hasTenant ? [tenantId] : null);

    // Self-healing: if any local SQLite row is in deletedCampIds, purge it immediately
    if (deletedCampIds.isNotEmpty) {
      for (final id in deletedCampIds) {
        db.delete(DatabaseTables.tableCamps, where: 'id = ?', whereArgs: [id]);
      }
    }

    final localCamps = maps
        .map((m) {
          final map = Map<String, dynamic>.from(m);
          if (map.containsKey('live_patient_count') && map['live_patient_count'] != null) {
            map['total_patients_registered'] = map['live_patient_count'];
          }
          return CampModel.fromMap(map);
        })
        .where((c) => !deletedCampIds.contains(c.id))
        .toList();

    // Self-healing: Reconcile any staff assignments recorded in users.assigned_camp_ids
    // that are missing from camps.assigned_staff_ids (e.g. from staff registered before bi-directional sync).
    try {
      final userRows = await db.query(DatabaseTables.tableUsers);
      final staffUsers = userRows
          .map((r) => UserModel.fromMap(r))
          .where((u) => !u.isSuperAdmin && u.role != UserRole.superAdmin)
          .toList();

      for (int i = 0; i < localCamps.length; i++) {
        final camp = localCamps[i];
        final currentStaffIds = Set<String>.from(camp.assignedStaffIds);
        bool campChanged = false;

        // 1. Add any active staff assigned to this camp in their user record
        for (final u in staffUsers) {
          if (u.assignedCampIds.contains(camp.id) && !currentStaffIds.contains(u.id)) {
            currentStaffIds.add(u.id);
            campChanged = true;
          }
        }

        // 2. Remove any orphaned staff IDs that no longer exist in tableUsers
        final validUserIds = userRows.map((r) => r['id'] as String).toSet();
        final beforeRemoveCount = currentStaffIds.length;
        currentStaffIds.removeWhere((id) => !validUserIds.contains(id));
        if (currentStaffIds.length != beforeRemoveCount) {
          campChanged = true;
        }

        if (campChanged) {
          final nowUtc = DateTime.now().toUtc();
          final updatedStaffList = currentStaffIds.toList();
          final updatedCamp = camp.copyWith(
            assignedStaffIds: updatedStaffList,
            updatedAt: nowUtc,
          );
          localCamps[i] = updatedCamp;

          await db.update(
            DatabaseTables.tableCamps,
            {
              'assigned_staff_ids': updatedStaffList.join(','),
              'updated_at': nowUtc.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [camp.id],
          );

          if (enableCentralSync) {
            try {
              await HttpCentralApiService().broadcastCamp(updatedCamp);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[CampRepo] Self-healing staff assignment reconciliation error: $e');
    }

    return localCamps;
  }

  void _syncCentralCampsInBackground(Database db) {
    if (!HttpCentralApiService.isServerConfigured) return;
    Future<void>(() async {
      try {
        final centralCamps = await HttpCentralApiService().fetchCentralCamps();
        if (centralCamps.isEmpty) return;
        final deletedCampIds = await _getDeletedCampIds(db);
        for (final c in centralCamps) {
          final latestDeleted = await _getDeletedCampIds(db);
          // If camp was deleted locally or via sync pull, inform central server to delete and skip re-insertion
          if (deletedCampIds.contains(c.id) || latestDeleted.contains(c.id)) {
            await db.delete(
              DatabaseTables.tableCamps,
              where: 'id = ?',
              whereArgs: [c.id],
            );
            await HttpCentralApiService().deleteCentralCamp(c.id);
            continue;
          }

          final existingRows = await db.query(
            DatabaseTables.tableCamps,
            where: 'id = ?',
            whereArgs: [c.id],
            limit: 1,
          );
          if (existingRows.isEmpty) {
            await db.insert(
              DatabaseTables.tableCamps,
              c.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } else {
            final local = CampModel.fromMap(existingRows.first);
            final localUpdated = (local.updatedAt ?? local.createdAt).toUtc();
            final centralUpdated = (c.updatedAt ?? c.createdAt).toUtc();

            // Guard A: Protect a locally-OPEN camp from being downgraded by a STALE
            // central snapshot (where local is newer). BUT if central has a NEWER close/archive
            // timestamp, it means another device/browser already closed the camp — accept it.
            if (local.status == CampStatus.open && c.status != CampStatus.open) {
              if (!centralUpdated.isAfter(localUpdated)) {
                // Central snapshot is stale — push our OPEN state back to central.
                await HttpCentralApiService().broadcastCamp(local);
                continue;
              }
              // Central is newer → fall through to accept the close from central below.
            }

            // Guard B: A locally CLOSED/ARCHIVED camp should NOT blindly push to central
            // if central already has a NEWER OPEN state — that would overwrite a legitimate
            // reopen performed on another device/tab (e.g. Chrome vs Opera, or tablet vs web).
            //
            // ✅ FIX: Only push our CLOSED/ARCHIVED copy if local is genuinely newer.
            //   If central's OPEN is newer, fall through so the generic branch below
            //   can overwrite local with the newer OPEN from central.
            if ((local.status == CampStatus.closed || local.status == CampStatus.archived) &&
                c.status == CampStatus.open) {
              if (localUpdated.isAfter(centralUpdated)) {
                // Local close/archive is genuinely newer → push our state to central.
                await HttpCentralApiService().broadcastCamp(local);
                continue;
              }
              // Central OPEN is newer (legitimate reopen from another device) → fall through.
            }

            if (centralUpdated.isAfter(localUpdated)) {
              await db.update(
                DatabaseTables.tableCamps,
                c.toMap(),
                where: 'id = ?',
                whereArgs: [c.id],
              );
            } else if (localUpdated.isAfter(centralUpdated)) {
              await HttpCentralApiService().broadcastCamp(local);
            }
          }
        }
      } catch (e) { debugPrint('[CampRepo] Central sync error: $e'); }
    });
  }

  @override
  Future<CampModel?> getCampById(String id) async {
    final db = await _databaseService.database;
    final deletedCampIds = await _getDeletedCampIds(db);
    if (deletedCampIds.contains(id)) return null;

    final maps = await db.rawQuery('''
      SELECT c.*,
             COALESCE((SELECT COUNT(*) FROM ${DatabaseTables.tablePatients} p WHERE p.camp_id = c.id), 0) AS live_patient_count
      FROM ${DatabaseTables.tableCamps} c
      WHERE c.id = ?
      LIMIT 1
    ''', [id]);

    if (maps.isNotEmpty) {
      final map = Map<String, dynamic>.from(maps.first);
      if (map.containsKey('live_patient_count') && map['live_patient_count'] != null) {
        map['total_patients_registered'] = map['live_patient_count'];
      }
      return CampModel.fromMap(map);
    }

    // Try central cloud if enabled and server is available
    if (enableCentralSync && !HttpCentralApiService.isServerCooldownActive) {
      try {
        final centralCamps = await HttpCentralApiService().fetchCentralCamps();
        final latestDeleted = await _getDeletedCampIds(db);
        if (latestDeleted.contains(id)) return null;
        CampModel? matched;
        for (final c in centralCamps) {
          if (c.id == id && !latestDeleted.contains(c.id)) {
            await db.insert(
              DatabaseTables.tableCamps,
              c.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            matched = c;
            break;
          }
        }
        if (matched != null) return matched;
      } catch (e) { debugPrint('[CampRepo] Central sync error: $e'); }
    }

    return null;
  }

  @override
  Future<CampModel?> getActiveCamp() async {
    final db = await _databaseService.database;
    final maps = await db.rawQuery('''
      SELECT c.*,
             COALESCE((SELECT COUNT(*) FROM ${DatabaseTables.tablePatients} p WHERE p.camp_id = c.id), 0) AS live_patient_count
      FROM ${DatabaseTables.tableCamps} c
      WHERE c.status = ?
      ORDER BY c.created_at DESC, c.camp_code ASC
      LIMIT 1
    ''', [AppConstants.campStatusOpen]);
    if (maps.isNotEmpty) {
      final map = Map<String, dynamic>.from(maps.first);
      if (map.containsKey('live_patient_count') && map['live_patient_count'] != null) {
        map['total_patients_registered'] = map['live_patient_count'];
      }
      return CampModel.fromMap(map);
    }

    return null;
  }

  @override
  Future<CampModel> createCamp(CampModel camp, {required String createdByUserId, required String deviceId}) async {
    final db = await _databaseService.database;
    final campId = camp.id.isEmpty ? 'camp-${_uuid.v4().substring(0, 8)}' : camp.id;
    final now = DateTime.now().toUtc();
    final newCamp = camp.copyWith(id: campId, createdAt: now, updatedAt: now);

    // Remove from deleted_camp_ids tombstone if re-created
    await _removeDeletedCampId(db, campId);

    await db.insert(
      DatabaseTables.tableCamps,
      newCamp.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Update sticky default roster for subsequent camps
    final existingDefault = await _readStoredDefaultRoster(db);
    final candidateDefault = DefaultCampRoster.fromCamp(newCamp);
    if (existingDefault != null || candidateDefault.hasAnyDefaults) {
      await _writeStoredDefaultRoster(db, candidateDefault);
    }

    await _auditRepository.logActivity(
      userId: createdByUserId,
      userName: 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: AppConstants.auditActionCampCreate,
      entityType: 'Camp',
      entityId: newCamp.id,
      detailsJson: '{"campCode":"${newCamp.campCode}","name":"${newCamp.name}"}',
      deviceId: deviceId,
    );

    if (enableCentralSync) {
      try {
        await HttpCentralApiService().broadcastCamp(newCamp);
      } catch (e) { debugPrint('[CampRepo] Central sync error: $e'); }
    }

    // Keep users.assigned_camp_ids in sync when staff are assigned at creation time
    if (newCamp.assignedStaffIds.isNotEmpty) {
      await _syncUsersForCampAssignment(
        db,
        campId: newCamp.id,
        staffIds: newCamp.assignedStaffIds,
      );
    }

    // Ensure standard clinical formulary is seeded so this new camp inherits all defaults
    try {
      await LookupRepository(
        databaseService: _databaseService,
        auditRepository: _auditRepository,
        enableCentralSync: enableCentralSync,
      ).ensureDefaultsSeeded(tenantId: newCamp.tenantId);
    } catch (e) {
      debugPrint('[CampRepo] Note: ensureDefaultsSeeded on camp create: $e');
    }

    return newCamp;
  }

  @override
  Future<bool> openCamp(String campId, {required String adminUserId, required String deviceId}) async {
    final camp = await getCampById(campId);
    if (camp == null) return false;

    final db = await _databaseService.database;
    final now = DateTime.now().toUtc();

    // Multiple camps can be open simultaneously — no close-cascade needed.
    // Each camp manages its own lifecycle independently.

    final updated = camp.copyWith(
      status: CampStatus.open,
      updatedAt: now,
    );

    await db.update(
      DatabaseTables.tableCamps,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [campId],
    );

    await _auditRepository.logActivity(
      userId: adminUserId,
      userName: 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: AppConstants.auditActionCampOpen,
      entityType: 'Camp',
      entityId: campId,
      detailsJson: '{"campCode":"${camp.campCode}","status":"OPEN"}',
      deviceId: deviceId,
    );

    if (enableCentralSync) {
      try {
        await HttpCentralApiService().broadcastCamp(updated);
      } catch (e) { debugPrint('[CampRepo] Central sync error: $e'); }
    }

    return true;
  }

  @override
  Future<bool> closeCamp(String campId, {required String adminUserId, required String deviceId}) async {
    final camp = await getCampById(campId);
    if (camp == null) return false;

    final db = await _databaseService.database;
    final now = DateTime.now().toUtc();

    final updated = camp.copyWith(
      status: CampStatus.closed,
      updatedAt: now,
    );

    await db.update(
      DatabaseTables.tableCamps,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [campId],
    );

    await _auditRepository.logActivity(
      userId: adminUserId,
      userName: 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: AppConstants.auditActionCampClose,
      entityType: 'Camp',
      entityId: campId,
      detailsJson: '{"campCode":"${camp.campCode}","status":"CLOSED"}',
      deviceId: deviceId,
    );

    if (enableCentralSync) {
      try {
        await HttpCentralApiService().broadcastCamp(updated);
      } catch (e) { debugPrint('[CampRepo] Central sync error: $e'); }
    }

    return true;
  }

  @override
  Future<bool> archiveCamp(String campId, {required String adminUserId, required String deviceId}) async {
    final camp = await getCampById(campId);
    if (camp == null) return false;

    final db = await _databaseService.database;
    final now = DateTime.now().toUtc();

    final updated = camp.copyWith(
      status: CampStatus.archived,
      updatedAt: now,
    );

    await db.update(
      DatabaseTables.tableCamps,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [campId],
    );

    await _auditRepository.logActivity(
      userId: adminUserId,
      userName: 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: AppConstants.auditActionCampArchive,
      entityType: 'Camp',
      entityId: campId,
      detailsJson: '{"campCode":"${camp.campCode}","status":"ARCHIVED"}',
      deviceId: deviceId,
    );

    if (enableCentralSync) {
      try {
        await HttpCentralApiService().broadcastCamp(updated);
      } catch (e) { debugPrint('[CampRepo] Central sync error: $e'); }
    }

    return true;
  }

  @override
  Future<CampModel> updateCamp(CampModel camp, {required String adminUserId, required String deviceId}) async {
    final db = await _databaseService.database;
    final now = DateTime.now().toUtc();
    final updated = camp.copyWith(updatedAt: now);

    // Multiple camps can be open simultaneously — no close-cascade on update.
    // Each camp manages its own lifecycle independently.

    await db.update(
      DatabaseTables.tableCamps,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [camp.id],
    );

    // Update sticky default doctor/nurse roster when editing an active/upcoming camp
    // (Closed/Archived historical edits do not overwrite the current default team).
    if (!updated.status.isLocked) {
      final existingDefault = await _readStoredDefaultRoster(db);
      final updatedDocs = updated.doctorNames.isNotEmpty
          ? List<String>.from(updated.doctorNames)
          : (updated.doctorName.trim().isNotEmpty
              ? [updated.doctorName.trim()]
              : <String>[]);
      final mergedDefault = (existingDefault ?? DefaultCampRoster.fromCamp(updated)).copyWith(
        doctorNames: updatedDocs,
        showDoctorOnForms: updated.showDoctorOnForms,
        nurseNames: List<String>.from(updated.nurseNames),
        showNurseOnForms: updated.showNurseOnForms,
        sourceCampId: updated.id,
        sourceCampCode: updated.campCode,
      );
      if (existingDefault != null || mergedDefault.hasAnyDefaults) {
        await _writeStoredDefaultRoster(db, mergedDefault);
      }
    }

    await _auditRepository.logActivity(
      userId: adminUserId,
      userName: 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: AppConstants.auditActionCampUpdate,
      entityType: 'Camp',
      entityId: camp.id,
      detailsJson: '{"campCode":"${camp.campCode}","name":"${camp.name}","status":"${camp.status.toDbString()}"}',
      deviceId: deviceId,
    );

    if (enableCentralSync) {
      try {
        await HttpCentralApiService().broadcastCamp(updated);
      } catch (e) { debugPrint('[CampRepo] Central sync error: $e'); }
    }

    return updated;
  }

  @override
  Future<bool> deleteCamp(String campId, {required String adminUserId, required String deviceId}) async {
    final camp = await getCampById(campId);
    final db = await _databaseService.database;

    // 1. Immediately save to tombstone so background sync cannot resurrect it
    await _addDeletedCampId(db, campId);

    // 2. Cascade delete in local database
    await db.delete(
      DatabaseTables.tableClinicalVisits,
      where: 'camp_id = ?',
      whereArgs: [campId],
    );
    await db.delete(
      DatabaseTables.tablePatients,
      where: 'camp_id = ?',
      whereArgs: [campId],
    );
    await db.delete(
      DatabaseTables.tableCamps,
      where: 'id = ?',
      whereArgs: [campId],
    );

    // Cascade safety: delete any orphaned patient or visit records
    try {
      await db.rawDelete('DELETE FROM ${DatabaseTables.tablePatients} WHERE camp_id NOT IN (SELECT id FROM ${DatabaseTables.tableCamps});');
      await db.rawDelete('DELETE FROM ${DatabaseTables.tableClinicalVisits} WHERE camp_id NOT IN (SELECT id FROM ${DatabaseTables.tableCamps});');
    } catch (e) { debugPrint('[CampRepo] Central sync error: $e'); }

    // Prune deleted campId from all staff assigned_camp_ids
    try {
      final userRows = await db.query(DatabaseTables.tableUsers);
      for (final row in userRows) {
        final user = UserModel.fromMap(row);
        if (user.assignedCampIds.contains(campId)) {
          final updatedCamps = List<String>.from(user.assignedCampIds)..remove(campId);
          final updatedUser = user.copyWith(assignedCampIds: updatedCamps);
          await db.update(
            DatabaseTables.tableUsers,
            updatedUser.toMap(),
            where: 'id = ?',
            whereArgs: [user.id],
          );
          if (enableCentralSync) {
            HttpCentralApiService().broadcastUser(updatedUser);
          }
        }
      }
    } catch (e) { debugPrint('[CampRepo] Central sync error: $e'); }

    await _auditRepository.logActivity(
      userId: adminUserId,
      userName: 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: 'CAMP_DELETED',
      entityType: 'Camp',
      entityId: campId,
      detailsJson: '{"campCode":"${camp?.campCode ?? campId}"}',
      deviceId: deviceId,
    );

    if (enableCentralSync) {
      try {
        await HttpCentralApiService().deleteCentralCamp(campId);
      } catch (e) { debugPrint('[CampRepo] Central sync error: $e'); }
    }

    return true;
  }

  @override
  Future<bool> assignStaff(String campId, List<String> staffIds, {required String adminUserId, required String deviceId}) async {
    final camp = await getCampById(campId);
    if (camp == null) return false;

    final db = await _databaseService.database;
    final updated = camp.copyWith(
      assignedStaffIds: staffIds,
      updatedAt: DateTime.now().toUtc(),
    );

    await db.update(
      DatabaseTables.tableCamps,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [campId],
    );

    // Update sticky default staff assignment when updating an active/upcoming camp
    if (!camp.status.isLocked) {
      final existingDefault = await _readStoredDefaultRoster(db);
      final mergedDefault = (existingDefault ?? DefaultCampRoster.fromCamp(updated)).copyWith(
        assignedStaffIds: List<String>.from(staffIds),
        sourceCampId: updated.id,
        sourceCampCode: updated.campCode,
      );
      if (existingDefault != null || mergedDefault.hasAnyDefaults) {
        await _writeStoredDefaultRoster(db, mergedDefault);
      }
    }

    // 1. Broadcast the updated camp to Central Cloud
    if (enableCentralSync) {
      try {
        await HttpCentralApiService().broadcastCamp(updated);
      } catch (e) { debugPrint('[CampRepo] Central sync error: $e'); }
    }

    // 2. Synchronize ALL users in SQLite and Central Cloud with this camp's staff list
    await _syncUsersForCampAssignment(
      db,
      campId: campId,
      staffIds: staffIds,
    );

    await _auditRepository.logActivity(
      userId: adminUserId,
      userName: 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: AppConstants.auditActionStaffAssign,
      entityType: 'Camp',
      entityId: campId,
      detailsJson: '{"campCode":"${camp.campCode}","staffCount":${staffIds.length}}',
      deviceId: deviceId,
    );

    return true;
  }
}
