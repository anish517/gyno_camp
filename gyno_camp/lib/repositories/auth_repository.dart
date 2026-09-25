import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../core/security/security_service.dart';
import '../core/services/http_central_api_service.dart';
import '../core/services/session_service.dart';
import '../models/user_model.dart';
import 'audit_repository.dart';

abstract class IAuthRepository {
  Future<List<UserModel>> getAllUsers({bool includeInactive = false});
  Future<UserModel?> getUserById(String id);
  Future<UserModel?> getUserByEmail(String email);
  Future<UserModel> createUser({
    required UserModel user,
    required String adminUserId,
    required String deviceId,
  });
  Future<UserModel> updateUser({
    required UserModel user,
    required String adminUserId,
    required String deviceId,
  });
  Future<void> deleteUser({
    required String userId,
    required String adminUserId,
    required String deviceId,
  });
  Future<UserModel?> login({
    required String email,
    String? password,
    required String deviceId,
  });
  Future<UserModel?> loginAsRole({
    required UserRole role,
    required String deviceId,
  });
  Future<void> logout({required String deviceId});
  Future<List<String>> getValidCampsForUser(List<String> assignedCampIds);
  UserModel? get currentUser;
  void setCurrentUser(UserModel? user);
}

class AuthRepository implements IAuthRepository {
  final DatabaseService _databaseService;
  final AuditRepository _auditRepository;
  final bool enableCentralSync;
  UserModel? _currentUser;

  AuthRepository({
    DatabaseService? databaseService,
    AuditRepository? auditRepository,
    this.enableCentralSync = true,
  }) : _databaseService = databaseService ?? DatabaseService(),
       _auditRepository = auditRepository ?? AuditRepository();

  @override
  UserModel? get currentUser => _currentUser;

  @override
  void setCurrentUser(UserModel? user) {
    _currentUser = user;
  }

