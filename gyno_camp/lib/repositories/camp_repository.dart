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

class CampRepository implements ICampRepository {
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

  Future<Set<String>> _getDeletedCampIds(Database db) async {
    try {
      final meta = await db.query(
        DatabaseTables.tableMetadata,
        where: "key = 'deleted_camp_ids'",
      );
      if (meta.isNotEmpty) {
        final val = meta.first['value'] as String? ?? '';
        return val.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
      }
    } catch (e) {
      debugPrint('[CampRepo] Error reading deleted_camp_ids: $e');
    }
    return {};
  }

  Future<void> _addDeletedCampId(Database db, String campId) async {
    try {
      final existing = await _getDeletedCampIds(db);
      existing.add(campId);
      await db.insert(
        DatabaseTables.tableMetadata,
        {
          'key': 'deleted_camp_ids',
          'value': existing.join(','),
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('[CampRepo] Error saving deleted_camp_ids: $e');
    }
  }

  Future<void> _removeDeletedCampId(Database db, String campId) async {
    try {
      final meta = await db.query(
        DatabaseTables.tableMetadata,
        where: "key = 'deleted_camp_ids'",
      );
      if (meta.isNotEmpty) {
        final val = meta.first['value'] as String? ?? '';
        final remaining = val
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && s != campId)
            .toList();
        await db.insert(
          DatabaseTables.tableMetadata,
          {
            'key': 'deleted_camp_ids',
            'value': remaining.join(','),
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (e) {
      debugPrint('[CampRepo] Error clearing deleted_camp_ids: $e');
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

    // 2. Enforce single active camp invariant locally:
    // If multiple camps somehow are marked 'OPEN', keep only the most recent one OPEN, and close the others.
    final openRows = await db.query(
      DatabaseTables.tableCamps,
      where: 'status = ?',
      whereArgs: [AppConstants.campStatusOpen],
      orderBy: 'updated_at DESC, created_at DESC, start_date DESC',
    );
    if (openRows.length > 1) {
      for (int i = 1; i < openRows.length; i++) {
        final staleId = openRows[i]['id'] as String;
        await db.update(
          DatabaseTables.tableCamps,
          {'status': AppConstants.campStatusClosed, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [staleId],
        );
      }
    }

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
        COALESCE(c.updated_at, c.created_at) DESC
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

    return localCamps;
  }

  void _syncCentralCampsInBackground(Database db) {
    if (!HttpCentralApiService.isServerConfigured) return;
    Future<void>(() async {
      try {
        final deletedCampIds = await _getDeletedCampIds(db);
        final centralCamps = await HttpCentralApiService().fetchCentralCamps();
        if (centralCamps.isEmpty) return;
        for (final c in centralCamps) {
          // If camp was deleted locally, inform central server to delete and skip re-insertion
          if (deletedCampIds.contains(c.id)) {
            HttpCentralApiService().deleteCentralCamp(c.id);
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
            final localUpdated = local.updatedAt ?? local.createdAt;
            final centralUpdated = c.updatedAt ?? c.createdAt;

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
        CampModel? matched;
        for (final c in centralCamps) {
          if (c.id == id) {
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
      ORDER BY c.updated_at DESC, c.created_at DESC
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
    final newCamp = camp.copyWith(id: campId, createdAt: DateTime.now());

    // Remove from deleted_camp_ids tombstone if re-created
    await _removeDeletedCampId(db, campId);

    await db.insert(
      DatabaseTables.tableCamps,
      newCamp.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

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
        HttpCentralApiService().broadcastCamp(newCamp);
      } catch (e) { debugPrint('[CampRepo] Central sync error: $e'); }
    }

    return newCamp;
  }

  @override
  Future<bool> openCamp(String campId, {required String adminUserId, required String deviceId}) async {
    final camp = await getCampById(campId);
    if (camp == null) return false;

    final db = await _databaseService.database;
    final now = DateTime.now();

    // Enforce single active camp rule: close all other currently open camps
    final otherOpenCamps = await db.query(
      DatabaseTables.tableCamps,
      where: 'status = ? AND id != ?',
      whereArgs: [AppConstants.campStatusOpen, campId],
    );
    for (final m in otherOpenCamps) {
      final oldId = m['id'] as String;
      await closeCamp(oldId, adminUserId: adminUserId, deviceId: deviceId);
    }

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
    final now = DateTime.now();

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
    final now = DateTime.now();

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
    final now = DateTime.now();
    final updated = camp.copyWith(updatedAt: now);

    await db.update(
      DatabaseTables.tableCamps,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [camp.id],
    );

    await _auditRepository.logActivity(
      userId: adminUserId,
      userName: 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: AppConstants.auditActionCampUpdate,
      entityType: 'Camp',
      entityId: camp.id,
      detailsJson: '{"campCode":"${camp.campCode}","name":"${camp.name}"}',
      deviceId: deviceId,
    );

    if (enableCentralSync) {
      try {
        HttpCentralApiService().broadcastCamp(updated);
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
      updatedAt: DateTime.now(),
    );

    await db.update(
      DatabaseTables.tableCamps,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [campId],
    );

    // 1. Broadcast the updated camp to Central Cloud
    if (enableCentralSync) {
      try {
        HttpCentralApiService().broadcastCamp(updated);
      } catch (e) { debugPrint('[CampRepo] Central sync error: $e'); }
    }

    // 2. Also update each assigned staff's user record with this campId
    try {
      for (final staffId in staffIds) {
        final userMaps = await db.query(
          DatabaseTables.tableUsers,
          where: 'id = ?',
          whereArgs: [staffId],
          limit: 1,
        );
        if (userMaps.isNotEmpty) {
          final user = UserModel.fromMap(userMaps.first);
          final existingCamps = List<String>.from(user.assignedCampIds);
          if (!existingCamps.contains(campId)) {
            existingCamps.add(campId);
            final updatedUser = user.copyWith(assignedCampIds: existingCamps);
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
      }
    } catch (e) { debugPrint('[CampRepo] Central sync error: $e'); }

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
