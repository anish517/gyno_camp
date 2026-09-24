import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../core/services/duplicate_detection_service.dart';
import '../core/services/http_central_api_service.dart';
import '../models/clinical_visit_model.dart';
import '../models/patient_model.dart';
import '../models/sync_payload_model.dart';
import 'audit_repository.dart';

abstract class IPatientRepository {
  Future<PatientModel> registerPatient(
    PatientModel patient, {
    required String createdByUserId,
    required String createdByUserName,
    required String createdByUserRole,
    required String deviceId,
  });
  Future<PatientModel> updatePatient(
    PatientModel patient, {
    required String updatedByUserId,
    required String updatedByUserName,
    required String updatedByUserRole,
    required String deviceId,
  });
  Future<List<PatientModel>> getPatientsByCamp([String? campId]);
  Future<PatientModel?> getPatientByPatientId(String patientId);
  Future<List<PatientModel>> searchPatients({required String campId, required String query});
  Future<DuplicateCheckResult> checkDuplicate({
    required String campId,
    required String firstName,
    required String surname,
    required int age,
    required String mobile,
    required String ward,
    String? spouseOrFatherName,
    String? maritalStatus,
  });
  Future<ClinicalVisitModel> saveClinicalVisit(
    ClinicalVisitModel visit, {
    required String createdByUserId,
    required String deviceId,
  });
  Future<List<ClinicalVisitModel>> getClinicalVisits(String patientId, {String? patientUuid});
  Future<ClinicalVisitModel?> getLatestClinicalVisit(String patientId, {String? patientUuid});
}

class PatientRepository implements IPatientRepository {
  final DatabaseService _databaseService;
  final AuditRepository _auditRepository;
  final bool _enableCentralSync;
  final Uuid _uuid = const Uuid();

  PatientRepository({
    DatabaseService? databaseService,
    AuditRepository? auditRepository,
    this._enableCentralSync = true,
  })  : _databaseService = databaseService ?? DatabaseService(),
        _auditRepository = auditRepository ?? AuditRepository();

