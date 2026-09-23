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
      whereClauses.add("(camp_id = ? OR camp_id IS NULL OR camp_id = '')");
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
      whereClauses.add("(camp_id = ? OR camp_id IS NULL OR camp_id = '')");
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

    await db.insert(
      DatabaseTables.tableLookupItems,
      newItem.toMap(),
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

    await db.update(
      DatabaseTables.tableLookupItems,
      updatedItem.toMap(),
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
      {'is_active': isActive ? 1 : 0},
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
      await apiService.pushDelta(payload);
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
  Future<void> ensureDefaultsSeeded({String? tenantId}) async {
    final db = await _databaseService.database;
    final targetTenant = tenantId ?? 'tenant_default';
    final metaKey = 'lookup_defaults_seeded_$targetTenant';

    // 1. Backfill any existing items missing sub_category first
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
    } catch (e) { debugPrint('[LookupRepo] Central sync error: $e'); }

    // 2. Check one-time seed gate in app_metadata
    try {
      final meta = await db.query(
        DatabaseTables.tableMetadata,
        where: 'key = ?',
        whereArgs: [metaKey],
      );
      if (meta.isNotEmpty) {
        // Defaults have already been seeded. Do not resurrect user deletions!
        return;
      }
    } catch (e) { debugPrint('[LookupRepo] Central sync error: $e'); }

    // 3. Check & seed referral hospitals if empty
    final hospitals = await getItemsByCategory('referral_hospital', tenantId: targetTenant);
    if (hospitals.isEmpty) {
      int idx = 0;
      for (final h in ClinicalConstants.referralHospitals) {
        idx++;
        final cleanCode = h.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        await db.insert(
          DatabaseTables.tableLookupItems,
          {
            'id': 'hosp-$targetTenant-$idx',
            'category': 'referral_hospital',
            'sub_category': 'Referral Centers',
            'code': cleanCode,
            'label_en': h,
            'label_ne': h,
            'is_active': 1,
            'sort_order': idx,
            'tenant_id': targetTenant,
            'is_deleted': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    // 2. Check & seed 21 clinical diagnoses with sub_categories if empty
    final diagnoses = await getItemsByCategory('diagnosis', tenantId: targetTenant);
    if (diagnoses.isEmpty) {
      int idx = 0;
      for (final d in ClinicalConstants.defaultDiagnoses) {
        idx++;
        final cleanCode = d.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        final subCat = ClinicalConstants.diagnosisCategoryMap[d] ?? 'General / Other';
        await db.insert(
          DatabaseTables.tableLookupItems,
          {
            'id': 'diag-$targetTenant-$idx',
            'category': 'diagnosis',
            'sub_category': subCat,
            'code': cleanCode,
            'label_en': d,
            'label_ne': d,
            'is_active': 1,
            'sort_order': idx,
            'tenant_id': targetTenant,
            'is_deleted': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    // 3. Check & seed 10 medications with sub_categories if empty
    final medicines = await getItemsByCategory('medicine', tenantId: targetTenant);
    if (medicines.isEmpty) {
      int idx = 0;
      for (final m in ClinicalConstants.defaultMedications) {
        idx++;
        final cleanCode = m.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        final subCat = ClinicalConstants.medicationCategoryMap[m] ?? 'Other / Custom';
        await db.insert(
          DatabaseTables.tableLookupItems,
          {
            'id': 'med-$targetTenant-$idx',
            'category': 'medicine',
            'sub_category': subCat,
            'code': cleanCode,
            'label_en': m,
            'label_ne': m,
            'is_active': 1,
            'sort_order': idx,
            'tenant_id': targetTenant,
            'is_deleted': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    // 3b. Seed default Visit Reasons from ClinicalConstants.visitReasonOptions
    final existingReasons = await getItemsByCategory('visit_reason', tenantId: targetTenant);
    if (existingReasons.isEmpty) {
      for (final entry in ClinicalConstants.visitReasonOptions.entries) {
        final cleanCode = entry.key.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        final reg = RegExp(r'^(.*?)\s*\((.*?)\)$');
        final match = reg.firstMatch(entry.value);
        final labelEn = match != null ? match.group(1)!.trim() : entry.key;
        final labelNe = match != null ? match.group(2)!.trim() : entry.value;
        await db.insert(
          DatabaseTables.tableLookupItems,
          {
            'id': 'reason-$targetTenant-$cleanCode',
            'category': 'visit_reason',
            'sub_category': 'Reason for Visit',
            'code': cleanCode,
            'label_en': labelEn,
            'label_ne': labelNe,
            'is_active': 1,
            'sort_order': ClinicalConstants.visitReasonOptions.keys.toList().indexOf(entry.key) + 1,
            'tenant_id': targetTenant,
            'is_deleted': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    // 3c. Seed default Chief Complaints (Yellow Form Standard Symptoms)
    final existingComplaints = await getItemsByCategory('chief_complaint', tenantId: targetTenant);
    if (existingComplaints.isEmpty) {
      final defaultComplaints = [
        {'en': 'Lower Abdominal Pain', 'ne': 'तल्लो पेट दुख्ने', 'sub': 'Pelvic & Abdominal'},
        {'en': 'White / Foul Discharge', 'ne': 'सेतो वा गन्हाउने पानी बग्ने', 'sub': 'Infections & Discharge'},
        {'en': 'Pelvic Heaviness', 'ne': 'तल्लो पेट भारी हुने', 'sub': 'Pelvic Floor & Prolapse'},
        {'en': 'Burning Micturition', 'ne': 'पिसाब पोल्ने', 'sub': 'Urinary Symptoms'},
        {'en': 'Urinary Incontinence', 'ne': 'पिसाब चुहिने', 'sub': 'Urinary Symptoms'},
        {'en': 'Dyspareunia', 'ne': 'यौन सम्पर्कमा दुखाई', 'sub': 'Reproductive & Sexual'},
        {'en': 'Coital Bleeding', 'ne': 'सम्पर्कपछि रगत बग्ने', 'sub': 'Bleeding & Neoplasms'},
        {'en': 'Mass Per Vagina', 'ne': 'पाठेघर / मासु खस्ने', 'sub': 'Pelvic Floor & Prolapse'},
        {'en': 'Severe Backache', 'ne': 'कम्मर दुख्ने', 'sub': 'Musculoskeletal & General'},
      ];
      int idx = 0;
      for (final c in defaultComplaints) {
        idx++;
        final cleanCode = c['en']!.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        await db.insert(
          DatabaseTables.tableLookupItems,
          {
            'id': 'complaint-$targetTenant-$idx',
            'category': 'chief_complaint',
            'sub_category': c['sub'],
            'code': cleanCode,
            'label_en': c['en'],
            'label_ne': c['ne'],
            'is_active': 1,
            'sort_order': idx,
            'tenant_id': targetTenant,
            'is_deleted': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    // 4. Persist seed gate marker so deletions remain permanent
    try {
      await db.insert(
        DatabaseTables.tableMetadata,
        {
          'key': metaKey,
          'value': 'true',
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) { debugPrint('[LookupRepo] Central sync error: $e'); }
  }
}
