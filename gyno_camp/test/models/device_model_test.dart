import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/models/device_model.dart';

void main() {
  group('DeviceModel & DeviceActivationStatus Tests', () {
    test('DeviceActivationStatus enum parsing works', () {
      expect(DeviceActivationStatus.fromString('APPROVED'), DeviceActivationStatus.approved);
      expect(DeviceActivationStatus.fromString('PENDING_OTP'), DeviceActivationStatus.pendingOtp);
      expect(DeviceActivationStatus.fromString('PENDING_APPROVAL'), DeviceActivationStatus.pendingApproval);
      expect(DeviceActivationStatus.fromString('REVOKED'), DeviceActivationStatus.revoked);
      expect(DeviceActivationStatus.fromString('UNREGISTERED'), DeviceActivationStatus.unregistered);
      expect(DeviceActivationStatus.fromString('invalid'), DeviceActivationStatus.unregistered);
    });

    test('DeviceModel properties and status helper getters', () {
      final dev = DeviceModel(
        deviceId: 'dev-001',
        deviceName: 'Field Tab 1',
        model: 'Samsung Tab A9',
        hardwareFingerprint: 'A1B2C3D4E5F67890',
        status: DeviceActivationStatus.approved,
        registeredAt: DateTime(2026, 9, 1),
        pinHash: 'hashed_pin_123',
      );

      expect(dev.isApproved, isTrue);
      expect(dev.hasPinSet, isTrue);
    });

    test('DeviceModel serialization preserves all fields', () {
      final now = DateTime(2026, 9, 6, 10, 0);
      final dev = DeviceModel(
        deviceId: 'dev-002',
        deviceName: 'Field Tab 2',
        model: 'Lenovo M10',
        hardwareFingerprint: 'FP-LENOVO-999',
        status: DeviceActivationStatus.pendingApproval,
        registeredByUserId: 'usr-1',
        registeredByName: 'Sita Sharma',
        otpHash: 'otp_hash_val',
        otpExpiresAt: now.add(const Duration(minutes: 10)),
        registeredAt: now,
      );

      final map = dev.toMap();
      final fromMap = DeviceModel.fromMap(map);

      expect(fromMap.deviceId, dev.deviceId);
      expect(fromMap.deviceName, dev.deviceName);
      expect(fromMap.hardwareFingerprint, dev.hardwareFingerprint);
      expect(fromMap.status, DeviceActivationStatus.pendingApproval);
      expect(fromMap.registeredByName, 'Sita Sharma');
    });
  });
}
