import '../core/security/security_service.dart';

class AuditLogModel {
  final String id;
  final String userId;
  final String userName;
  final String userRole;
  final String action; // USER_LOGIN, PATIENT_REGISTERED, CLINICAL_ENTRY_SAVED, etc.
  final String entityType; // User, Device, Camp, Patient, ClinicalVisit
  final String? entityId;
  final String detailsJson;
  final String deviceId;
  final DateTime timestamp;
  final String logHash;

  const AuditLogModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.action,
    required this.entityType,
    this.entityId,
    required this.detailsJson,
    required this.deviceId,
    required this.timestamp,
    required this.logHash,
  });

  /// Factory helper that automatically generates the cryptographic hash
  factory AuditLogModel.create({
    required String id,
    required String userId,
    required String userName,
    required String userRole,
    required String action,
    required String entityType,
    String? entityId,
    required String detailsJson,
    required String deviceId,
    DateTime? timestamp,
    String? previousHash,
  }) {
    final ts = timestamp ?? DateTime.now();
    final hash = SecurityService.generateAuditHash(
      logId: id,
      userId: userId,
      action: action,
      timestamp: ts.toIso8601String(),
      details: detailsJson,
      previousHash: previousHash,
    );

    return AuditLogModel(
      id: id,
      userId: userId,
      userName: userName,
      userRole: userRole,
      action: action,
      entityType: entityType,
      entityId: entityId,
      detailsJson: detailsJson,
      deviceId: deviceId,
      timestamp: ts,
      logHash: hash,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'user_name': userName,
      'user_role': userRole,
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'details_json': detailsJson,
      'device_id': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'log_hash': logHash,
    };
  }

  factory AuditLogModel.fromMap(Map<String, dynamic> map) {
    return AuditLogModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      userName: map['user_name'] as String,
      userRole: map['user_role'] as String,
      action: map['action'] as String,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String?,
      detailsJson: map['details_json'] as String? ?? '{}',
      deviceId: map['device_id'] as String? ?? '',
      timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
      logHash: map['log_hash'] as String? ?? '',
    );
  }
}
