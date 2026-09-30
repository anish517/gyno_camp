import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/clinical_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../core/services/http_central_api_service.dart';
import '../models/lookup_item_model.dart';
import '../models/sync_payload_model.dart';
import 'audit_repository.dart';

abstract class ILookupRepository {
  Future<List<LookupItemModel>> getAllItems({String? tenantId, String? campId});
  Future<List<LookupItemModel>> getItemsByCategory(String category, {String? tenantId, String? campId, bool activeOnly = false});
  Future<LookupItemModel> addItem(LookupItemModel item, {required String userId, required String userName, required String deviceId});
  Future<LookupItemModel> updateItem(LookupItemModel item, {required String userId, required String userName, required String deviceId});
  Future<bool> toggleItemStatus(String id, bool isActive, {required String userId, required String userName, required String deviceId, String? campId});
  Future<bool> deleteItem(String id, {required String userId, required String userName, required String deviceId, String? campId});
  Future<bool> restoreItemToCamp(String id, {required String campId, required String userId, required String userName, required String deviceId});
  Future<void> ensureDefaultsSeeded({String? tenantId});
  Future<void> backfillSubCategories();
}

class LookupRepository implements ILookupRepository {
  final DatabaseService _databaseService;
  final AuditRepository _auditRepository;
  final bool _enableCentralSync;
  final Uuid _uuid = const Uuid();

  LookupRepository({
    DatabaseService? databaseService,
    AuditRepository? auditRepository,
    this._enableCentralSync = true,
  })  : _databaseService = databaseService ?? DatabaseService(),
        _auditRepository = auditRepository ?? AuditRepository();

  static String sanitizeCode(String code, String labelEn, String category) {
    var trimmed = code.trim().toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').replaceAll(RegExp(r'_+'), '_');
    if (trimmed.startsWith('_')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('_')) trimmed = trimmed.substring(0, trimmed.length - 1);

    if (trimmed.length <= 1 || trimmed == 'k') {
      var fromLabel = labelEn.trim().toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').replaceAll(RegExp(r'_+'), '_');
      if (fromLabel.startsWith('_')) fromLabel = fromLabel.substring(1);
      if (fromLabel.endsWith('_')) fromLabel = fromLabel.substring(0, fromLabel.length - 1);
      if (fromLabel.length > 1) {
        return fromLabel;
      }
      final prefix = category == 'referral_hospital'
          ? 'hosp'
          : (category == 'medicine'
              ? 'med'
              : (category == 'chief_complaint'
                  ? 'complaint'
                  : (category == 'visit_reason' ? 'reason' : 'diag')));
      return '${prefix}_${DateTime.now().millisecondsSinceEpoch % 100000}';
    }
    return trimmed;
  }

  @override
  Future<List<LookupItemModel>> getAllItems({String? tenantId, String? campId}) async {
    final db = await _databaseService.database;
    final whereClauses = <String>['is_deleted = 0'];
    final whereArgs = <dynamic>[];

    if (tenantId != null && tenantId.isNotEmpty) {
      whereClauses.add("(tenant_id = ? OR tenant_id = 'global' OR tenant_id = 'tenant_default')");
      whereArgs.add(tenantId);
    }

    if (campId != null && campId.isNotEmpty && campId != 'all') {
      whereClauses.add("(camp_id = ? OR ((category = 'visit_reason' OR category = 'chief_complaint') AND (camp_id IS NULL OR camp_id = '')))");
      whereArgs.add(campId);
    }

    final maps = await db.query(
      DatabaseTables.tableLookupItems,
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'category ASC, sort_order ASC, label_en ASC',
    );
    var items = maps.map((m) => LookupItemModel.fromMap(m)).toList();
    if (campId != null && campId.isNotEmpty && campId != 'all') {
      items = items.where((i) => !i.excludedCampIds.contains(campId)).toList();
    }
    return items;
  }

