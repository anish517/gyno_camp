import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/auth_repository.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';

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
      authRepo = AuthRepository(databaseService: dbService, auditRepository: auditRepo);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('getAllUsers returns seeded users', () async {
      final users = await authRepo.getAllUsers();
      expect(users.length, greaterThanOrEqualTo(3));
    });

    test('login with valid email succeeds and updates lastLoginAt and audit trail', () async {
      final user = await authRepo.login(email: 'sita@gynocamp.org', deviceId: 'dev-test-01');
      expect(user, isNotNull);
      expect(user!.name, contains('Sita'));
      expect(user.role, UserRole.dataTaker);
      expect(authRepo.currentUser, isNotNull);

      // Check audit log was written
      final logs = await auditRepo.getRecentLogs();
      expect(logs.any((l) => l.action == 'USER_LOGIN' && l.userId == user.id), isTrue);
    });

    test('login with invalid email returns null', () async {
      final user = await authRepo.login(email: 'nonexistent@gynocamp.org', deviceId: 'dev-test-01');
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
      await authRepo.login(email: 'admin@gynocamp.org', deviceId: 'dev-test-01');
      expect(authRepo.currentUser, isNotNull);

      await authRepo.logout(deviceId: 'dev-test-01');
      expect(authRepo.currentUser, isNull);

      final logs = await auditRepo.getRecentLogs();
      expect(logs.any((l) => l.action == 'USER_LOGOUT'), isTrue);
    });
  });
}
