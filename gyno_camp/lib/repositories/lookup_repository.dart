import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/clinical_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../models/lookup_item_model.dart';
import 'audit_repository.dart';

abstract class ILookupRepository {
  Future<List<LookupItemModel>> getAllItems();
  Future<List<LookupItemModel>> getItemsByCategory(String category, {bool activeOnly = false});
  Future<LookupItemModel> addItem(LookupItemModel item, {required String userId, required String userName, required String deviceId});
  Future<LookupItemModel> updateItem(LookupItemModel item, {required String userId, required String userName, required String deviceId});
  Future<bool> toggleItemStatus(String id, bool isActive, {required String userId, required String userName, required String deviceId});
  Future<bool> deleteItem(String id, {required String userId, required String userName, required String deviceId});
  Future<void> ensureDefaultsSeeded();
}

class LookupRepository implements ILookupRepository {
  final DatabaseService _databaseService;
  final AuditRepository _auditRepository;
  final Uuid _uuid = const Uuid();

  LookupRepository({
    DatabaseService? databaseService,
    AuditRepository? auditRepository,
  })  : _databaseService = databaseService ?? DatabaseService(),
        _auditRepository = auditRepository ?? AuditRepository();

  @override
  Future<List<LookupItemModel>> getAllItems() async {
    final db = await _databaseService.database;
    final maps = await db.query(
      DatabaseTables.tableLookupItems,
      orderBy: 'category ASC, sort_order ASC, label_en ASC',
    );
    return maps.map((m) => LookupItemModel.fromMap(m)).toList();
  }

  @override
  Future<List<LookupItemModel>> getItemsByCategory(String category, {bool activeOnly = false}) async {
    final db = await _databaseService.database;
    final whereClauses = <String>['category = ?'];
    final whereArgs = <dynamic>[category];

    if (activeOnly) {
      whereClauses.add('is_active = 1');
    }

    final maps = await db.query(
      DatabaseTables.tableLookupItems,
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'sort_order ASC, label_en ASC',
    );
    return maps.map((m) => LookupItemModel.fromMap(m)).toList();
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
    final newItem = item.copyWith(id: id);

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
      detailsJson: '{"category":"${newItem.category}","code":"${newItem.code}","labelEn":"${newItem.labelEn}"}',
      deviceId: deviceId,
    );

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
    await db.update(
      DatabaseTables.tableLookupItems,
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );

    await _auditRepository.logActivity(
      userId: userId,
      userName: userName,
      userRole: AppConstants.roleSuperAdmin,
      action: AppConstants.auditActionLookupUpdate,
      entityType: 'LookupItem',
      entityId: item.id,
      detailsJson: '{"category":"${item.category}","code":"${item.code}","labelEn":"${item.labelEn}"}',
      deviceId: deviceId,
    );

    return item;
  }

  @override
  Future<bool> toggleItemStatus(
    String id,
    bool isActive, {
    required String userId,
    required String userName,
    required String deviceId,
  }) async {
    final db = await _databaseService.database;
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
  }) async {
    final db = await _databaseService.database;
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
      return true;
    }
    return false;
  }

  @override
  Future<void> ensureDefaultsSeeded() async {
    final db = await _databaseService.database;
    final hospitals = await getItemsByCategory('referral_hospital');
    if (hospitals.isEmpty) {
      int idx = 0;
      for (final h in ClinicalConstants.referralHospitals) {
        idx++;
        await db.insert(
          DatabaseTables.tableLookupItems,
          {
            'id': 'hosp-$idx',
            'category': 'referral_hospital',
            'code': h.toLowerCase().replaceAll(' ', '_'),
            'label_en': h,
            'label_ne': h,
            'is_active': 1,
            'sort_order': idx,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }
}
