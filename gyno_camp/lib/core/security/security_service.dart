import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../services/session_service.dart';

class SecurityService {
  /// Generates a SHA-256 hash string for any input string
  static String hashSha256(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Hashes a 4-6 digit App PIN with a unique salt
  static String hashPin(String pin, {String salt = 'gyno_camp_salt_2026'}) {
    final bytes = utf8.encode('$salt:$pin:$salt');
    return sha256.convert(bytes).toString();
  }

  /// Verifies entered PIN against stored hashed PIN
  static bool verifyPin(String enteredPin, String storedHash, {String salt = 'gyno_camp_salt_2026'}) {
    final computedHash = hashPin(enteredPin, salt: salt);
    return computedHash == storedHash;
  }

  /// Generates a deterministic or persistent installation Hardware Fingerprint
  static String generateDeviceFingerprint({
    String? brand,
    String? model,
    String? serial,
    String? installToken,
  }) {
    if (brand != null || model != null || serial != null) {
      final raw = '${brand ?? "Samsung"}-${model ?? "Galaxy Tab A9"}-${serial ?? "GC-TAB-001"}-org.gynocamp.nepal';
      return hashSha256(raw).substring(0, 32).toUpperCase();
    }
    final token = installToken ?? SessionService.current?.getOrCreateDeviceInstallToken() ?? 'GC-DEV-DEFAULT';
    final raw = '$token-org.gynocamp.nepal';
    return hashSha256(raw).substring(0, 32).toUpperCase();
  }

  /// Generates a 6-digit numerical OTP
  static String generateOtp() {
    final random = Random.secure();
    final otp = 100000 + random.nextInt(900000);
    return otp.toString();
  }

  /// Generates a tamper-evident cryptographic hash for an audit record
  static String generateAuditHash({
    required String logId,
    required String userId,
    required String action,
    required String timestamp,
    required String details,
    String? previousHash,
  }) {
    final payload = '$logId|$userId|$action|$timestamp|$details|${previousHash ?? 'GENESIS'}';
    return hashSha256(payload);
  }
}