  Future<void> _upsertUserPreservingCredentials(DatabaseExecutor db, UserModel u) async {
    final existing = await db.query(
      DatabaseTables.tableUsers,
      columns: ['password_hash', 'pin_hash', 'updated_at'],
      where: 'id = ?',
      whereArgs: [u.id],
      limit: 1,
    );
    final map = u.toMap();
    if (existing.isNotEmpty) {
      final row = existing.first;
      final localPass = row['password_hash'] as String?;
      final localPin = row['pin_hash'] as String?;
      final localUpdatedAt = row['updated_at'] as String?;

      DateTime? localTs;
      DateTime? incomingTs;
      try {
        if (localUpdatedAt != null && localUpdatedAt.isNotEmpty) {
          localTs = DateTime.parse(localUpdatedAt).toUtc();
        }
        final incomingUpdatedAt = map['updated_at'] as String?;
        if (incomingUpdatedAt != null && incomingUpdatedAt.isNotEmpty) {
          incomingTs = DateTime.parse(incomingUpdatedAt).toUtc();
        }
      } catch (_) {}

      // If local record has a timestamp and is newer than (or incoming has no timestamp):
      // local credentials win!
      final localIsNewer = localTs != null && (incomingTs == null || localTs.isAfter(incomingTs));

      final incomingPassEmpty = map['password_hash'] == null || map['password_hash'].toString().isEmpty;
      final incomingPinEmpty = map['pin_hash'] == null || map['pin_hash'].toString().isEmpty;

      if (localIsNewer || (incomingPassEmpty && localPass != null && localPass.isNotEmpty)) {
        map['password_hash'] = localPass;
      }
      if (localIsNewer || (incomingPinEmpty && localPin != null && localPin.isNotEmpty)) {
        map['pin_hash'] = localPin;
      }
      if (localIsNewer && localUpdatedAt != null) {
        map['updated_at'] = localUpdatedAt;
      }
    }
    await db.insert(
      DatabaseTables.tableUsers,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<UserModel>> getAllUsers({bool includeInactive = false}) async {
    final db = await _databaseService.database;

    // Load tombstoned deleted user IDs to prevent deleted users from being resurrected
    Set<String> deletedUserIds = {};
    try {
      final meta = await db.query(
        DatabaseTables.tableMetadata,
        where: "key = 'deleted_user_ids'",
      );
      if (meta.isNotEmpty) {
        final val = meta.first['value'] as String? ?? '';
        deletedUserIds = val.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
      }
    } catch (e) { debugPrint('[AuthRepo] Central sync error: $e'); }

    // 1. Merge latest users from Central Cloud if available
    if (enableCentralSync && HttpCentralApiService.isServerConfigured) {
      try {
        final centralUsers = await HttpCentralApiService().fetchCentralUsers();
        if (centralUsers.isNotEmpty) {
          for (final u in centralUsers) {
            if (deletedUserIds.contains(u.id)) {
              // User was deleted locally; inform central cloud and skip
              HttpCentralApiService().deleteCentralUser(u.id);
              continue;
            }
            await _upsertUserPreservingCredentials(db, u);
          }
        }
      } catch (e) { debugPrint('[AuthRepo] Central sync error: $e'); }
    }

    final maps = await db.query(
      DatabaseTables.tableUsers,
      where: includeInactive ? null : 'is_active = ?',
      whereArgs: includeInactive ? null : [1],
      orderBy: 'name ASC',
    );

    final savedOrg = SessionService.current?.getOrganizationName();
    return maps
        .map((m) => UserModel.fromMap(m))
        .where((u) => !deletedUserIds.contains(u.id))
        .map((u) {
          if (savedOrg != null &&
              savedOrg.trim().isNotEmpty &&
              u.isSuperAdmin &&
              (u.tenantName == 'Outreach Health Center' ||
                  u.tenantName == 'Nepal Health Outreach Network')) {
            return u.copyWith(tenantName: savedOrg);
          }
          return u;
        })
        .toList();
  }

  @override
  Future<UserModel?> getUserById(String id) async {
    final db = await _databaseService.database;

    // Check tombstone
    try {
      final meta = await db.query(
        DatabaseTables.tableMetadata,
        where: "key = 'deleted_user_ids'",
      );
      if (meta.isNotEmpty) {
        final val = meta.first['value'] as String? ?? '';
        final deletedUserIds = val.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
        if (deletedUserIds.contains(id)) return null;
      }
    } catch (e) { debugPrint('[AuthRepo] Central sync error: $e'); }

    final maps = await db.query(
      DatabaseTables.tableUsers,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      final user = UserModel.fromMap(maps.first);
      final savedOrg = SessionService.current?.getOrganizationName();
      if (savedOrg != null &&
          savedOrg.trim().isNotEmpty &&
          user.isSuperAdmin &&
          (user.tenantName == 'Outreach Health Center' ||
              user.tenantName == 'Nepal Health Outreach Network')) {
        return user.copyWith(tenantName: savedOrg);
      }
      return user;
    }

    // Try central cloud if enabled
    if (enableCentralSync && HttpCentralApiService.isServerConfigured) {
      try {
        final centralUsers = await HttpCentralApiService().fetchCentralUsers();
        for (final u in centralUsers) {
          await _upsertUserPreservingCredentials(db, u);
        }
        final refreshed = await db.query(
          DatabaseTables.tableUsers,
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (refreshed.isNotEmpty) {
          final user = UserModel.fromMap(refreshed.first);
          final savedOrg = SessionService.current?.getOrganizationName();
          if (savedOrg != null &&
              savedOrg.trim().isNotEmpty &&
              user.isSuperAdmin &&
              (user.tenantName == 'Outreach Health Center' ||
                  user.tenantName == 'Nepal Health Outreach Network')) {
            return user.copyWith(tenantName: savedOrg);
          }
          return user;
        }
      } catch (e) { debugPrint('[AuthRepo] Central sync error: $e'); }
    }

    return null;
  }

  @override
  Future<UserModel?> getUserByEmail(String email) async {
    final db = await _databaseService.database;
    final trimmed = email.trim();
    final lower = trimmed.toLowerCase();
    final isSuperAdminAlias = lower == 'admin' ||
        lower == 'superadmin' ||
        lower == 'admin@gynocamp.org' ||
        lower == 'super administrator' ||
        lower == 'root';
    
    final maps = await db.query(
      DatabaseTables.tableUsers,
      where: isSuperAdminAlias
          ? "LOWER(email) = ? OR phone = ? OR LOWER(email) = 'admin@gynocamp.org' OR id = 'usr-superadmin-01'"
          : 'LOWER(email) = ? OR phone = ?',
      whereArgs: [lower, trimmed],
      limit: 1,
    );
    if (maps.isNotEmpty) return UserModel.fromMap(maps.first);

    // Try central cloud for newly registered staff from other devices
    if (enableCentralSync && HttpCentralApiService.isServerConfigured) {
      try {
        final centralUsers = await HttpCentralApiService().fetchCentralUsers();
        for (final u in centralUsers) {
          await _upsertUserPreservingCredentials(db, u);
        }
        final refreshed = await db.query(
          DatabaseTables.tableUsers,
          where: isSuperAdminAlias
              ? "LOWER(email) = ? OR phone = ? OR LOWER(email) = 'admin@gynocamp.org' OR id = 'usr-superadmin-01'"
              : 'LOWER(email) = ? OR phone = ?',
          whereArgs: [lower, trimmed],
          limit: 1,
        );
        if (refreshed.isNotEmpty) return UserModel.fromMap(refreshed.first);
      } catch (e) { debugPrint('[AuthRepo] Central sync error: $e'); }
    }

    return null;
  }

  @override
  Future<UserModel> createUser({
    required UserModel user,
    required String adminUserId,
    required String deviceId,
  }) async {
    final db = await _databaseService.database;

    // Remove from deleted_user_ids tombstone if re-created
    try {
      final meta = await db.query(
        DatabaseTables.tableMetadata,
        where: "key = 'deleted_user_ids'",
      );
      if (meta.isNotEmpty) {
        final val = meta.first['value'] as String? ?? '';
        final remaining = val
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && s != user.id)
            .toList();
        await db.insert(
          DatabaseTables.tableMetadata,
          {
            'key': 'deleted_user_ids',
            'value': remaining.join(','),
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (e) { debugPrint('[AuthRepo] Central sync error: $e'); }

    final createdUser = user.copyWith(updatedAt: user.updatedAt ?? DateTime.now());
    await db.insert(
      DatabaseTables.tableUsers,
      createdUser.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _auditRepository.logActivity(
      userId: adminUserId,
      userName: _currentUser?.name ?? 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: 'USER_REGISTERED',
      entityType: 'User',
      entityId: createdUser.id,
      detailsJson:
          '{"name":"${createdUser.name}","email":"${createdUser.email}","role":"${createdUser.role.toDbString()}"}',
      deviceId: deviceId,
    );

    if (enableCentralSync) {
      try {
        await HttpCentralApiService().broadcastUser(createdUser);
      } catch (e) { debugPrint('[AuthRepo] Central sync error: $e'); }
    }

    return createdUser;
  }

  @override
  Future<UserModel> updateUser({
    required UserModel user,
    required String adminUserId,
    required String deviceId,
  }) async {
    final now = DateTime.now();
    final updatedWithTimestamp = user.copyWith(updatedAt: now);
    final db = await _databaseService.database;
    await db.update(
      DatabaseTables.tableUsers,
      updatedWithTimestamp.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );

    // If organization / tenant name was updated, persist across SaaS session and camps
    if (user.tenantName.trim().isNotEmpty && user.tenantName != 'Outreach Health Center') {
      await SessionService.current?.saveOrganizationName(user.tenantName.trim());
      try {
        await db.insert(
          DatabaseTables.tableMetadata,
          {
            'key': 'saas_organization_name',
            'value': user.tenantName.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await db.update(
          DatabaseTables.tableCamps,
          {'organization_name': user.tenantName.trim()},
          where: 'tenant_id = ?',
          whereArgs: [user.tenantId],
        );
      } catch (e) { debugPrint('[AuthRepo] Central sync error: $e'); }
    }

    // Synchronize camp assigned_staff_ids with user.assignedCampIds (Issue 1)
    try {
      final campRows = await db.query(DatabaseTables.tableCamps);
      for (final r in campRows) {
        final cId = r['id'] as String;
        final rawStaff = (r['assigned_staff_ids'] as String? ?? '')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet();
        bool changed = false;
        if (user.assignedCampIds.contains(cId)) {
          if (!rawStaff.contains(user.id)) {
            rawStaff.add(user.id);
            changed = true;
          }
        } else {
          if (rawStaff.contains(user.id)) {
            rawStaff.remove(user.id);
            changed = true;
          }
        }
        if (changed) {
          await db.update(
            DatabaseTables.tableCamps,
            {'assigned_staff_ids': rawStaff.join(',')},
            where: 'id = ?',
            whereArgs: [cId],
          );
        }
      }
    } catch (e) { debugPrint('[AuthRepo] Central sync error: $e'); }

    await _auditRepository.logActivity(
      userId: adminUserId,
      userName: _currentUser?.name ?? 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: 'USER_UPDATED',
      entityType: 'User',
      entityId: user.id,
      detailsJson:
          '{"name":"${user.name}","email":"${user.email}","role":"${user.role.toDbString()}","isActive":${user.isActive}}',
      deviceId: deviceId,
    );

    if (enableCentralSync) {
      try {
        await HttpCentralApiService().broadcastUser(updatedWithTimestamp);
      } catch (e) { debugPrint('[AuthRepo] Central sync error: $e'); }
    }

    if (_currentUser?.id == updatedWithTimestamp.id) {
      _currentUser = updatedWithTimestamp;
    }
    return updatedWithTimestamp;
  }

  @override
  Future<void> deleteUser({
    required String userId,
    required String adminUserId,
    required String deviceId,
  }) async {
    if (userId == adminUserId) {
      throw Exception('Cannot delete the active logged-in administrator.');
    }
    if (userId == 'usr-superadmin-01') {
      throw Exception('Cannot delete the root system administrator.');
    }

    final db = await _databaseService.database;
    final target = await getUserById(userId);
    if (target == null) return;

    await db.delete(
      DatabaseTables.tableUsers,
      where: 'id = ?',
      whereArgs: [userId],
    );

    // Save tombstone in app_metadata
    try {
      final meta = await db.query(
        DatabaseTables.tableMetadata,
        where: "key = 'deleted_user_ids'",
      );
      final existing = meta.isNotEmpty
          ? (meta.first['value'] as String? ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet()
          : <String>{};
      existing.add(userId);
      await db.insert(
        DatabaseTables.tableMetadata,
        {
          'key': 'deleted_user_ids',
          'value': existing.join(','),
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) { debugPrint('[AuthRepo] Central sync error: $e'); }

    // Tell Central Cloud Server to delete user immediately
    if (enableCentralSync) {
      try {
        await HttpCentralApiService().deleteCentralUser(userId);
      } catch (e) { debugPrint('[AuthRepo] Central sync error: $e'); }
    }

    await _auditRepository.logActivity(
      userId: adminUserId,
      userName: _currentUser?.name ?? 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: 'USER_DELETED',
      entityType: 'User',
      entityId: userId,
      detailsJson:
          '{"name":"${target.name}","email":"${target.email}","role":"${target.role.toDbString()}"}',
      deviceId: deviceId,
    );
  }

  @override
  Future<List<String>> getValidCampsForUser(List<String> assignedCampIds) async {
    if (assignedCampIds.isEmpty) return [];
    final db = await _databaseService.database;
    final placeholders = List.filled(assignedCampIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT id FROM ${DatabaseTables.tableCamps} WHERE id IN ($placeholders)',
      assignedCampIds,
    );
    return rows.map((r) => r['id'] as String).toList();
  }

  @override
  Future<UserModel?> login({
    required String email,
    String? password,
    required String deviceId,
  }) async {
    final user = await getUserByEmail(email);
    if (user == null || !user.isActive) return null;

    final hasCredentials = (user.passwordHash != null && user.passwordHash!.isNotEmpty) ||
        (user.pinHash != null && user.pinHash!.isNotEmpty);

    if (hasCredentials) {
      if (password == null || password.trim().isEmpty) {
        return null;
      }
      final inputHash = SecurityService.hashSha256(password);
      final isPinValid =
          user.pinHash != null &&
          user.pinHash!.isNotEmpty &&
          SecurityService.verifyPin(password, user.pinHash!);
      final isPasswordValid =
          user.passwordHash != null &&
          user.passwordHash!.isNotEmpty &&
          user.passwordHash == inputHash;

      if (!isPasswordValid && !isPinValid) {
        return null;
      }
    }

    final db = await _databaseService.database;
    final now = DateTime.now();
    await db.update(
      DatabaseTables.tableUsers,
      {'last_login_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [user.id],
    );

    _currentUser = user.copyWith(lastLoginAt: now);

    // Record audit trail
    await _auditRepository.logActivity(
      userId: user.id,
      userName: user.name,
      userRole: user.role.toDbString(),
      action: AppConstants.auditActionLogin,
      entityType: 'User',
      entityId: user.id,
      detailsJson: '{"loginMethod":"credentials","email":"${user.email}"}',
      deviceId: deviceId,
    );

    return _currentUser;
  }

  @override
  Future<UserModel?> loginAsRole({
    required UserRole role,
    required String deviceId,
  }) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      DatabaseTables.tableUsers,
      where: 'role = ? AND is_active = 1',
      whereArgs: [role.toDbString()],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    final user = UserModel.fromMap(maps.first);
    final now = DateTime.now();

    await db.update(
      DatabaseTables.tableUsers,
      {'last_login_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [user.id],
    );

    _currentUser = user.copyWith(lastLoginAt: now);

    await _auditRepository.logActivity(
      userId: user.id,
      userName: user.name,
      userRole: user.role.toDbString(),
      action: AppConstants.auditActionLogin,
      entityType: 'User',
      entityId: user.id,
      detailsJson:
          '{"loginMethod":"role_switch","role":"${role.toDbString()}"}',
      deviceId: deviceId,
    );

    return _currentUser;
  }

  @override
  Future<void> logout({required String deviceId}) async {
    if (_currentUser != null) {
      await _auditRepository.logActivity(
        userId: _currentUser!.id,
        userName: _currentUser!.name,
        userRole: _currentUser!.role.toDbString(),
        action: AppConstants.auditActionLogout,
        entityType: 'User',
        entityId: _currentUser!.id,
        detailsJson: '{"event":"logout"}',
        deviceId: deviceId,
      );
    }
    _currentUser = null;
  }
}
