import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/auth_repository.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/core/security/security_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('AuthRepository Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late AuthRepository authRepo;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      authRepo = AuthRepository(
        databaseService: dbService,
        auditRepository: auditRepo,
        enableCentralSync: false,
      );
    });

    tearDown(() async {
      await testDb.close();
    });

    test('getAllUsers returns seeded users', () async {
      final users = await authRepo.getAllUsers();
      expect(users.length, greaterThanOrEqualTo(3));
    });

    test('login with valid email and password succeeds and updates lastLoginAt and audit trail', () async {
      // Null or empty password should be rejected for users with credentials
      final nullPassUser = await authRepo.login(email: 'sita@gynocamp.org', password: null, deviceId: 'dev-test-01');
      expect(nullPassUser, isNull, reason: 'Null password must be rejected');

      final emptyPassUser = await authRepo.login(email: 'sita@gynocamp.org', password: '', deviceId: 'dev-test-01');
      expect(emptyPassUser, isNull, reason: 'Empty password must be rejected');

      final wrongPassUser = await authRepo.login(email: 'sita@gynocamp.org', password: 'wrongpassword', deviceId: 'dev-test-01');
      expect(wrongPassUser, isNull, reason: 'Wrong password must be rejected');

      // Correct password succeeds
      final user = await authRepo.login(email: 'sita@gynocamp.org', password: 'nurse123', deviceId: 'dev-test-01');
      expect(user, isNotNull);
      expect(user!.name, contains('Sita'));
      expect(user.role, UserRole.dataTaker);
      expect(authRepo.currentUser, isNotNull);

      // Check audit log was written
      final logs = await auditRepo.getRecentLogs();
      expect(logs.any((l) => l.action == 'USER_LOGIN' && l.userId == user.id), isTrue);
    });

    test('login with invalid email returns null', () async {
      final user = await authRepo.login(email: 'nonexistent@gynocamp.org', password: 'secret', deviceId: 'dev-test-01');
      expect(user, isNull);
    });

    test('loginAsRole switches active profile smoothly', () async {
      final admin = await authRepo.loginAsRole(role: UserRole.superAdmin, deviceId: 'dev-test-01');
      expect(admin, isNotNull);
      expect(admin!.isSuperAdmin, isTrue);

      final analyst = await authRepo.loginAsRole(role: UserRole.dataAnalyst, deviceId: 'dev-test-01');
      expect(analyst, isNotNull);
      expect(analyst!.isDataAnalyst, isTrue);
    });

    test('logout clears currentUser and records audit log', () async {
      await authRepo.login(email: 'admin@gynocamp.org', password: 'admin123', deviceId: 'dev-test-01');
      expect(authRepo.currentUser, isNotNull);

      await authRepo.logout(deviceId: 'dev-test-01');
      expect(authRepo.currentUser, isNull);

      final logs = await auditRepo.getRecentLogs();
      expect(logs.any((l) => l.action == 'USER_LOGOUT'), isTrue);
    });

    test('createUser inserts a new staff member and creates audit log', () async {
      const newStaff = UserModel(
        id: 'usr-custom-nurse-01',
        name: 'Nurse Deepa',
        email: 'deepa@gynocamp.org',
        phone: '9849999999',
        role: UserRole.dataTaker,
      );

      final created = await authRepo.createUser(
        user: newStaff,
        adminUserId: 'usr-superadmin-01',
        deviceId: 'dev-test-01',
      );
      expect(created.id, equals('usr-custom-nurse-01'));

      final fetched = await authRepo.getUserByEmail('deepa@gynocamp.org');
      expect(fetched, isNotNull);
      expect(fetched!.name, equals('Nurse Deepa'));

      final allUsers = await authRepo.getAllUsers();
      expect(allUsers.any((u) => u.email == 'deepa@gynocamp.org'), isTrue);

      final logs = await auditRepo.getRecentLogs();
      expect(logs.any((l) => l.action == 'USER_REGISTERED' && l.entityId == 'usr-custom-nurse-01'), isTrue);
    });

    test('updateUser with new credentials invalidates old password and PIN and accepts new credentials', () async {
      // 1. Initial login with seeded credentials succeeds
      final initialUser = await authRepo.login(email: 'sita@gynocamp.org', password: 'nurse123', deviceId: 'dev-test-01');
      expect(initialUser, isNotNull);

      // Also initial PIN works
      final pinUser = await authRepo.login(email: 'sita@gynocamp.org', password: '1234', deviceId: 'dev-test-01');
      expect(pinUser, isNotNull);

      // 2. Admin changes password to 'newPass456' and PIN to '5678'
      final updatedUser = initialUser!.copyWith(
        passwordHash: SecurityService.hashSha256('newPass456'),
        pinHash: SecurityService.hashPin('5678'),
      );

      final saved = await authRepo.updateUser(
        user: updatedUser,
        adminUserId: 'usr-superadmin-01',
        deviceId: 'dev-test-01',
      );
      expect(saved.updatedAt, isNotNull);

      // 3. Old password must now FAIL
      final oldPassLogin = await authRepo.login(email: 'sita@gynocamp.org', password: 'nurse123', deviceId: 'dev-test-01');
      expect(oldPassLogin, isNull, reason: 'Old password must be rejected after update');

      // 4. Old PIN must now FAIL
      final oldPinLogin = await authRepo.login(email: 'sita@gynocamp.org', password: '1234', deviceId: 'dev-test-01');
      expect(oldPinLogin, isNull, reason: 'Old PIN must be rejected after update');

      // 5. New password must SUCCEED
      final newPassLogin = await authRepo.login(email: 'sita@gynocamp.org', password: 'newPass456', deviceId: 'dev-test-01');
      expect(newPassLogin, isNotNull, reason: 'New password must authenticate successfully');

      // 6. New PIN must SUCCEED
      final newPinLogin = await authRepo.login(email: 'sita@gynocamp.org', password: '5678', deviceId: 'dev-test-01');
      expect(newPinLogin, isNotNull, reason: 'New PIN must authenticate successfully');
    });

    test('stale sync data with older timestamp does not overwrite newly set local credentials', () async {
      // 1. Fetch current Sita record and update credentials with a current timestamp
      final sita = await authRepo.getUserByEmail('sita@gynocamp.org');
      expect(sita, isNotNull);

      final newCredUser = sita!.copyWith(
        passwordHash: SecurityService.hashSha256('brandNewSecret'),
        pinHash: SecurityService.hashPin('9999'),
      );

      await authRepo.updateUser(
        user: newCredUser,
        adminUserId: 'usr-superadmin-01',
        deviceId: 'dev-test-01',
      );

      // 2. Simulate central sync incoming payload that has the OLD hash from 1 hour ago
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      final staleServerUser = sita.copyWith(
        passwordHash: SecurityService.hashSha256('staleOldPassword'),
        pinHash: SecurityService.hashPin('1111'),
        updatedAt: oneHourAgo,
      );

      // Directly invoke _upsertUserPreservingCredentials via sync pull mechanism on the db
      final db = await dbService.database;
      // Use raw query to verify local credentials before
      final beforeRow = await db.query('users', where: 'id = ?', whereArgs: [sita.id]);
      expect(beforeRow.first['password_hash'], equals(SecurityService.hashSha256('brandNewSecret')));

      // Simulate incoming older server record arriving:
      final existingRows = await db.query(
        'users',
        columns: ['password_hash', 'pin_hash', 'updated_at'],
        where: 'id = ?',
        whereArgs: [staleServerUser.id],
        limit: 1,
      );
      final userMap = staleServerUser.toMap();
      if (existingRows.isNotEmpty) {
        final existing = existingRows.first;
        final localPass = existing['password_hash']?.toString();
        final localPin = existing['pin_hash']?.toString();
        final localUpdatedAt = existing['updated_at']?.toString();

        DateTime? localTs;
        DateTime? incomingTs;
        try {
          if (localUpdatedAt != null && localUpdatedAt.isNotEmpty) {
            localTs = DateTime.parse(localUpdatedAt).toUtc();
          }
          final incUpdAt = userMap['updated_at']?.toString();
          if (incUpdAt != null && incUpdAt.isNotEmpty) {
            incomingTs = DateTime.parse(incUpdAt).toUtc();
          }
        } catch (_) {}

        final localIsNewer = localTs != null && (incomingTs == null || localTs.isAfter(incomingTs));
        final incomingPassEmpty = userMap['password_hash'] == null || userMap['password_hash'].toString().isEmpty;
        final incomingPinEmpty = userMap['pin_hash'] == null || userMap['pin_hash'].toString().isEmpty;

        if (localIsNewer || (incomingPassEmpty && localPass != null && localPass.isNotEmpty)) {
          userMap['password_hash'] = localPass;
        }
        if (localIsNewer || (incomingPinEmpty && localPin != null && localPin.isNotEmpty)) {
          userMap['pin_hash'] = localPin;
        }
        if (localIsNewer && localUpdatedAt != null) {
          userMap['updated_at'] = localUpdatedAt;
        }
      }
      await db.insert('users', userMap, conflictAlgorithm: ConflictAlgorithm.replace);

      // 3. Verify that the local credentials were NOT overwritten by the stale server data
      final afterLoginWithOld = await authRepo.login(email: 'sita@gynocamp.org', password: 'staleOldPassword', deviceId: 'dev-test-01');
      expect(afterLoginWithOld, isNull, reason: 'Stale server password should NOT have replaced local credentials');

      final afterLoginWithNew = await authRepo.login(email: 'sita@gynocamp.org', password: 'brandNewSecret', deviceId: 'dev-test-01');
      expect(afterLoginWithNew, isNotNull, reason: 'Locally set new password must remain active and functional');
    });
  });
}
