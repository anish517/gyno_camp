import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/security/security_service.dart';

void main() {
  group('SecurityService Tests', () {
    test('hashSha256 produces 64-character hex digest', () {
      final hash = SecurityService.hashSha256('test_string_123');
      expect(hash.length, 64);
      expect(hash, isNotEmpty);
    });

    test('hashPin and verifyPin correctly verifies matching and non-matching PINs', () {
      const pin = '1234';
      final hashed = SecurityService.hashPin(pin);

      expect(SecurityService.verifyPin('1234', hashed), isTrue);
      expect(SecurityService.verifyPin('9999', hashed), isFalse);
      expect(SecurityService.verifyPin('12345', hashed), isFalse);
    });

    test('generateDeviceFingerprint creates deterministic 32-char uppercase signature', () {
      final fp1 = SecurityService.generateDeviceFingerprint(
        brand: 'Samsung',
        model: 'Tab A9',
        serial: 'TAB-001',
      );

      final fp2 = SecurityService.generateDeviceFingerprint(
        brand: 'Samsung',
        model: 'Tab A9',
        serial: 'TAB-001',
      );

      expect(fp1.length, 32);
      expect(fp1, fp2); // Deterministic
      expect(fp1, fp1.toUpperCase());
    });

    test('generateOtp produces a valid 6-digit number string', () {
      for (int i = 0; i < 20; i++) {
        final otp = SecurityService.generateOtp();
        expect(otp.length, 6);
        final numVal = int.tryParse(otp);
        expect(numVal, isNotNull);
        expect(numVal! >= 100000 && numVal <= 999999, isTrue);
      }
    });

    test('generateAuditHash creates tamper-evident chained hash', () {
      final hash1 = SecurityService.generateAuditHash(
        logId: 'log-1',
        userId: 'usr-1',
        action: 'PATIENT_REGISTERED',
        timestamp: '2026-09-06T12:00:00Z',
        details: '{"patientId":"GC-001"}',
        previousHash: 'GENESIS',
      );

      expect(hash1.length, 64);

      // Same data produces identical hash
      final hash1Repeat = SecurityService.generateAuditHash(
        logId: 'log-1',
        userId: 'usr-1',
        action: 'PATIENT_REGISTERED',
        timestamp: '2026-09-06T12:00:00Z',
        details: '{"patientId":"GC-001"}',
        previousHash: 'GENESIS',
      );
      expect(hash1, hash1Repeat);

      // Any alteration changes hash
      final hashTampered = SecurityService.generateAuditHash(
        logId: 'log-1',
        userId: 'usr-1',
        action: 'PATIENT_REGISTERED',
        timestamp: '2026-09-06T12:00:00Z',
        details: '{"patientId":"GC-002_TAMPERED"}',
        previousHash: 'GENESIS',
      );
      expect(hash1, isNot(hashTampered));
    });
  });
}
