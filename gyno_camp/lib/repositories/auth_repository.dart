import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../core/security/security_service.dart';
import '../core/services/http_central_api_service.dart';
import '../core/services/session_service.dart';
import '../models/camp_model.dart';
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
  Future<Map<String, dynamic>> sendForgotPasswordOtp(String email);
  Future<Map<String, dynamic>> verifyResetCode(String email, String code);
  Future<Map<String, dynamic>> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
    String? newPin,
    required String deviceId,
  });
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
      columns: ['password_hash', 'pin_hash', 'updated_at', 'assigned_camp_ids'],
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
      final localCampIds = row['assigned_camp_ids'] as String?;

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

      // Identify whether local credentials are just unedited default bootstrap seeds
      final defaultAdminPass = SecurityService.hashSha256('admin123');
      final defaultNursePass = SecurityService.hashSha256('nurse123');
      final defaultAnalystPass = SecurityService.hashSha256('analyst123');
      final defaultPin = SecurityService.hashPin('1234');

      final isLocalDefaultPass = localPass == defaultAdminPass ||
          localPass == defaultNursePass ||
          localPass == defaultAnalystPass;
      final isLocalDefaultPin = localPin == defaultPin;

      // LOCAL wins credentials ONLY when:
      //   - local timestamp is STRICTLY NEWER than incoming, AND
      //   - local credentials are not just the default bootstrap seeds.
      // If timestamps are equal (or incoming is newer), server (incoming) wins.
      // This handles the cross-browser password-reset race:
      //   Chrome resets → PostgreSQL updated_at = NOW() → Opera fetches → incoming is newer → Opera gets new hash.
      final localIsStrictlyNewer = localTs != null &&
          incomingTs != null &&
          localTs.isAfter(incomingTs) &&
          !isLocalDefaultPass;

      final incomingPassEmpty =
          map['password_hash'] == null || map['password_hash'].toString().isEmpty;
      final incomingPinEmpty =
          map['pin_hash'] == null || map['pin_hash'].toString().isEmpty;

      // Password resolution:
      if (incomingPassEmpty) {
        // Server has no hash yet — keep local
        if (localPass != null && localPass.isNotEmpty) {
          map['password_hash'] = localPass;
        }
      } else if (localIsStrictlyNewer) {
        // Local has a genuinely newer custom password — keep it
        map['password_hash'] = localPass;
      }
      // else: incoming (server/reset) hash wins → map already has it

      // PIN resolution:
      if (incomingPinEmpty) {
        if (localPin != null && localPin.isNotEmpty) {
          map['pin_hash'] = localPin;
        }
      } else if (localIsStrictlyNewer && !isLocalDefaultPin) {
        map['pin_hash'] = localPin;
      }
      // else: incoming pin wins

      // ── assigned_camp_ids resolution ────────────────────────────────────
      // If local is strictly newer, keep the local camp assignments to prevent
      // stale PostgreSQL snapshots from restoring removed/added camps.
      // If incoming is newer (or same), the server wins — correctly
      // propagating new assignments made from another device or browser.
      if (localIsStrictlyNewer && localCampIds != null) {
        map['assigned_camp_ids'] = localCampIds;
      }
      // else: incoming server camp IDs win (already in map from u.toMap())

      // Preserve whichever timestamp is genuinely newer
      if (localIsStrictlyNewer && localUpdatedAt != null) {
        map['updated_at'] = localUpdatedAt;
      }
    }
    await db.insert(
      DatabaseTables.tableUsers,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Cross-checks [user.assignedCampIds] against the camps table (source of truth).
  /// Any camp that no longer lists [user.id] in its assigned_staff_ids is stripped.
  /// Persists corrections to SQLite + server if anything changed.
  /// Must be called on every code path that loads a user into an active session.
  Future<UserModel> _reconcileCampIds(DatabaseExecutor db, UserModel user) async {
    try {
      final campRows = await db.query(DatabaseTables.tableCamps);
      final reconciledCampIds = <String>[];
      for (final campId in user.assignedCampIds) {
        final matches = campRows.where((r) => r['id'] == campId);
        if (matches.isNotEmpty) {
          final staffIds = (matches.first['assigned_staff_ids'] as String? ?? '')
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet();
          if (staffIds.contains(user.id)) {
            reconciledCampIds.add(campId);
          }
          // else: camp no longer lists this user → strip it
        }
        // else: camp not in local DB → strip it
      }
      if (reconciledCampIds.length != user.assignedCampIds.length) {
        final now = DateTime.now().toUtc();
        final corrected = user.copyWith(
          assignedCampIds: reconciledCampIds,
          updatedAt: now,
        );
        await db.update(
          DatabaseTables.tableUsers,
          {
            'assigned_camp_ids': reconciledCampIds.join(','),
            'updated_at': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [user.id],
        );
        if (enableCentralSync) {
          try { HttpCentralApiService().broadcastUser(corrected); } catch (_) {}
        }
        debugPrint('[AuthRepo] Reconciled camps for ${user.email}: ${reconciledCampIds.join(",")}');
        return corrected;
      }
    } catch (e) {
      debugPrint('[AuthRepo] Camp reconciliation error (non-fatal): $e');
    }
    return user;
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
              !AppConstants.isLegacyDefaultOrganization(savedOrg) &&
              AppConstants.isLegacyDefaultOrganization(u.tenantName)) {
            return u.copyWith(tenantName: savedOrg.trim());
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
      UserModel user = UserModel.fromMap(maps.first);
      user = await _reconcileCampIds(db, user);
      final savedOrg = SessionService.current?.getOrganizationName();
      if (savedOrg != null &&
          savedOrg.trim().isNotEmpty &&
          !AppConstants.isLegacyDefaultOrganization(savedOrg) &&
          AppConstants.isLegacyDefaultOrganization(user.tenantName)) {
        return user.copyWith(tenantName: savedOrg.trim());
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
          UserModel user = UserModel.fromMap(refreshed.first);
          user = await _reconcileCampIds(db, user);
          final savedOrg = SessionService.current?.getOrganizationName();
          if (savedOrg != null &&
              savedOrg.trim().isNotEmpty &&
              !AppConstants.isLegacyDefaultOrganization(savedOrg) &&
              AppConstants.isLegacyDefaultOrganization(user.tenantName)) {
            return user.copyWith(tenantName: savedOrg.trim());
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

    // Strict lookup: only the account's CURRENT email or phone can sign in.
    // (No hard-coded 'admin' / 'admin@gynocamp.org' aliases once the email is changed.)
    final maps = await db.query(
      DatabaseTables.tableUsers,
      where: 'LOWER(email) = ? OR phone = ?',
      whereArgs: [lower, trimmed],
      limit: 1,
    );

    // ── Fix 1A: Always try to refresh from central on login ────────────────
    // Even if the user exists locally, their assignedCampIds may be stale
    // (e.g. admin assigned them to a new camp from a different device). We
    // attempt a background upsert here, which is timestamp-safe: local
    // credentials always win if the local record is newer.
    if (maps.isNotEmpty &&
        enableCentralSync &&
        !HttpCentralApiService.isServerCooldownActive) {
      try {
        final centralUsers = await HttpCentralApiService().fetchCentralUsers();
        for (final u in centralUsers) {
          await _upsertUserPreservingCredentials(db, u);
        }
        // Re-read after potential update so we return the freshest record
        final refreshed = await db.query(
          DatabaseTables.tableUsers,
          where: 'LOWER(email) = ? OR phone = ?',
          whereArgs: [lower, trimmed],
          limit: 1,
        );
        if (refreshed.isNotEmpty) return UserModel.fromMap(refreshed.first);
      } catch (e) {
        debugPrint('[AuthRepo] Login central refresh error (non-fatal): $e');
      }
      // Fallback: return the originally found local record
      return UserModel.fromMap(maps.first);
    }

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
          where: 'LOWER(email) = ? OR phone = ?',
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

    // If organization / tenant name was updated, persist across SaaS session, users, and camps
    if (user.tenantName.trim().isNotEmpty &&
        !AppConstants.isLegacyDefaultOrganization(user.tenantName)) {
      await updateTenantOrganizationName(
        newOrgName: user.tenantName.trim(),
        tenantId: user.tenantId,
        adminUserId: adminUserId,
        deviceId: deviceId,
      );
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
          if (enableCentralSync) {
            try {
              final campObj = CampModel.fromMap(r).copyWith(
                assignedStaffIds: rawStaff.toList(),
                updatedAt: DateTime.now().toUtc(),
              );
              HttpCentralApiService().broadcastCamp(campObj);
            } catch (_) {}
          }
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

  Future<void> updateTenantOrganizationName({
    required String newOrgName,
    required String tenantId,
    required String adminUserId,
    required String deviceId,
  }) async {
    final trimmed = newOrgName.trim();
    if (trimmed.isEmpty) return;

    // 1. Save in SharedPreferences
    await SessionService.current?.saveOrganizationName(trimmed);

    final db = await _databaseService.database;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // 2. Persist in app_metadata
    try {
      await db.insert(
        DatabaseTables.tableMetadata,
        {
          'key': 'saas_organization_name',
          'value': trimmed,
          'updated_at': nowIso,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await db.insert(
        DatabaseTables.tableMetadata,
        {
          'key': 'tenant_organization_name',
          'value': trimmed,
          'updated_at': nowIso,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 3. Update ALL users in SQLite belonging to this tenant or default
      await db.rawUpdate(
        "UPDATE ${DatabaseTables.tableUsers} SET tenant_name = ?, updated_at = ? WHERE tenant_id = ? OR tenant_id = 'tenant_default' OR tenant_id = 'global'",
        [trimmed, nowIso, tenantId],
      );

      // 4. Update ALL camps in SQLite belonging to this tenant or default
      await db.rawUpdate(
        "UPDATE ${DatabaseTables.tableCamps} SET organization_name = ?, updated_at = ? WHERE tenant_id = ? OR tenant_id = 'tenant_default' OR tenant_id = 'global'",
        [trimmed, nowIso, tenantId],
      );
    } catch (e) {
      debugPrint('[AuthRepo] SQLite update error: $e');
    }

    // 5. Update local _currentUser if set
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(tenantName: trimmed);
    }

    // 6. Broadcast to Central Cloud Server
    if (enableCentralSync && HttpCentralApiService.isServerConfigured) {
      try {
        final api = HttpCentralApiService();
        // Call the atomic tenant rename endpoint on the server
        await api.renameTenant(tenantId: tenantId, newOrgName: trimmed);

        // Also broadcast all updated camps so PostgreSQL and other devices get full payloads
        final camps = await db.query(DatabaseTables.tableCamps);
        for (final row in camps) {
          final camp = CampModel.fromMap(row);
          await api.broadcastCamp(camp);
        }

        // Also broadcast all updated users
        final users = await db.query(DatabaseTables.tableUsers);
        for (final row in users) {
          final u = UserModel.fromMap(row);
          await api.broadcastUser(u);
        }
      } catch (e) {
        debugPrint('[AuthRepo] Central cloud broadcast error: $e');
      }
    }

    // 7. Audit log
    await _auditRepository.logActivity(
      userId: adminUserId,
      userName: _currentUser?.name ?? 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: 'ORGANIZATION_RENAMED',
      entityType: 'Tenant',
      entityId: tenantId,
      detailsJson: '{"newOrganizationName":"$trimmed"}',
      deviceId: deviceId,
    );
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
    var user = await getUserByEmail(email);
    if (user == null || !user.isActive) return null;

    final hasCredentials = (user.passwordHash != null && user.passwordHash!.isNotEmpty) ||
        (user.pinHash != null && user.pinHash!.isNotEmpty);

    if (hasCredentials) {
      if (password == null || password.trim().isEmpty) {
        return null;
      }
      final inputHash = SecurityService.hashSha256(password);
      var isPinValid =
          user.pinHash != null &&
          user.pinHash!.isNotEmpty &&
          SecurityService.verifyPin(password, user.pinHash!);
      var isPasswordValid =
          user.passwordHash != null &&
          user.passwordHash!.isNotEmpty &&
          user.passwordHash == inputHash;

      if (!isPasswordValid && !isPinValid) {
        // getUserByEmail() above already synced the latest user data from the central server
        // into local SQLite. Re-read the freshest local record to check if credentials were
        // updated remotely (e.g. password reset from another browser).
        // This avoids a redundant fetchCentralUsers() HTTP call that would cause excess
        // widget rebuilds and contribute to TextField desync on Flutter Web.
        if (enableCentralSync) {
          try {
            final db = await _databaseService.database;
            final freshRows = await db.query(
              DatabaseTables.tableUsers,
              where: 'LOWER(email) = ? OR phone = ?',
              whereArgs: [email.trim().toLowerCase(), email.trim()],
              limit: 1,
            );
            if (freshRows.isNotEmpty) {
              final reloaded = UserModel.fromMap(freshRows.first);
              if (reloaded.isActive) {
                final isPinValidFresh = reloaded.pinHash != null &&
                    reloaded.pinHash!.isNotEmpty &&
                    SecurityService.verifyPin(password, reloaded.pinHash!);
                final isPasswordValidFresh = reloaded.passwordHash != null &&
                    reloaded.passwordHash!.isNotEmpty &&
                    reloaded.passwordHash == inputHash;
                if (isPasswordValidFresh || isPinValidFresh) {
                  user = reloaded;
                } else {
                  return null;
                }
              } else {
                return null;
              }
            } else {
              return null;
            }
          } catch (_) {
            return null;
          }
        } else {
          return null;
        }
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

    // Apply effective organization name consistently on fresh login
    final savedOrg = SessionService.current?.getOrganizationName();
    final effectiveTenant = (savedOrg != null &&
            savedOrg.trim().isNotEmpty &&
            !AppConstants.isLegacyDefaultOrganization(savedOrg))
        ? savedOrg.trim()
        : (!AppConstants.isLegacyDefaultOrganization(user.tenantName)
            ? user.tenantName.trim()
            : AppConstants.defaultOrganizationName);

    _currentUser = user.copyWith(
      lastLoginAt: now,
      tenantName: effectiveTenant,
    );

    // ── Camp assignment reconciliation (authoritative source-of-truth check) ──
    // Cross-check user.assignedCampIds against what the local camps table says.
    // Any camp that no longer lists this user in assigned_staff_ids is stripped.
    // This is the authoritative fix: it cleans stale PostgreSQL data on login
    // regardless of timestamp race conditions.
    try {
      final campRows = await db.query(DatabaseTables.tableCamps);
      final reconciledCampIds = <String>[];
      for (final campId in _currentUser!.assignedCampIds) {
        final matches = campRows.where((r) => r['id'] == campId);
        if (matches.isNotEmpty) {
          final staffIds = (matches.first['assigned_staff_ids'] as String? ?? '')
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet();
          if (staffIds.contains(_currentUser!.id)) {
            reconciledCampIds.add(campId); // user is still assigned
          }
          // else: camp no longer lists this user → drop it
        }
        // else: camp not found locally → drop it (deleted or not yet synced)
      }
      if (reconciledCampIds.length != _currentUser!.assignedCampIds.length) {
        _currentUser = _currentUser!.copyWith(assignedCampIds: reconciledCampIds);
        final correctedUpdatedAt = DateTime.now().toUtc().toIso8601String();
        await db.update(
          DatabaseTables.tableUsers,
          {
            'assigned_camp_ids': reconciledCampIds.join(','),
            'updated_at': correctedUpdatedAt,
          },
          where: 'id = ?',
          whereArgs: [_currentUser!.id],
        );
        if (enableCentralSync) {
          try {
            HttpCentralApiService().broadcastUser(
              _currentUser!.copyWith(updatedAt: DateTime.now().toUtc()),
            );
          } catch (_) {}
        }
        debugPrint('[AuthRepo] Reconciled camps for ${_currentUser!.email}: ${reconciledCampIds.join(",")}');
      }
    } catch (e) {
      debugPrint('[AuthRepo] Camp reconciliation error (non-fatal): $e');
    }

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

    // Apply effective organization name consistently on role switch
    final savedOrgRole = SessionService.current?.getOrganizationName();
    final effectiveTenantRole = (savedOrgRole != null &&
            savedOrgRole.trim().isNotEmpty &&
            !AppConstants.isLegacyDefaultOrganization(savedOrgRole))
        ? savedOrgRole.trim()
        : (!AppConstants.isLegacyDefaultOrganization(user.tenantName)
            ? user.tenantName.trim()
            : AppConstants.defaultOrganizationName);

    _currentUser = user.copyWith(
      lastLoginAt: now,
      tenantName: effectiveTenantRole,
    );

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

  @override
  Future<Map<String, dynamic>> sendForgotPasswordOtp(String email) async {
    return HttpCentralApiService().sendForgotPasswordOtp(email);
  }

  @override
  Future<Map<String, dynamic>> verifyResetCode(String email, String code) async {
    return HttpCentralApiService().verifyResetCode(email, code);
  }

  @override
  Future<Map<String, dynamic>> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
    String? newPin,
    required String deviceId,
  }) async {
    final result = await HttpCentralApiService().resetPasswordWithCode(
      email,
      code,
      newPassword,
      newPin: newPin,
    );

    if (result['success'] == true) {
      try {
        final db = await _databaseService.database;
        final passHash = SecurityService.hashSha256(newPassword.trim());
        final pinHash = (newPin != null && newPin.trim().isNotEmpty)
            ? SecurityService.hashPin(newPin.trim())
            : null;
        final nowIso = DateTime.now().toUtc().toIso8601String();

        final updates = <String, dynamic>{
          'password_hash': passHash,
          'updated_at': nowIso,
        };
        if (pinHash != null) {
          updates['pin_hash'] = pinHash;
        }

        await db.update(
          DatabaseTables.tableUsers,
          updates,
          where: 'LOWER(email) = ?',
          whereArgs: [email.trim().toLowerCase()],
        );

        final matchedUsers = await db.query(
          DatabaseTables.tableUsers,
          where: 'LOWER(email) = ?',
          whereArgs: [email.trim().toLowerCase()],
          limit: 1,
        );

        if (matchedUsers.isNotEmpty) {
          final u = UserModel.fromMap(matchedUsers.first);
          await _auditRepository.logActivity(
            userId: u.id,
            userName: u.name,
            userRole: u.role.toDbString(),
            action: 'PASSWORD_RESET_VIA_SMTP',
            entityType: 'User',
            entityId: u.id,
            detailsJson: '{"method":"smtp_otp_reset","email":"$email"}',
            deviceId: deviceId,
          );
          // Broadcast updated user (new hash + fresh updated_at) to central server.
          // Ensures SSE-connected browsers (Opera, Android, other tabs) receive the
          // new credential immediately and won't be stuck with a stale local hash.
          if (enableCentralSync) {
            try {
              await HttpCentralApiService().broadcastUser(u);
            } catch (e) {
              debugPrint('[AuthRepo] Broadcast after reset (non-fatal): $e');
            }
          }
        }
      } catch (e) {
        debugPrint('[AuthRepo] Local SQLite update error after reset: $e');
      }
    }

    return result;
  }
}