  @override
  Future<List<LookupItemModel>> getItemsByCategory(String category, {String? tenantId, String? campId, bool activeOnly = false}) async {
    final db = await _databaseService.database;
    final whereClauses = <String>['category = ?', 'is_deleted = 0'];
    final whereArgs = <dynamic>[category];

    if (tenantId != null && tenantId.isNotEmpty) {
      whereClauses.add("(tenant_id = ? OR tenant_id = 'global' OR tenant_id = 'tenant_default')");
      whereArgs.add(tenantId);
    }

    if (campId != null && campId.isNotEmpty && campId != 'all') {
      if (category == 'visit_reason' || category == 'chief_complaint') {
        whereClauses.add("(camp_id = ? OR camp_id IS NULL OR camp_id = '')");
      } else {
        whereClauses.add("camp_id = ?");
      }
      whereArgs.add(campId);
    }

    if (activeOnly) {
      whereClauses.add('is_active = 1');
    }

    final maps = await db.query(
      DatabaseTables.tableLookupItems,
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'sort_order ASC, label_en ASC',
    );
    var items = maps.map((m) => LookupItemModel.fromMap(m)).toList();
    if (campId != null && campId.isNotEmpty && campId != 'all') {
      items = items.where((i) => !i.excludedCampIds.contains(campId)).toList();
    }
    return items;
  }

