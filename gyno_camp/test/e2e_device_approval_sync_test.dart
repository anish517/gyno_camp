import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/http_central_api_service.dart';
import 'package:gyno_camp/models/device_model.dart';

void main() {
  const testServerUrl = 'http://127.0.0.1:8080';
  final api = HttpCentralApiService(baseUrl: testServerUrl);

  group('Cross-Device Whitelist Approval & Sync E2E Test', () {
    test('Mobile registers -> Central stores -> Web Admin fetches & approves -> Mobile detects approval', () async {
      final fingerprint = 'tablet-fp-${DateTime.now().millisecondsSinceEpoch}';
      final deviceId = 'dev-e2e-${DateTime.now().millisecondsSinceEpoch}';

      // 1. Mobile requests registration and verifies OTP (sets status to pendingApproval)
      final mobileDevice = DeviceModel(
        deviceId: deviceId,
        deviceName: 'Field Unit Galaxy Tab S8',
        model: 'SM-X700',
        hardwareFingerprint: fingerprint,
        status: DeviceActivationStatus.pendingApproval,
        registeredByUserId: 'usr-staff-01',
        registeredByName: 'Staff Nurse Sita',
        registeredAt: DateTime.now(),
      );

      final broadcastSuccess = await api.broadcastDevice(mobileDevice);
      expect(broadcastSuccess, isTrue, reason: 'Device broadcast to central server should succeed');

      // 2. Central Server check endpoint
      final checkedDevice = await api.checkCentralDeviceStatus(fingerprint);
      expect(checkedDevice, isNotNull);
      expect(checkedDevice!.deviceId, equals(deviceId));
      expect(checkedDevice.status, equals(DeviceActivationStatus.pendingApproval));
      expect(checkedDevice.deviceName, equals('Field Unit Galaxy Tab S8'));
      expect(checkedDevice.registeredByName, equals('Staff Nurse Sita'));

      // 3. Web Admin fetches all devices
      final allDevices = await api.fetchCentralDevices();
      expect(allDevices.any((d) => d.deviceId == deviceId), isTrue,
          reason: 'Web Admin should see the pending tablet in the central device list');
      final pendingDevices = allDevices.where((d) => d.status == DeviceActivationStatus.pendingApproval).toList();
      expect(pendingDevices.any((d) => d.deviceId == deviceId), isTrue);

      // 4. Web Admin approves the device
      final approveSuccess = await api.approveCentralDevice(deviceId, 'usr-super-admin-01');
      expect(approveSuccess, isTrue, reason: 'Admin approval should succeed on central server');

      // 5. Mobile poll detects the approved status
      final pollResult = await api.checkCentralDeviceStatus(fingerprint);
      expect(pollResult, isNotNull);
      expect(pollResult!.status, equals(DeviceActivationStatus.approved));
      expect(pollResult.isApproved, isTrue);
      expect(pollResult.approvedByUserId, equals('usr-super-admin-01'));
      expect(pollResult.approvedAt, isNotNull);
    });
  });
}
