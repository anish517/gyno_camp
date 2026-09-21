import 'package:sqflite/sqflite.dart';

import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../core/security/security_service.dart';
import '../core/services/http_central_api_service.dart';
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

  @override
  Future<List<UserModel>> getAllUsers({bool includeInactive = false}) async {
    final db = await _databaseService.database;

    // 1. Merge latest users from Central Cloud if available
    if (enableCentralSync && HttpCentralApiService.isServerConfigured) {
      try {
        final centralUsers = await HttpCentralApiService().fetchCentralUsers();
        if (centralUsers.isNotEmpty) {
          for (final u in centralUsers) {
            await db.insert(
              DatabaseTables.tableUsers,
              u.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      } catch (_) {}
    }

    final maps = await db.query(
      DatabaseTables.tableUsers,
      where: includeInactive ? null : 'is_active = ?',
      whereArgs: includeInactive ? null : [1],
      orderBy: 'name ASC',
    );
    return maps.map((m) => UserModel.fromMap(m)).toList();
  }

  @override
  Future<UserModel?> getUserById(String id) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      DatabaseTables.tableUsers,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) return UserModel.fromMap(maps.first);

    // Try central cloud if enabled
    if (enableCentralSync && HttpCentralApiService.isServerConfigured) {
      try {
        final centralUsers = await HttpCentralApiService().fetchCentralUsers();
        for (final u in centralUsers) {
          await db.insert(
            DatabaseTables.tableUsers,
            u.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          if (u.id == id) return u;
        }
      } catch (_) {}
    }

    return null;
  }

  @override
  Future<UserModel?> getUserByEmail(String email) async {
    final db = await _databaseService.database;
    final trimmed = email.trim();
    final lower = trimmed.toLowerCase();
    final isSuperAdminAlias = lower == 'admin';
    
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
          await db.insert(
            DatabaseTables.tableUsers,
            u.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          if (u.email.trim().toLowerCase() == lower || u.phone == trimmed) {
            return u;
          }
        }
      } catch (_) {}
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
    await db.insert(
      DatabaseTables.tableUsers,
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _auditRepository.logActivity(
      userId: adminUserId,
      userName: _currentUser?.name ?? 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: 'USER_REGISTERED',
      entityType: 'User',
      entityId: user.id,
      detailsJson:
          '{"name":"${user.name}","email":"${user.email}","role":"${user.role.toDbString()}"}',
      deviceId: deviceId,
    );

    try {
      HttpCentralApiService().broadcastUser(user);
    } catch (_) {}

    return user;
  }

  @override
  Future<UserModel> updateUser({
    required UserModel user,
    required String adminUserId,
    required String deviceId,
  }) async {
    final db = await _databaseService.database;
    await db.update(
      DatabaseTables.tableUsers,
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );

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

    try {
      HttpCentralApiService().broadcastUser(user);
    } catch (_) {}

    if (_currentUser?.id == user.id) {
      _currentUser = user;
    }
    return user;
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
