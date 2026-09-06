import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/constants/app_constants.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/models/device_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/device_security_repository.dart';
import 'package:gyno_camp/viewmodels/device_management_viewmodel.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DeviceManagementViewModel Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late DeviceSecurityRepository devRepo;
    late DeviceManagementViewModel vm;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      devRepo = DeviceSecurityRepository(
        databaseService: dbService,
        auditRepository: auditRepo,
      );

      // Register a device to have pending state
      final reg = await devRepo.requestDeviceRegistration(
        deviceName: 'Field Tablet 1',
        model: 'Galaxy Tab A',
        hardwareFingerprint: 'hw-fp-test-001',
        staffUserId: 'usr-01',
        staffName: 'Staff Sita',
      );
      // Verify OTP so it moves to pending approval
      await devRepo.verifyOtp(deviceId: reg.device.deviceId, enteredOtp: reg.plainOtp);

      vm = DeviceManagementViewModel(devRepo);
      await Future.delayed(const Duration(milliseconds: 100));
    });

    tearDown(() async {
      await testDb.close();
    });

    test('initial state loads devices and counts pending accurately', () async {
      expect(vm.state.isLoading, isFalse);
      expect(vm.state.devices.isNotEmpty, isTrue);
      expect(vm.state.pendingCount, greaterThanOrEqualTo(1));
    });

    test('filterStatus filters list of devices', () {
      vm.setFilter(AppConstants.deviceStatusPendingApproval);
      expect(vm.state.filterStatus, AppConstants.deviceStatusPendingApproval);
      expect(
        vm.state.filteredDevices.every((d) => d.status == DeviceActivationStatus.pendingApproval),
        isTrue,
      );
    });

    test('approveDevice moves pending device to approved', () async {
      final pendingDev = vm.state.devices.firstWhere(
        (d) => d.status == DeviceActivationStatus.pendingApproval,
      );

      final success = await vm.approveDevice(pendingDev.deviceId, adminUserId: 'admin-01');
      expect(success, isTrue);
      expect(vm.state.successMessage, contains('authorized'));

      final updated = vm.state.devices.firstWhere((d) => d.deviceId == pendingDev.deviceId);
      expect(updated.status, DeviceActivationStatus.approved);
    });

    test('revokeDevice sets approved device to revoked', () async {
      // First approve it
      final pendingDev = vm.state.devices.firstWhere(
        (d) => d.status == DeviceActivationStatus.pendingApproval,
      );
      await vm.approveDevice(pendingDev.deviceId, adminUserId: 'admin-01');

      // Now revoke it
      final revoked = await vm.revokeDevice(pendingDev.deviceId, adminUserId: 'admin-01');
      expect(revoked, isTrue);
      expect(vm.state.successMessage, contains('revoked'));

      final updated = vm.state.devices.firstWhere((d) => d.deviceId == pendingDev.deviceId);
      expect(updated.status, DeviceActivationStatus.revoked);
    });
  });
}
