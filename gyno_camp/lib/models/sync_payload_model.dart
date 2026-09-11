import 'audit_log_model.dart';
import 'camp_model.dart';
import 'clinical_visit_model.dart';
import 'lookup_item_model.dart';
import 'patient_model.dart';
import 'user_model.dart';

class SyncPushPayload {
  final String deviceId;
  final DateTime generatedAt;
  final String tenantId;
  final List<PatientModel> patients;
  final List<ClinicalVisitModel> clinicalVisits;
  final List<AuditLogModel> auditLogs;

  const SyncPushPayload({
    required this.deviceId,
    required this.generatedAt,
    this.tenantId = 'tenant_bir_hospital',
    this.patients = const [],
    this.clinicalVisits = const [],
    this.auditLogs = const [],
  });

  bool get isEmpty => patients.isEmpty && clinicalVisits.isEmpty && auditLogs.isEmpty;
  int get totalRecords => patients.length + clinicalVisits.length + auditLogs.length;

  Map<String, dynamic> toMap() {
    return {
      'device_id': deviceId,
      'generated_at': generatedAt.toIso8601String(),
      'tenant_id': tenantId,
      'patients': patients.map((p) => p.toMap()).toList(),
      'clinical_visits': clinicalVisits.map((v) => v.toMap()).toList(),
      'audit_logs': auditLogs.map((a) => a.toMap()).toList(),
    };
  }

  factory SyncPushPayload.fromMap(Map<String, dynamic> map) {
    return SyncPushPayload(
      deviceId: map['device_id'] as String? ?? '',
      generatedAt: DateTime.tryParse(map['generated_at'] as String? ?? '') ?? DateTime.now(),
      tenantId: map['tenant_id'] as String? ?? 'tenant_bir_hospital',
      patients: (map['patients'] as List<dynamic>?)
              ?.map((p) => PatientModel.fromMap(p as Map<String, dynamic>))
              .toList() ??
          [],
      clinicalVisits: (map['clinical_visits'] as List<dynamic>?)
              ?.map((v) => ClinicalVisitModel.fromMap(v as Map<String, dynamic>))
              .toList() ??
          [],
      auditLogs: (map['audit_logs'] as List<dynamic>?)
              ?.map((a) => AuditLogModel.fromMap(a as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class SyncPushResponse {
  final bool success;
  final DateTime serverTimestamp;
  final List<String> syncedPatientIds;
  final List<String> syncedVisitIds;
  final List<String> syncedAuditLogIds;
  final List<String> conflictEntityIds;
  final String? message;

  const SyncPushResponse({
    required this.success,
    required this.serverTimestamp,
    this.syncedPatientIds = const [],
    this.syncedVisitIds = const [],
    this.syncedAuditLogIds = const [],
    this.conflictEntityIds = const [],
    this.message,
  });

  Map<String, dynamic> toMap() {
    return {
      'success': success,
      'server_timestamp': serverTimestamp.toIso8601String(),
      'synced_patient_ids': syncedPatientIds,
      'synced_visit_ids': syncedVisitIds,
      'synced_audit_log_ids': syncedAuditLogIds,
      'conflict_entity_ids': conflictEntityIds,
      'message': message,
    };
  }

  factory SyncPushResponse.fromMap(Map<String, dynamic> map) {
    return SyncPushResponse(
      success: map['success'] as bool? ?? false,
      serverTimestamp: DateTime.tryParse(map['server_timestamp'] as String? ?? '') ?? DateTime.now(),
      syncedPatientIds: List<String>.from(map['synced_patient_ids'] as List? ?? []),
      syncedVisitIds: List<String>.from(map['synced_visit_ids'] as List? ?? []),
      syncedAuditLogIds: List<String>.from(map['synced_audit_log_ids'] as List? ?? []),
      conflictEntityIds: List<String>.from(map['conflict_entity_ids'] as List? ?? []),
      message: map['message'] as String?,
    );
  }
}

class SyncPullResponse {
  final bool success;
  final DateTime serverTimestamp;
  final List<CampModel> camps;
  final List<LookupItemModel> lookupItems;
  final List<UserModel> users;
  final List<PatientModel> patients;
  final List<ClinicalVisitModel> clinicalVisits;
  final String? message;

  const SyncPullResponse({
    required this.success,
    required this.serverTimestamp,
    this.camps = const [],
    this.lookupItems = const [],
    this.users = const [],
    this.patients = const [],
    this.clinicalVisits = const [],
    this.message,
  });

  Map<String, dynamic> toMap() {
    return {
      'success': success,
      'server_timestamp': serverTimestamp.toIso8601String(),
      'camps': camps.map((c) => c.toMap()).toList(),
      'lookup_items': lookupItems.map((l) => l.toMap()).toList(),
      'users': users.map((u) => u.toMap()).toList(),
      'patients': patients.map((p) => p.toMap()).toList(),
      'clinical_visits': clinicalVisits.map((v) => v.toMap()).toList(),
      'message': message,
    };
  }

  factory SyncPullResponse.fromMap(Map<String, dynamic> map) {
    return SyncPullResponse(
      success: map['success'] as bool? ?? false,
      serverTimestamp: DateTime.tryParse(map['server_timestamp'] as String? ?? '') ?? DateTime.now(),
      camps: (map['camps'] as List<dynamic>?)
              ?.map((c) => CampModel.fromMap(c as Map<String, dynamic>))
              .toList() ??
          [],
      lookupItems: (map['lookup_items'] as List<dynamic>?)
              ?.map((l) => LookupItemModel.fromMap(l as Map<String, dynamic>))
              .toList() ??
          [],
      users: (map['users'] as List<dynamic>?)
              ?.map((u) => UserModel.fromMap(u as Map<String, dynamic>))
              .toList() ??
          [],
      patients: (map['patients'] as List<dynamic>?)
              ?.map((p) => PatientModel.fromMap(p as Map<String, dynamic>))
              .toList() ??
          [],
      clinicalVisits: (map['clinical_visits'] as List<dynamic>?)
              ?.map((v) => ClinicalVisitModel.fromMap(v as Map<String, dynamic>))
              .toList() ??
          [],
      message: map['message'] as String?,
    );
  }
}

class SyncHistoryItem {
  final String id;
  final DateTime timestamp;
  final int patientsPushed;
  final int visitsPushed;
  final int auditLogsPushed;
  final int campsPulled;
  final bool isSuccess;
  final String? errorMessage;

  const SyncHistoryItem({
    required this.id,
    required this.timestamp,
    this.patientsPushed = 0,
    this.visitsPushed = 0,
    this.auditLogsPushed = 0,
    this.campsPulled = 0,
    required this.isSuccess,
    this.errorMessage,
  });

  int get totalPushed => patientsPushed + visitsPushed + auditLogsPushed;
}
