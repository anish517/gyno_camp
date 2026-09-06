import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../models/camp_model.dart';
import 'audit_repository.dart';

abstract class ICampRepository {
  Future<List<CampModel>> getAllCamps();
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
  final Uuid _uuid = const Uuid();

  CampRepository({
    DatabaseService? databaseService,
    AuditRepository? auditRepository,
  })  : _databaseService = databaseService ?? DatabaseService(),
        _auditRepository = auditRepository ?? AuditRepository();

  @override
  Future<List<CampModel>> getAllCamps() async {
    final db = await _databaseService.database;
    final maps = await db.rawQuery('''
      SELECT c.*,
             COALESCE((SELECT COUNT(*) FROM ${DatabaseTables.tablePatients} p WHERE p.camp_id = c.id), 0) AS live_patient_count
      FROM ${DatabaseTables.tableCamps} c
      ORDER BY c.start_date DESC
    ''');
    return maps.map((m) {
      final map = Map<String, dynamic>.from(m);
      if (map.containsKey('live_patient_count') && map['live_patient_count'] != null) {
        map['total_patients_registered'] = map['live_patient_count'];
      }
      return CampModel.fromMap(map);
    }).toList();
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
    if (maps.isEmpty) return null;
    final map = Map<String, dynamic>.from(maps.first);
    if (map.containsKey('live_patient_count') && map['live_patient_count'] != null) {
      map['total_patients_registered'] = map['live_patient_count'];
    }
    return CampModel.fromMap(map);
  }

  @override
  Future<CampModel?> getActiveCamp() async {
    final db = await _databaseService.database;
    final maps = await db.rawQuery('''
      SELECT c.*,
             COALESCE((SELECT COUNT(*) FROM ${DatabaseTables.tablePatients} p WHERE p.camp_id = c.id), 0) AS live_patient_count
      FROM ${DatabaseTables.tableCamps} c
      WHERE c.status = ?
      LIMIT 1
    ''', [AppConstants.campStatusOpen]);
    if (maps.isEmpty) return null;
    final map = Map<String, dynamic>.from(maps.first);
    if (map.containsKey('live_patient_count') && map['live_patient_count'] != null) {
      map['total_patients_registered'] = map['live_patient_count'];
    }
    return CampModel.fromMap(map);
  }

  @override
  Future<CampModel> createCamp(CampModel camp, {required String createdByUserId, required String deviceId}) async {
    final db = await _databaseService.database;
    final campId = camp.id.isEmpty ? 'camp-${_uuid.v4().substring(0, 8)}' : camp.id;
    final newCamp = camp.copyWith(id: campId, createdAt: DateTime.now());

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

    return newCamp;
  }

  @override
  Future<bool> openCamp(String campId, {required String adminUserId, required String deviceId}) async {
    final camp = await getCampById(campId);
    if (camp == null) return false;

    final db = await _databaseService.database;
    final now = DateTime.now();

    // Enforce single active camp rule: close any other currently open camp
    final activeCamp = await getActiveCamp();
    if (activeCamp != null && activeCamp.id != campId) {
      await closeCamp(activeCamp.id, adminUserId: adminUserId, deviceId: deviceId);
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

    return updated;
  }

  @override
  Future<bool> deleteCamp(String campId, {required String adminUserId, required String deviceId}) async {
    final camp = await getCampById(campId);
    if (camp == null) return false;

    final db = await _databaseService.database;
    await db.delete(
      DatabaseTables.tableCamps,
      where: 'id = ?',
      whereArgs: [campId],
    );

    await _auditRepository.logActivity(
      userId: adminUserId,
      userName: 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: 'CAMP_DELETED',
      entityType: 'Camp',
      entityId: campId,
      detailsJson: '{"campCode":"${camp.campCode}"}',
      deviceId: deviceId,
    );

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
