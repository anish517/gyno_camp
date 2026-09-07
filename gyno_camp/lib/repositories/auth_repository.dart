import 'package:sqflite/sqflite.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../models/user_model.dart';
import 'audit_repository.dart';

abstract class IAuthRepository {
  Future<List<UserModel>> getAllUsers();
  Future<UserModel?> getUserById(String id);
  Future<UserModel?> getUserByEmail(String email);
  Future<UserModel> createUser({
    required UserModel user,
    required String adminUserId,
    required String deviceId,
  });
  Future<UserModel?> login({required String email, required String deviceId});
  Future<UserModel?> loginAsRole({required UserRole role, required String deviceId});
  Future<void> logout({required String deviceId});
  UserModel? get currentUser;
}

class AuthRepository implements IAuthRepository {
  final DatabaseService _databaseService;
  final AuditRepository _auditRepository;
  UserModel? _currentUser;

  AuthRepository({
    DatabaseService? databaseService,
    AuditRepository? auditRepository,
  })  : _databaseService = databaseService ?? DatabaseService(),
        _auditRepository = auditRepository ?? AuditRepository();

  @override
  UserModel? get currentUser => _currentUser;

  @override
  Future<List<UserModel>> getAllUsers() async {
    final db = await _databaseService.database;
    final maps = await db.query(
      DatabaseTables.tableUsers,
      where: 'is_active = ?',
      whereArgs: [1],
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
    if (maps.isEmpty) return null;
    return UserModel.fromMap(maps.first);
  }

  @override
  Future<UserModel?> getUserByEmail(String email) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      DatabaseTables.tableUsers,
      where: 'LOWER(email) = ?',
      whereArgs: [email.toLowerCase().trim()],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return UserModel.fromMap(maps.first);
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
      detailsJson: '{"name":"${user.name}","email":"${user.email}","role":"${user.role.toDbString()}"}',
      deviceId: deviceId,
    );

    return user;
  }

  @override
  Future<UserModel?> login({required String email, required String deviceId}) async {
    final user = await getUserByEmail(email);
    if (user == null || !user.isActive) return null;

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
      detailsJson: '{"loginMethod":"email","email":"$email"}',
      deviceId: deviceId,
    );

    return _currentUser;
  }

  @override
  Future<UserModel?> loginAsRole({required UserRole role, required String deviceId}) async {
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
      detailsJson: '{"loginMethod":"role_switch","role":"${role.toDbString()}"}',
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