  @override
  Future<LookupItemModel> addItem(
    LookupItemModel item, {
    required String userId,
    required String userName,
    required String deviceId,
  }) async {
    final db = await _databaseService.database;
    final id = item.id.isEmpty ? 'lookup-${_uuid.v4().substring(0, 8)}' : item.id;
    final cleanCode = sanitizeCode(item.code, item.labelEn, item.category);
    final newItem = item.copyWith(id: id, code: cleanCode, isDeleted: false);

    final map = newItem.toMap();
    map['is_synced'] = 0;
    map['updated_at'] = DateTime.now().toIso8601String();

    await db.insert(
      DatabaseTables.tableLookupItems,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _auditRepository.logActivity(
      userId: userId,
      userName: userName,
      userRole: AppConstants.roleSuperAdmin,
      action: AppConstants.auditActionLookupAdd,
      entityType: 'LookupItem',
      entityId: newItem.id,
      detailsJson: '{"category":"${newItem.category}","code":"${newItem.code}","labelEn":"${newItem.labelEn}","tenantId":"${newItem.tenantId}"}',
      deviceId: deviceId,
    );

    // Auto-push to central server (fire-and-forget)
    if (_enableCentralSync) unawaited(_pushLookupToServer(newItem));

    return newItem;
  }

  @override
  Future<LookupItemModel> updateItem(
    LookupItemModel item, {
    required String userId,
    required String userName,
    required String deviceId,
  }) async {
    final db = await _databaseService.database;
    final cleanCode = sanitizeCode(item.code, item.labelEn, item.category);
    final updatedItem = item.copyWith(code: cleanCode);

    final map = updatedItem.toMap();
    map['is_synced'] = 0;
    map['updated_at'] = DateTime.now().toIso8601String();

    await db.update(
      DatabaseTables.tableLookupItems,
      map,
      where: 'id = ?',
      whereArgs: [updatedItem.id],
    );

    await _auditRepository.logActivity(
      userId: userId,
      userName: userName,
      userRole: AppConstants.roleSuperAdmin,
      action: AppConstants.auditActionLookupUpdate,
      entityType: 'LookupItem',
      entityId: updatedItem.id,
      detailsJson: '{"category":"${updatedItem.category}","code":"${updatedItem.code}","labelEn":"${updatedItem.labelEn}"}',
      deviceId: deviceId,
    );

    // Auto-push to central server (fire-and-forget)
    if (_enableCentralSync) unawaited(_pushLookupToServer(updatedItem));

    return updatedItem;
  }

  @override
  Future<bool> toggleItemStatus(
    String id,
    bool isActive, {
    required String userId,
    required String userName,
    required String deviceId,
    String? campId,
  }) async {
    final db = await _databaseService.database;

    // If campId is specified, check if item is global
    if (campId != null && campId.isNotEmpty && campId != 'all') {
      final rows = await db.query(
        DatabaseTables.tableLookupItems,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final existingItem = LookupItemModel.fromMap(rows.first);
        if (existingItem.campId != campId) {
          // Global default item: toggling off in a specific camp excludes it for that camp
          if (!isActive) {
            if (!existingItem.excludedCampIds.contains(campId)) {
              final updatedExcluded = [...existingItem.excludedCampIds, campId];
              final updatedItem = existingItem.copyWith(excludedCampIds: updatedExcluded);
              await updateItem(updatedItem, userId: userId, userName: userName, deviceId: deviceId);
            }
            return true;
          } else {
            // Re-enabling in camp removes camp from excludedCampIds
            final updatedExcluded = existingItem.excludedCampIds.where((c) => c != campId).toList();
            final updatedItem = existingItem.copyWith(excludedCampIds: updatedExcluded);
            await updateItem(updatedItem, userId: userId, userName: userName, deviceId: deviceId);
            return true;
          }
        }
      }
    }

    final count = await db.update(
      DatabaseTables.tableLookupItems,
      {
        'is_active': isActive ? 1 : 0,
        'is_synced': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    if (count > 0) {
      await _auditRepository.logActivity(
        userId: userId,
        userName: userName,
        userRole: AppConstants.roleSuperAdmin,
        action: AppConstants.auditActionLookupToggle,
        entityType: 'LookupItem',
        entityId: id,
        detailsJson: '{"isActive":$isActive}',
        deviceId: deviceId,
      );
      // Auto-push status change to central server
      final rows = await db.query(
        DatabaseTables.tableLookupItems,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty && _enableCentralSync) unawaited(_pushLookupToServer(LookupItemModel.fromMap(rows.first)));
      return true;
    }
    return false;
  }

  @override
  Future<bool> deleteItem(
    String id, {
    required String userId,
    required String userName,
    required String deviceId,
    String? campId,
  }) async {
    final db = await _databaseService.database;

    // If campId is specified, check if the item is camp-specific or global
    if (campId != null && campId.isNotEmpty && campId != 'all') {
      final rows = await db.query(
        DatabaseTables.tableLookupItems,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final existingItem = LookupItemModel.fromMap(rows.first);
        if (existingItem.campId == campId) {
          // Item was created specifically for this camp -> permanently delete from DB
          final count = await db.delete(
            DatabaseTables.tableLookupItems,
            where: 'id = ?',
            whereArgs: [id],
          );
          if (count > 0) {
            await _auditRepository.logActivity(
              userId: userId,
              userName: userName,
              userRole: AppConstants.roleSuperAdmin,
              action: AppConstants.auditActionLookupDelete,
              entityType: 'LookupItem',
              entityId: id,
              detailsJson: '{"deletedId":"$id","campId":"$campId"}',
              deviceId: deviceId,
            );
            if (_enableCentralSync) unawaited(_pushLookupDeleteToServer(id));
            return true;
          }
          return false;
        } else {
          // Item is a Global Default -> DO NOT DELETE GLOBALLY! Exclude from this camp only.
          if (!existingItem.excludedCampIds.contains(campId)) {
            final updatedExcluded = [...existingItem.excludedCampIds, campId];
            final updatedItem = existingItem.copyWith(excludedCampIds: updatedExcluded);
            await updateItem(updatedItem, userId: userId, userName: userName, deviceId: deviceId);
            await _auditRepository.logActivity(
              userId: userId,
              userName: userName,
              userRole: AppConstants.roleSuperAdmin,
              action: 'LOOKUP_EXCLUDE_FROM_CAMP',
              entityType: 'LookupItem',
              entityId: id,
              detailsJson: '{"excludedFromCamp":"$campId","labelEn":"${existingItem.labelEn}"}',
              deviceId: deviceId,
            );
            return true;
          }
          return true;
        }
      }
    }

    // Global deletion (campId == null or 'all')
    final count = await db.delete(
      DatabaseTables.tableLookupItems,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (count > 0) {
      await _auditRepository.logActivity(
        userId: userId,
        userName: userName,
        userRole: AppConstants.roleSuperAdmin,
        action: AppConstants.auditActionLookupDelete,
        entityType: 'LookupItem',
        entityId: id,
        detailsJson: '{"deletedId":"$id"}',
        deviceId: deviceId,
      );
      // Notify server of deletion by pushing a tombstone item
      if (_enableCentralSync) unawaited(_pushLookupDeleteToServer(id));
      return true;
    }
    return false;
  }

  @override
  Future<bool> restoreItemToCamp(
    String id, {
    required String campId,
    required String userId,
    required String userName,
    required String deviceId,
  }) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      DatabaseTables.tableLookupItems,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final existingItem = LookupItemModel.fromMap(rows.first);
      if (existingItem.excludedCampIds.contains(campId)) {
        final updatedExcluded = existingItem.excludedCampIds.where((c) => c != campId).toList();
        final updatedItem = existingItem.copyWith(excludedCampIds: updatedExcluded);
        await updateItem(updatedItem, userId: userId, userName: userName, deviceId: deviceId);
        await _auditRepository.logActivity(
          userId: userId,
          userName: userName,
          userRole: AppConstants.roleSuperAdmin,
          action: 'LOOKUP_RESTORE_TO_CAMP',
          entityType: 'LookupItem',
          entityId: id,
          detailsJson: '{"restoredToCamp":"$campId","labelEn":"${existingItem.labelEn}"}',
          deviceId: deviceId,
        );
        return true;
      }
    }
    return false;
  }

  /// Fire-and-forget: push a lookup item to the central server.
  Future<void> _pushLookupToServer(LookupItemModel item) async {
    try {
      final apiService = HttpCentralApiService();
      if (!apiService.isConfigured || HttpCentralApiService.isServerCooldownActive) return;
      final payload = SyncPushPayload(
        deviceId: 'dev-auto',
        generatedAt: DateTime.now(),
        lookupItems: [item],
      );
      final res = await apiService.pushDelta(payload);
      if (res.success) {
        final db = await _databaseService.database;
        await db.rawUpdate(
          'UPDATE ${DatabaseTables.tableLookupItems} SET is_synced = 1 WHERE id = ?',
          [item.id],
        );
      }
    } catch (e) { debugPrint('[LookupRepo] Central sync error: $e'); }
  }

  /// Fire-and-forget: notify server that a lookup item was deleted.
  Future<void> _pushLookupDeleteToServer(String id) async {
    try {
      final apiService = HttpCentralApiService();
      if (!apiService.isConfigured || HttpCentralApiService.isServerCooldownActive) return;
      // Push a tombstone with is_deleted=1
      final tombstone = LookupItemModel(
        id: id,
        category: 'deleted',
        code: 'deleted',
        labelEn: 'deleted',
        labelNe: 'deleted',
        isDeleted: true,
        isActive: false,
      );
      final payload = SyncPushPayload(
        deviceId: 'dev-auto',
        generatedAt: DateTime.now(),
        lookupItems: [tombstone],
      );
      await apiService.pushDelta(payload);
    } catch (e) { debugPrint('[LookupRepo] Central sync error: $e'); }
  }

  @override
  // Auto-seeding removed by design: each camp starts with empty lists.
  // Admins manually add medicines/diagnoses/hospitals via Master Config per camp.
  Future<void> ensureDefaultsSeeded({String? tenantId}) async {}

  /// Backfill sub_category for any existing items that are missing it.
  /// Safe to call at any time — only runs SQL UPDATEs, never inserts.
  @override
  Future<void> backfillSubCategories() async {
    final db = await _databaseService.database;
    try {
      for (final entry in ClinicalConstants.diagnosisCategoryMap.entries) {
        await db.update(
          DatabaseTables.tableLookupItems,
          {'sub_category': entry.value},
          where: "category = ? AND label_en = ? AND (sub_category IS NULL OR sub_category = '')",
          whereArgs: ['diagnosis', entry.key],
        );
      }
      for (final entry in ClinicalConstants.medicationCategoryMap.entries) {
        await db.update(
          DatabaseTables.tableLookupItems,
          {'sub_category': entry.value},
          where: "category = ? AND label_en = ? AND (sub_category IS NULL OR sub_category = '')",
          whereArgs: ['medicine', entry.key],
        );
      }
      await cleanupLegacyAutoSeededDefaults();
    } catch (e) {
      debugPrint('[LookupRepo] backfillSubCategories error: $e');
    }
  }

  /// Cleans up any legacy auto-seeded defaults that have no camp assigned,
  /// ensuring camps start with clean, empty lists.
  Future<void> cleanupLegacyAutoSeededDefaults() async {
    final db = await _databaseService.database;
    try {
      await db.delete(
        DatabaseTables.tableLookupItems,
        where: "(id LIKE 'diag-%' OR id LIKE 'med-%') AND (camp_id IS NULL OR camp_id = '')",
      );
    } catch (e) {
      debugPrint('[LookupRepo] cleanupLegacyAutoSeededDefaults error: $e');
    }
  }
}
