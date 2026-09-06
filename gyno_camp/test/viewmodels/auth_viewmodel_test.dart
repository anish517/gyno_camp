import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/auth_repository.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/viewmodels/auth_viewmodel.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('AuthViewModel (Riverpod StateNotifier) Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late AuthRepository authRepo;
    late AuthViewModel authVm;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      authRepo = AuthRepository(databaseService: dbService, auditRepository: auditRepo);
      authVm = AuthViewModel(authRepo);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('Initial state is unauthenticated', () {
      expect(authVm.state.isAuthenticated, isFalse);
      expect(authVm.state.currentUser, isNull);
    });

    test('loginAsRole updates state to authenticated with appropriate role', () async {
      final success = await authVm.loginAsRole(
        role: UserRole.dataTaker,
        deviceId: 'dev-test',
      );

      expect(success, isTrue);
      expect(authVm.state.isAuthenticated, isTrue);
      expect(authVm.state.currentUser?.role, UserRole.dataTaker);
      expect(authVm.state.currentRole, UserRole.dataTaker);
    });

    test('login with unknown email sets error state', () async {
      final success = await authVm.login(
        email: 'invalid_email@nowhere.com',
        deviceId: 'dev-test',
      );

      expect(success, isFalse);
      expect(authVm.state.isAuthenticated, isFalse);
      expect(authVm.state.errorMessage, isNotNull);
    });

    test('logout clears user from state', () async {
      await authVm.loginAsRole(role: UserRole.superAdmin, deviceId: 'dev-test');
      expect(authVm.state.isAuthenticated, isTrue);

      await authVm.logout(deviceId: 'dev-test');
      expect(authVm.state.isAuthenticated, isFalse);
      expect(authVm.state.currentUser, isNull);
    });
  });
}
