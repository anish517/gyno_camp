import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../models/audit_log_model.dart';

abstract class IAuditRepository {
  Future<void> logActivity({
    required String userId,
    required String userName,
    required String userRole,
    required String action,
    required String entityType,
    String? entityId,
    required String detailsJson,
    required String deviceId,
  });
  Future<List<AuditLogModel>> getRecentLogs({int limit = 50});
  Future<List<AuditLogModel>> getLogsByUser(String userId, {int limit = 50});
}

class AuditRepository implements IAuditRepository {
  final DatabaseService _databaseService;
  final Uuid _uuid = const Uuid();
  String? _lastLogHash;

  AuditRepository({DatabaseService? databaseService})
      : _databaseService = databaseService ?? DatabaseService();

  @override
  Future<void> logActivity({
    required String userId,
    required String userName,
    required String userRole,
    required String action,
    required String entityType,
    String? entityId,
    required String detailsJson,
    required String deviceId,
  }) async {
    final db = await _databaseService.database;
    final logId = _uuid.v4();

    final log = AuditLogModel.create(
      id: logId,
      userId: userId,
      userName: userName,
      userRole: userRole,
      action: action,
      entityType: entityType,
      entityId: entityId,
      detailsJson: detailsJson,
      deviceId: deviceId,
      previousHash: _lastLogHash,
    );

    _lastLogHash = log.logHash;

    await db.insert(
      DatabaseTables.tableAuditLogs,
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<AuditLogModel>> getRecentLogs({int limit = 50}) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      DatabaseTables.tableAuditLogs,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return maps.map((m) => AuditLogModel.fromMap(m)).toList();
  }

  @override
  Future<List<AuditLogModel>> getLogsByUser(String userId, {int limit = 50}) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      DatabaseTables.tableAuditLogs,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return maps.map((m) => AuditLogModel.fromMap(m)).toList();
  }
}
