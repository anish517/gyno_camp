import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/models/device_model.dart';
import 'package:gyno_camp/repositories/device_security_repository.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DeviceSecurityRepository Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late DeviceSecurityRepository deviceRepo;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      deviceRepo = DeviceSecurityRepository(databaseService: dbService, auditRepository: auditRepo);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('Full device activation lifecycle: Request -> OTP -> Admin Approve -> PIN Lock', () async {
      const fingerprint = 'FP-TEST-TABLET-001';

      // 1. Initially unregistered
      final initial = await deviceRepo.getDeviceByFingerprint(fingerprint);
      expect(initial, isNull);

      // 2. Request registration -> generates OTP and transitions to pendingOtp
      final regResult = await deviceRepo.requestDeviceRegistration(
        deviceName: 'Field Unit A',
        model: 'Samsung Tab A9',
        hardwareFingerprint: fingerprint,
        staffUserId: 'usr-datataker-01',
        staffName: 'Sita Sharma',
      );

      final device = regResult.device;
      final otp = regResult.plainOtp;

      expect(device.status, DeviceActivationStatus.pendingOtp);
      expect(otp.length, 6);

      // 3. Verifying wrong OTP fails
      final wrongOtpSuccess = await deviceRepo.verifyOtp(
        deviceId: device.deviceId,
        enteredOtp: '000000',
      );
      expect(wrongOtpSuccess, isFalse);

      // 4. Verifying correct OTP succeeds -> transitions to pendingApproval
      final correctOtpSuccess = await deviceRepo.verifyOtp(
        deviceId: device.deviceId,
        enteredOtp: otp,
      );
      expect(correctOtpSuccess, isTrue);

      final pendingDev = await deviceRepo.getDeviceById(device.deviceId);
      expect(pendingDev!.status, DeviceActivationStatus.pendingApproval);

      // Check pending devices list
      final pendingList = await deviceRepo.getPendingDevices();
      expect(pendingList.any((d) => d.deviceId == device.deviceId), isTrue);

      // 5. Super Admin approves device -> status becomes approved
      final approveSuccess = await deviceRepo.approveDevice(
        deviceId: device.deviceId,
        adminUserId: 'usr-superadmin-01',
      );
      expect(approveSuccess, isTrue);

      final approvedDev = await deviceRepo.getDeviceById(device.deviceId);
      expect(approvedDev!.isApproved, isTrue);
      expect(approvedDev.approvedByUserId, 'usr-superadmin-01');

      // 6. Set 4-digit App Lock PIN
      final pinSetSuccess = await deviceRepo.setAppLockPin(
        deviceId: device.deviceId,
        pin: '4321',
      );
      expect(pinSetSuccess, isTrue);

      // 7. Verify PIN
      expect(await deviceRepo.verifyAppLockPin(deviceId: device.deviceId, enteredPin: '4321'), isTrue);
      expect(await deviceRepo.verifyAppLockPin(deviceId: device.deviceId, enteredPin: '9999'), isFalse);
    });
  });
}
