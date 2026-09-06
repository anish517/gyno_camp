import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/repositories/device_security_repository.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/viewmodels/device_security_viewmodel.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DeviceSecurityViewModel (Riverpod StateNotifier) Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late DeviceSecurityRepository deviceRepo;
    late DeviceSecurityViewModel deviceVm;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      deviceRepo = DeviceSecurityRepository(databaseService: dbService, auditRepository: auditRepo);
      deviceVm = DeviceSecurityViewModel(deviceRepo);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('Initial state reflects hardware fingerprint and unregistered status', () {
      expect(deviceVm.state.hardwareFingerprint, isNotEmpty);
      expect(deviceVm.state.isUnregistered, isTrue);
      expect(deviceVm.state.isApproved, isFalse);
    });

    test('requestRegistration transitions state to pendingOtp with plainOtp generated', () async {
      final success = await deviceVm.requestRegistration(
        deviceName: 'Field Unit 99',
        staffUserId: 'usr-datataker-01',
        staffName: 'Sita',
      );

      expect(success, isTrue);
      expect(deviceVm.state.isPendingOtp, isTrue);
      expect(deviceVm.state.latestOtp, isNotNull);
      expect(deviceVm.state.latestOtp!.length, 6);
    });

    test('verifyOtp transitions state to pendingApproval when correct OTP is passed', () async {
      await deviceVm.requestRegistration(
        deviceName: 'Field Unit 99',
        staffUserId: 'usr-datataker-01',
        staffName: 'Sita',
      );

      final otp = deviceVm.state.latestOtp!;
      final verified = await deviceVm.verifyOtp(otp);

      expect(verified, isTrue);
      expect(deviceVm.state.isPendingApproval, isTrue);
    });

    test('approveDeviceByAdmin transitions state to approved', () async {
      await deviceVm.requestRegistration(
        deviceName: 'Field Unit 99',
        staffUserId: 'usr-datataker-01',
        staffName: 'Sita',
      );

      final otp = deviceVm.state.latestOtp!;
      await deviceVm.verifyOtp(otp);

      final approved = await deviceVm.approveDeviceByAdmin(adminUserId: 'usr-superadmin-01');
      expect(approved, isTrue);
      expect(deviceVm.state.isApproved, isTrue);
      expect(deviceVm.state.requiresPinSetup, isTrue);
    });

    test('PIN setup and unlock flow', () async {
      await deviceVm.requestRegistration(
        deviceName: 'Field Unit 99',
        staffUserId: 'usr-datataker-01',
        staffName: 'Sita',
      );
      await deviceVm.verifyOtp(deviceVm.state.latestOtp!);
      await deviceVm.approveDeviceByAdmin(adminUserId: 'usr-superadmin-01');

      // Setup PIN
      final pinSet = await deviceVm.setupPin('9876');
      expect(pinSet, isTrue);
      expect(deviceVm.state.isAppLocked, isFalse);

      // Lock app
      deviceVm.lockApp();
      expect(deviceVm.state.isAppLocked, isTrue);

      // Wrong PIN fails to unlock
      final wrongUnlock = await deviceVm.unlockWithPin('0000');
      expect(wrongUnlock, isFalse);
      expect(deviceVm.state.isAppLocked, isTrue);

      // Correct PIN unlocks
      final correctUnlock = await deviceVm.unlockWithPin('9876');
      expect(correctUnlock, isTrue);
      expect(deviceVm.state.isAppLocked, isFalse);
    });
  });
}