  @override
  Future<PatientModel> registerPatient(
    PatientModel patient, {
    required String createdByUserId,
    required String createdByUserName,
    required String createdByUserRole,
    required String deviceId,
  }) async {
    final db = await _databaseService.database;

    // Generate formatted unique Patient ID if not present
    String finalPatientId = patient.patientId;
    if (finalPatientId.isEmpty) {
      final countResult = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM ${DatabaseTables.tablePatients} WHERE camp_id = ?',
        [patient.campId],
      ));
      int nextSeq = (countResult ?? 0) + 1;
      while (true) {
        final candidateId = PatientModel.generatePatientId(
          campCode: patient.campCode,
          sequenceNumber: nextSeq,
          year: patient.intakeDate.year,
        );
        final existing = await db.query(
          DatabaseTables.tablePatients,
          columns: ['id'],
          where: 'patient_id = ?',
          whereArgs: [candidateId],
          limit: 1,
        );
        if (existing.isEmpty) {
          finalPatientId = candidateId;
          break;
        }
        nextSeq++;
      }
    }

    final newPatient = patient.copyWith(
      id: patient.id.isEmpty ? _uuid.v4() : patient.id,
      patientId: finalPatientId,
      createdAt: DateTime.now(),
      createdByUserId: createdByUserId,
      createdByDeviceId: deviceId,
    );

    await db.insert(
      DatabaseTables.tablePatients,
      newPatient.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Auto-push to central server immediately (fire-and-forget)
    if (_enableCentralSync) unawaited(_pushPatientToServer(newPatient));

    // Increment camp patient count
    await db.rawUpdate(
      'UPDATE ${DatabaseTables.tableCamps} SET total_patients_registered = total_patients_registered + 1 WHERE id = ?',
      [patient.campId],
    );

    // Audit log — use real logged-in user name and role (not hardcoded)
    await _auditRepository.logActivity(
      userId: createdByUserId,
      userName: createdByUserName,
      userRole: createdByUserRole,
      action: AppConstants.auditActionPatientRegister,
      entityType: 'Patient',
      entityId: newPatient.patientId,
      detailsJson: '{"patientId":"${newPatient.patientId}","name":"${newPatient.fullName}","age":${newPatient.age},"ward":"${newPatient.ward}"}',
      deviceId: deviceId,
    );

    return newPatient;
  }

  @override
  Future<PatientModel> updatePatient(
    PatientModel patient, {
    required String updatedByUserId,
    required String updatedByUserName,
    required String updatedByUserRole,
    required String deviceId,
  }) async {
    final db = await _databaseService.database;

    final updatedPatient = patient.copyWith(
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    await db.update(
      DatabaseTables.tablePatients,
      updatedPatient.toMap(),
      where: 'id = ? OR patient_id = ?',
      whereArgs: [updatedPatient.id, updatedPatient.patientId],
    );

    // Auto-push updated patient to central server immediately (fire-and-forget)
    if (_enableCentralSync) unawaited(_pushPatientToServer(updatedPatient));

    // Audit log update
    await _auditRepository.logActivity(
      userId: updatedByUserId,
      userName: updatedByUserName,
      userRole: updatedByUserRole,
      action: AppConstants.auditActionPatientUpdate,
      entityType: 'Patient',
      entityId: updatedPatient.patientId,
      detailsJson: jsonEncode({
        'patientId': updatedPatient.patientId,
        'name': updatedPatient.fullName,
        'age': updatedPatient.age,
        'ward': updatedPatient.ward,
        'municipality': updatedPatient.municipality,
        'district': updatedPatient.district,
        'province': updatedPatient.province,
        'mobile': updatedPatient.mobile,
        'spouseOrFather': updatedPatient.spouseOrFatherName,
        'maritalStatus': updatedPatient.maritalStatus,
        'reasons': updatedPatient.reasonsForVisit,
      }),
      deviceId: deviceId,
    );

    return updatedPatient;
  }

  /// Fire-and-forget: push a single patient to the central sync server.
  /// Marks is_synced=1 in local SQLite on success. Silent on failure.
  Future<void> _pushPatientToServer(PatientModel patient) async {
    try {
      final apiService = HttpCentralApiService();
      if (!apiService.isConfigured || HttpCentralApiService.isServerCooldownActive) return;
      final payload = SyncPushPayload(
        deviceId: patient.createdByDeviceId,
        generatedAt: DateTime.now(),
        patients: [patient],
      );
      final response = await apiService.pushDelta(payload);
      if (response.success && response.syncedPatientIds.contains(patient.id)) {
        final db = await _databaseService.database;
        await db.rawUpdate(
          'UPDATE ${DatabaseTables.tablePatients} SET is_synced = 1, synced_at = ? WHERE id = ?',
          [DateTime.now().toIso8601String(), patient.id],
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PatientRepo] Fire-and-forget patient push failed: $e');
      }
    }
  }

  /// Fire-and-forget: push a single clinical visit to the central sync server.
  Future<void> _pushVisitToServer(ClinicalVisitModel visit) async {
    try {
      final apiService = HttpCentralApiService();
      if (!apiService.isConfigured || HttpCentralApiService.isServerCooldownActive) return;
      final payload = SyncPushPayload(
        deviceId: visit.createdByUserId.isNotEmpty ? visit.createdByUserId : 'unknown-device',
        generatedAt: DateTime.now(),
        clinicalVisits: [visit],
      );
      final response = await apiService.pushDelta(payload);
      if (response.success && response.syncedVisitIds.contains(visit.id)) {
        final db = await _databaseService.database;
        await db.rawUpdate(
          'UPDATE ${DatabaseTables.tableClinicalVisits} SET is_synced = 1 WHERE id = ?',
          [visit.id],
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PatientRepo] Fire-and-forget visit push failed: $e');
      }
    }
  }

  @override
  Future<List<PatientModel>> getPatientsByCamp([String? campId]) async {
    final db = await _databaseService.database;
    final bool filterCamp = campId != null && campId.isNotEmpty && campId != 'all';
    final query = '''
      SELECT p.*,
             CASE WHEN cv.patient_id IS NOT NULL THEN 1 ELSE 0 END AS has_clinical_visit,
             cv.highest_pop_stage,
             cv.diagnoses,
             cv.surgery_done,
             cv.surgery_type,
             cv.is_follow_up
      FROM ${DatabaseTables.tablePatients} p
      LEFT JOIN (
        SELECT cv1.patient_id, cv1.highest_pop_stage, cv1.diagnoses, cv1.surgery_done, cv1.surgery_type, cv1.is_follow_up
        FROM ${DatabaseTables.tableClinicalVisits} cv1
        WHERE cv1.visit_date = (
          SELECT MAX(cv2.visit_date)
          FROM ${DatabaseTables.tableClinicalVisits} cv2
          WHERE cv2.patient_id = cv1.patient_id
        )
      ) cv ON cv.patient_id = p.patient_id OR cv.patient_id = p.id
      ${filterCamp ? 'WHERE p.camp_id = ?' : 'WHERE p.camp_id IN (SELECT id FROM ${DatabaseTables.tableCamps})'}
      ORDER BY p.created_at DESC
    ''';
    final maps = await db.rawQuery(query, filterCamp ? [campId] : []);
    return maps.map((m) => PatientModel.fromMap(m)).toList();
  }

  @override
  Future<PatientModel?> getPatientByPatientId(String patientId) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      DatabaseTables.tablePatients,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return PatientModel.fromMap(maps.first);
  }

  @override
  Future<List<PatientModel>> searchPatients({required String campId, required String query}) async {
    final db = await _databaseService.database;
    final term = '%${query.trim().toLowerCase()}%';

    final maps = await db.rawQuery('''
      SELECT * FROM ${DatabaseTables.tablePatients}
      WHERE camp_id = ? AND (
        LOWER(patient_id) LIKE ? OR
        LOWER(first_name) LIKE ? OR
        LOWER(surname) LIKE ? OR
        mobile LIKE ? OR
        ward LIKE ?
      )
      ORDER BY created_at DESC
    ''', [campId, term, term, term, term, term]);

    return maps.map((m) => PatientModel.fromMap(m)).toList();
  }

  @override
  Future<DuplicateCheckResult> checkDuplicate({
    required String campId,
    required String firstName,
    required String surname,
    required int age,
    required String mobile,
    required String ward,
    String? spouseOrFatherName,
    String? maritalStatus,
  }) async {
    final existing = await getPatientsByCamp(campId);
    return DuplicateDetectionService.check(
      existingPatients: existing,
      firstName: firstName,
      surname: surname,
      age: age,
      mobile: mobile,
      ward: ward,
      spouseOrFatherName: spouseOrFatherName,
      maritalStatus: maritalStatus,
    );
  }

  @override
  Future<ClinicalVisitModel> saveClinicalVisit(
    ClinicalVisitModel visit, {
    required String createdByUserId,
    required String deviceId,
  }) async {
    final db = await _databaseService.database;
    final visitId = visit.id.isEmpty ? _uuid.v4() : visit.id;

    final newVisit = ClinicalVisitModel(
      id: visitId,
      patientId: visit.patientId,
      campId: visit.campId,
      visitDate: visit.visitDate,
      deliveries: visit.deliveries,
      livingChildren: visit.livingChildren,
      abortions: visit.abortions,
      anamnesisComplaints: visit.anamnesisComplaints,
      uterusInside: visit.uterusInside,
      vulvaRemarks: visit.vulvaRemarks,
      vaginaRemarks: visit.vaginaRemarks,
      cervixRemarks: visit.cervixRemarks,
      uterusRemarks: visit.uterusRemarks,
      pelvicFloorTone: visit.pelvicFloorTone,
      popAnteriorStage: visit.popAnteriorStage,
      popMiddleStage: visit.popMiddleStage,
      popPosteriorStage: visit.popPosteriorStage,
      highestPopStage: visit.highestPopStage,
      urineTest: visit.urineTest,
      pregnancyTest: visit.pregnancyTest,
      systolicBp: visit.systolicBp,
      diastolicBp: visit.diastolicBp,
      pulse: visit.pulse,
      spo2: visit.spo2,
      glucose: visit.glucose,
      ecgNotes: visit.ecgNotes,
      diagnoses: visit.diagnoses,
      counseling: visit.counseling,
      pessaryType: visit.pessaryType,
      pessarySize: visit.pessarySize,
      surgicalReferral: visit.surgicalReferral,
      medications: visit.medications,
      customMedication: visit.customMedication,
      followUpNeeded: visit.followUpNeeded,
      followUpDestination: visit.followUpDestination,
      outtakeNotes: visit.outtakeNotes,
      isFollowUp: visit.isFollowUp,
      followUpNotes: visit.followUpNotes,
      surgeryDone: visit.surgeryDone,
      surgeryType: visit.surgeryType,
      createdAt: DateTime.now(),
      createdByUserId: createdByUserId,
      isSynced: false,
    );

    await db.insert(
      DatabaseTables.tableClinicalVisits,
      newVisit.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Auto-push to central server immediately (fire-and-forget)
    if (_enableCentralSync) unawaited(_pushVisitToServer(newVisit));

    final detailMap = {
      'patientId': newVisit.patientId,
      'highestPop': newVisit.highestPopStage,
      'popStages': 'A${newVisit.popAnteriorStage} M${newVisit.popMiddleStage} P${newVisit.popPosteriorStage}',
      'bp': '${newVisit.systolicBp ?? "-"}/${newVisit.diastolicBp ?? "-"}',
      'pulse': newVisit.pulse,
      'spo2': newVisit.spo2,
      'glucose': newVisit.glucose,
      'diagnoses': newVisit.diagnoses,
      'medications': newVisit.medications,
      'followUpNeeded': newVisit.followUpNeeded,
      'followUpDestination': newVisit.followUpDestination,
      'outtakeNotes': newVisit.outtakeNotes,
    };

    final userRows = await db.query(
      DatabaseTables.tableUsers,
      where: 'id = ?',
      whereArgs: [createdByUserId],
      limit: 1,
    );
    final auditUserName = userRows.isNotEmpty ? userRows.first['name'] as String : 'Field Clinician';
    final auditUserRole = userRows.isNotEmpty ? userRows.first['role'] as String : AppConstants.roleDataTaker;

    await _auditRepository.logActivity(
      userId: createdByUserId,
      userName: auditUserName,
      userRole: auditUserRole,
      action: AppConstants.auditActionClinicalEntry,
      entityType: 'ClinicalVisit',
      entityId: newVisit.id,
      detailsJson: jsonEncode(detailMap),
      deviceId: deviceId,
    );

    return newVisit;
  }

  @override
  Future<List<ClinicalVisitModel>> getClinicalVisits(String patientId, {String? patientUuid}) async {
    final db = await _databaseService.database;
    final whereClause = patientUuid != null && patientUuid.isNotEmpty
        ? 'patient_id = ? OR patient_id = ?'
        : 'patient_id = ?';
    final whereArguments = patientUuid != null && patientUuid.isNotEmpty
        ? [patientId, patientUuid]
        : [patientId];

    var maps = await db.query(
      DatabaseTables.tableClinicalVisits,
      where: whereClause,
      whereArgs: whereArguments,
      orderBy: 'visit_date DESC',
    );

    // Fallback cross-check: if no direct match, check if patientId was UUID or patient_id in patients table
    if (maps.isEmpty) {
      final pat = await db.query(
        DatabaseTables.tablePatients,
        where: 'id = ? OR patient_id = ?',
        whereArgs: [patientId, patientId],
        limit: 1,
      );
      if (pat.isNotEmpty) {
        final altId = pat.first['patient_id'] as String?;
        final uuid = pat.first['id'] as String?;
        maps = await db.query(
          DatabaseTables.tableClinicalVisits,
          where: 'patient_id = ? OR patient_id = ?',
          whereArgs: [altId ?? '', uuid ?? ''],
          orderBy: 'visit_date DESC',
        );
      }
    }

    return maps.map((m) => ClinicalVisitModel.fromMap(m)).toList();
  }

  @override
  Future<ClinicalVisitModel?> getLatestClinicalVisit(String patientId, {String? patientUuid}) async {
    final list = await getClinicalVisits(patientId, patientUuid: patientUuid);
    if (list.isEmpty) return null;
    return list.first;
  }
}
