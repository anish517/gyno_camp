import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../core/services/central_api_service.dart';
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
  Future<List<PatientModel>> getPatientsByCamp([String? campId, List<String>? allowedCampIds]);
  Future<PatientModel?> getPatientByPatientId(String patientId);
  Future<bool> isPatientIdTaken(String patientId);
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
  Future<void> deletePatient(
    String patientIdOrUuid, {
    String deletedByUserId = 'usr-local',
    String deletedByUserName = 'Field Staff',
    String deletedByUserRole = 'DATA_TAKER',
    String deviceId = 'dev-local',
  });
  Future<void> deleteClinicalVisit(
    String visitId, {
    String deletedByUserId = 'usr-local',
    String deletedByUserName = 'Field Staff',
    String deletedByUserRole = 'DATA_TAKER',
    String deviceId = 'dev-local',
  });
  Future<ClinicalVisitModel> recordNurseSeenQuickVisit({
    required PatientModel patient,
    required String nurseName,
    List<String> attendingNurses = const [],
    String? treatmentLevel,
    String? notes,
    required String userId,
    required String deviceId,
  });
}

class PatientRepository implements IPatientRepository {
  final DatabaseService _databaseService;
  final AuditRepository _auditRepository;
  final ICentralApiService? _centralApiService;
  final bool _enableCentralSync;
  final Uuid _uuid = const Uuid();

  PatientRepository({
    DatabaseService? databaseService,
    AuditRepository? auditRepository,
    this._centralApiService,
    this._enableCentralSync = true,
  })  : _databaseService = databaseService ?? DatabaseService(),
        _auditRepository = auditRepository ?? AuditRepository();

  /// Computes the next available global 5-digit numeric sequence across all camps,
  /// ignoring historical 'GC-...' records so numbering continues seamlessly (e.g., 00001 -> 00121).
  Future<int> getNextAvailableSequenceNumber() async {
    final db = await _databaseService.database;
    final maxVal = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT MAX(CAST(patient_id AS INTEGER)) FROM ${DatabaseTables.tablePatients} "
      "WHERE patient_id GLOB '[0-9]*' AND patient_id NOT GLOB '*[^0-9]*'",
    ));
    int nextSeq = (maxVal ?? 0) + 1;
    if (nextSeq < 1) nextSeq = 1;
    while (true) {
      final candidateId = PatientModel.generatePatientId(sequenceNumber: nextSeq);
      final existing = await db.query(
        DatabaseTables.tablePatients,
        columns: ['id'],
        where: 'UPPER(patient_id) = ?',
        whereArgs: [candidateId.toUpperCase()],
        limit: 1,
      );
      if (existing.isEmpty) {
        return nextSeq;
      }
      nextSeq++;
    }
  }

  @override
  Future<bool> isPatientIdTaken(String patientId) async {
    final clean = patientId.trim().toUpperCase();
    if (clean.isEmpty) return false;
    final db = await _databaseService.database;
    final existing = await db.query(
      DatabaseTables.tablePatients,
      columns: ['id'],
      where: 'UPPER(patient_id) = ?',
      whereArgs: [clean],
      limit: 1,
    );
    return existing.isNotEmpty;
  }

  @override
  Future<PatientModel> registerPatient(
    PatientModel patient, {
    required String createdByUserId,
    required String createdByUserName,
    required String createdByUserRole,
    required String deviceId,
    bool pushToServer = true,
  }) async {
    final db = await _databaseService.database;

    // Normalize and resolve unique Patient ID
    String finalPatientId = PatientModel.normalizePatientId(
      rawInput: patient.patientId,
      campCode: patient.campCode,
      year: patient.intakeDate.year,
    );

    if (finalPatientId.isNotEmpty) {
      // Custom / pre-assigned / OCR token supplied - verify uniqueness
      final existing = await db.query(
        DatabaseTables.tablePatients,
        columns: ['id', 'first_name', 'surname'],
        where: 'UPPER(patient_id) = ?',
        whereArgs: [finalPatientId.toUpperCase()],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final prevName = '${existing.first['first_name'] ?? ''} ${existing.first['surname'] ?? ''}'.trim();
        throw Exception('Patient Token ID "$finalPatientId" is already registered to $prevName. Please verify token or leave blank to auto-generate.');
      }
    } else {
      // Auto-generate globally unique continuous 5-digit Patient ID across all camps
      final nextSeq = await getNextAvailableSequenceNumber();
      finalPatientId = PatientModel.generatePatientId(
        campCode: patient.campCode,
        sequenceNumber: nextSeq,
        year: patient.intakeDate.year,
      );
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

    // Auto-push to central server immediately (fire-and-forget) unless batched by caller
    if (_enableCentralSync && pushToServer) {
      unawaited(_pushSyncDelta(deviceId: deviceId, patients: [newPatient]));
    }

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
    bool pushToServer = true,
  }) async {
    final db = await _databaseService.database;

    // Look up previous patient_id by UUID so if the Token ID was edited on Page 1,
    // we also update clinical_visits.patient_id to prevent orphaned clinical visits.
    String? oldPatientId;
    if (patient.id.isNotEmpty) {
      final prevRows = await db.query(
        DatabaseTables.tablePatients,
        columns: ['patient_id'],
        where: 'id = ?',
        whereArgs: [patient.id],
        limit: 1,
      );
      if (prevRows.isNotEmpty) {
        oldPatientId = prevRows.first['patient_id'] as String?;
      }
    }

    final updatedPatient = patient.copyWith(
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    await db.update(
      DatabaseTables.tablePatients,
      updatedPatient.toMap(),
      where: 'id = ? OR patient_id = ? COLLATE NOCASE',
      whereArgs: [updatedPatient.id, oldPatientId ?? updatedPatient.patientId],
    );

    final tokenChanged = oldPatientId != null &&
        oldPatientId.trim().isNotEmpty &&
        oldPatientId.trim().toLowerCase() != updatedPatient.patientId.trim().toLowerCase();

    if (tokenChanged) {
      await db.rawUpdate(
        'UPDATE ${DatabaseTables.tableClinicalVisits} SET patient_id = ?, is_synced = 0 WHERE patient_id = ? COLLATE NOCASE OR patient_id = ?',
        [updatedPatient.patientId.trim(), oldPatientId.trim(), updatedPatient.id],
      );
      try {
        await db.rawUpdate(
          'UPDATE ${DatabaseTables.tableOfflineScanQueue} SET committed_patient_id = ?, patient_token_hint = ? WHERE committed_patient_uuid = ? OR LOWER(committed_patient_id) = LOWER(?)',
          [
            updatedPatient.patientId.trim(),
            updatedPatient.patientId.trim(),
            updatedPatient.id,
            oldPatientId.trim(),
          ],
        );
      } catch (_) {}
    }

    // Synchronize normalized treatment_level to clinical_visits as well if present
    final normTreatment = PatientModel.normalizeTreatmentLevel(updatedPatient.treatmentLevel);
    if (normTreatment != null) {
      await db.rawUpdate(
        'UPDATE ${DatabaseTables.tableClinicalVisits} SET treatment_level = ? WHERE patient_id = ? COLLATE NOCASE OR patient_id = ?',
        [normTreatment, updatedPatient.patientId, updatedPatient.id],
      );
    }

    // Auto-push updated patient (and its clinical visits if Token ID changed) to central server immediately
    if (_enableCentralSync && pushToServer) {
      final visitsToPush = tokenChanged
          ? await getClinicalVisits(
              updatedPatient.patientId,
              patientUuid: updatedPatient.id,
            )
          : const <ClinicalVisitModel>[];
      unawaited(
        _pushSyncDelta(
          deviceId: deviceId,
          patients: [updatedPatient],
          clinicalVisits: visitsToPush,
        ),
      );
    }

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

  /// Pushes a patient and its clinical visit together in one central sync payload
  /// so remote listeners never pull a patient without its committed visit.
  Future<void> pushPatientAndVisitToServer({
    required PatientModel patient,
    required ClinicalVisitModel visit,
    required String deviceId,
  }) async {
    if (!_enableCentralSync) return;
    await _pushSyncDelta(
      deviceId: deviceId,
      patients: [patient],
      clinicalVisits: [visit],
    );
  }

  /// Fire-and-forget / batched push of patients and/or clinical visits to central sync.
  /// Marks synced rows with `is_synced = 1` in local SQLite on success.
  Future<void> _pushSyncDelta({
    required String deviceId,
    List<PatientModel> patients = const [],
    List<ClinicalVisitModel> clinicalVisits = const [],
  }) async {
    if (patients.isEmpty && clinicalVisits.isEmpty) return;
    try {
      final apiService = _centralApiService ?? HttpCentralApiService();
      if (_centralApiService == null) {
        final httpApi = apiService as HttpCentralApiService;
        if (!httpApi.isConfigured || HttpCentralApiService.isServerCooldownActive) return;
      }
      final payload = SyncPushPayload(
        deviceId: deviceId,
        generatedAt: DateTime.now(),
        patients: patients,
        clinicalVisits: clinicalVisits,
      );
      final response = await apiService.pushDelta(payload);
      if (response.success) {
        final db = await _databaseService.database;
        final syncedAtIso = DateTime.now().toIso8601String();
        if (response.reassignedPatientIds.isNotEmpty) {
          for (final entry in response.reassignedPatientIds.entries) {
            final patUuid = entry.key.trim();
            final newTokenId = entry.value.trim();
            if (patUuid.isEmpty || newTokenId.isEmpty) continue;
            final prevRows = await db.query(
              DatabaseTables.tablePatients,
              columns: ['patient_id'],
              where: 'id = ?',
              whereArgs: [patUuid],
              limit: 1,
            );
            final oldTokenId = prevRows.isNotEmpty
                ? (prevRows.first['patient_id']?.toString().trim() ?? '')
                : '';
            await db.rawUpdate(
              'UPDATE ${DatabaseTables.tablePatients} SET patient_id = ? WHERE id = ?',
              [newTokenId, patUuid],
            );
            if (oldTokenId.isNotEmpty &&
                oldTokenId.toLowerCase() != newTokenId.toLowerCase()) {
              await db.rawUpdate(
                'UPDATE ${DatabaseTables.tableClinicalVisits} SET patient_id = ? WHERE patient_id = ? COLLATE NOCASE OR patient_id = ?',
                [newTokenId, oldTokenId, patUuid],
              );
              try {
                await db.rawUpdate(
                  'UPDATE ${DatabaseTables.tableOfflineScanQueue} SET committed_patient_id = ?, patient_token_hint = ? WHERE committed_patient_uuid = ? OR LOWER(committed_patient_id) = LOWER(?)',
                  [newTokenId, newTokenId, patUuid, oldTokenId],
                );
              } catch (_) {}
            }
          }
        }
        for (final patientId in response.syncedPatientIds) {
          await db.rawUpdate(
            'UPDATE ${DatabaseTables.tablePatients} SET is_synced = 1, synced_at = ? WHERE id = ?',
            [syncedAtIso, patientId],
          );
        }
        for (final visitId in response.syncedVisitIds) {
          await db.rawUpdate(
            'UPDATE ${DatabaseTables.tableClinicalVisits} SET is_synced = 1 WHERE id = ?',
            [visitId],
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PatientRepo] Fire-and-forget central push failed: $e');
      }
    }
  }

  @override
  Future<List<PatientModel>> getPatientsByCamp([String? campId, List<String>? allowedCampIds]) async {
    final db = await _databaseService.database;
    final bool filterCamp = campId != null && campId.isNotEmpty && campId != 'all';

    if (!filterCamp && allowedCampIds != null && allowedCampIds.isEmpty) {
      return [];
    }

    String whereClause;
    List<dynamic> whereArgs = [];
    if (filterCamp) {
      whereClause = 'WHERE p.camp_id = ?';
      whereArgs = [campId];
    } else if (allowedCampIds != null) {
      final placeholders = List.filled(allowedCampIds.length, '?').join(', ');
      whereClause = 'WHERE p.camp_id IN ($placeholders)';
      whereArgs = List.from(allowedCampIds);
    } else {
      whereClause = 'WHERE p.camp_id IN (SELECT id FROM ${DatabaseTables.tableCamps})';
    }

    final query = '''
      SELECT p.*,
             CASE WHEN cv.patient_id IS NOT NULL THEN 1 ELSE 0 END AS has_clinical_visit,
             cv.highest_pop_stage,
             cv.diagnoses,
             cv.surgery_done,
             cv.surgery_type,
             cv.is_follow_up,
             cv.primary_doctor_name,
             cv.attending_doctor_names,
             cv.primary_nurse_name,
             cv.attending_nurse_names,
             cv.medications,
             cv.custom_medication,
             cv.counseling,
             cv.pessary_type,
             cv.pessary_size,
             cv.surgical_referral,
             cv.anamnesis_json,
             CASE 
               WHEN p.treatment_level IS NOT NULL AND TRIM(p.treatment_level) != '' AND LOWER(TRIM(p.treatment_level)) NOT IN ('none', 'unassigned', 'null')
                 THEN p.treatment_level
               WHEN cv.treatment_level IS NOT NULL AND TRIM(cv.treatment_level) != '' AND LOWER(TRIM(cv.treatment_level)) NOT IN ('none', 'unassigned', 'null')
                 THEN cv.treatment_level
               ELSE NULL
             END AS treatment_level
      FROM ${DatabaseTables.tablePatients} p
      LEFT JOIN (
        SELECT cv1.patient_id, cv1.highest_pop_stage, cv1.diagnoses, cv1.surgery_done, cv1.surgery_type, cv1.is_follow_up,
               cv1.primary_doctor_name, cv1.attending_doctor_names,
               cv1.primary_nurse_name, cv1.attending_nurse_names,
               cv1.medications, cv1.custom_medication, cv1.counseling,
               cv1.pessary_type, cv1.pessary_size, cv1.surgical_referral, cv1.treatment_level, cv1.anamnesis_json
        FROM ${DatabaseTables.tableClinicalVisits} cv1
        WHERE cv1.visit_date = (
          SELECT MAX(cv2.visit_date)
          FROM ${DatabaseTables.tableClinicalVisits} cv2
          WHERE cv2.patient_id = cv1.patient_id
        )
      ) cv ON cv.patient_id = p.patient_id COLLATE NOCASE OR cv.patient_id = p.id
      $whereClause
      ORDER BY p.created_at DESC
    ''';
    final maps = await db.rawQuery(query, whereArgs);
    return maps.map((m) => PatientModel.fromMap(m)).toList();
  }

  @override
  Future<PatientModel?> getPatientByPatientId(String patientId) async {
    final trimmed = patientId.trim();
    if (trimmed.isEmpty) return null;
    final paddedCandidate = RegExp(r'^\d{1,8}$').hasMatch(trimmed)
        ? trimmed.padLeft(5, '0')
        : trimmed;
    final db = await _databaseService.database;
    final maps = await db.rawQuery('''
      SELECT p.*,
             CASE WHEN cv.patient_id IS NOT NULL THEN 1 ELSE 0 END AS has_clinical_visit,
             cv.highest_pop_stage,
             cv.diagnoses,
             cv.surgery_done,
             cv.surgery_type,
             cv.is_follow_up,
             cv.primary_doctor_name,
             cv.attending_doctor_names,
             cv.primary_nurse_name,
             cv.attending_nurse_names,
             cv.medications,
             cv.custom_medication,
             cv.counseling,
             cv.pessary_type,
             cv.pessary_size,
             cv.surgical_referral,
             cv.anamnesis_json,
             CASE 
               WHEN p.treatment_level IS NOT NULL AND TRIM(p.treatment_level) != '' AND LOWER(TRIM(p.treatment_level)) NOT IN ('none', 'unassigned', 'null')
                 THEN p.treatment_level
               WHEN cv.treatment_level IS NOT NULL AND TRIM(cv.treatment_level) != '' AND LOWER(TRIM(cv.treatment_level)) NOT IN ('none', 'unassigned', 'null')
                 THEN cv.treatment_level
               ELSE NULL
             END AS treatment_level
      FROM ${DatabaseTables.tablePatients} p
      LEFT JOIN (
        SELECT cv1.patient_id, cv1.highest_pop_stage, cv1.diagnoses, cv1.surgery_done, cv1.surgery_type, cv1.is_follow_up,
               cv1.primary_doctor_name, cv1.attending_doctor_names,
               cv1.primary_nurse_name, cv1.attending_nurse_names,
               cv1.medications, cv1.custom_medication, cv1.counseling,
               cv1.pessary_type, cv1.pessary_size, cv1.surgical_referral, cv1.treatment_level, cv1.anamnesis_json
        FROM ${DatabaseTables.tableClinicalVisits} cv1
        WHERE cv1.visit_date = (
          SELECT MAX(cv2.visit_date)
          FROM ${DatabaseTables.tableClinicalVisits} cv2
          WHERE cv2.patient_id = cv1.patient_id
        )
      ) cv ON cv.patient_id = p.patient_id COLLATE NOCASE OR cv.patient_id = p.id
      WHERE p.patient_id = ? COLLATE NOCASE OR p.patient_id = ? COLLATE NOCASE OR p.id = ?
      LIMIT 1
    ''', [trimmed, paddedCandidate, trimmed]);
    if (maps.isEmpty) return null;
    return PatientModel.fromMap(maps.first);
  }

  @override
  Future<List<PatientModel>> searchPatients({required String campId, required String query}) async {
    final db = await _databaseService.database;
    final term = '%${query.trim().toLowerCase()}%';

    final maps = await db.rawQuery('''
      SELECT p.*,
             CASE WHEN cv.patient_id IS NOT NULL THEN 1 ELSE 0 END AS has_clinical_visit,
             cv.highest_pop_stage,
             cv.diagnoses,
             cv.surgery_done,
             cv.surgery_type,
             cv.is_follow_up,
             cv.primary_doctor_name,
             cv.attending_doctor_names,
             cv.primary_nurse_name,
             cv.attending_nurse_names,
             cv.medications,
             cv.custom_medication,
             cv.counseling,
             cv.pessary_type,
             cv.pessary_size,
             cv.surgical_referral,
             cv.anamnesis_json,
             CASE 
               WHEN p.treatment_level IS NOT NULL AND TRIM(p.treatment_level) != '' AND LOWER(TRIM(p.treatment_level)) NOT IN ('none', 'unassigned', 'null')
                 THEN p.treatment_level
               WHEN cv.treatment_level IS NOT NULL AND TRIM(cv.treatment_level) != '' AND LOWER(TRIM(cv.treatment_level)) NOT IN ('none', 'unassigned', 'null')
                 THEN cv.treatment_level
               ELSE NULL
             END AS treatment_level
      FROM ${DatabaseTables.tablePatients} p
      LEFT JOIN (
        SELECT cv1.patient_id, cv1.highest_pop_stage, cv1.diagnoses, cv1.surgery_done, cv1.surgery_type, cv1.is_follow_up,
               cv1.primary_doctor_name, cv1.attending_doctor_names,
               cv1.primary_nurse_name, cv1.attending_nurse_names,
               cv1.medications, cv1.custom_medication, cv1.counseling,
               cv1.pessary_type, cv1.pessary_size, cv1.surgical_referral, cv1.treatment_level, cv1.anamnesis_json
        FROM ${DatabaseTables.tableClinicalVisits} cv1
        WHERE cv1.visit_date = (
          SELECT MAX(cv2.visit_date)
          FROM ${DatabaseTables.tableClinicalVisits} cv2
          WHERE cv2.patient_id = cv1.patient_id
        )
      ) cv ON cv.patient_id = p.patient_id COLLATE NOCASE OR cv.patient_id = p.id
      WHERE p.camp_id = ? AND (
        LOWER(p.patient_id) LIKE ? OR
        LOWER(p.first_name) LIKE ? OR
        LOWER(p.surname) LIKE ? OR
        p.mobile LIKE ? OR
        p.ward LIKE ?
      )
      ORDER BY p.created_at DESC
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
    bool pushToServer = true,
  }) async {
    final db = await _databaseService.database;
    final isUpdate = visit.id.isNotEmpty;
    final visitId = isUpdate ? visit.id : _uuid.v4();
    final now = DateTime.now();

    final newVisit = visit.copyWith(
      id: visitId,
      primaryDoctorName: visit.primaryDoctorName ?? (visit.attendingDoctorNames.isNotEmpty ? visit.attendingDoctorNames.first : null),
      attendingDoctorNames: visit.attendingDoctorNames.isNotEmpty
          ? visit.attendingDoctorNames
          : (visit.primaryDoctorName != null && visit.primaryDoctorName!.trim().isNotEmpty ? [visit.primaryDoctorName!.trim()] : const []),
      primaryNurseName: visit.primaryNurseName ?? (visit.attendingNurseNames.isNotEmpty ? visit.attendingNurseNames.first : null),
      attendingNurseNames: visit.attendingNurseNames.isNotEmpty
          ? visit.attendingNurseNames
          : (visit.primaryNurseName != null && visit.primaryNurseName!.trim().isNotEmpty ? [visit.primaryNurseName!.trim()] : const []),
      createdAt: isUpdate ? visit.createdAt : now,
      updatedAt: now,
      createdByUserId: createdByUserId,
      isSynced: false,
    );

    await db.insert(
      DatabaseTables.tableClinicalVisits,
      newVisit.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (newVisit.treatmentLevel != null && newVisit.treatmentLevel!.trim().isNotEmpty) {
      final normTreatment = PatientModel.normalizeTreatmentLevel(newVisit.treatmentLevel) ?? newVisit.treatmentLevel!.trim();
      await db.rawUpdate(
        'UPDATE ${DatabaseTables.tablePatients} SET treatment_level = ? WHERE patient_id = ? COLLATE NOCASE OR id = ?',
        [normTreatment, newVisit.patientId, newVisit.patientId],
      );
    }

    // Auto-push to central server immediately (fire-and-forget) unless batched by caller
    if (_enableCentralSync && pushToServer) {
      unawaited(_pushSyncDelta(deviceId: deviceId, clinicalVisits: [newVisit]));
    }

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

  @override
  Future<void> deletePatient(
    String patientIdOrUuid, {
    String deletedByUserId = 'usr-local',
    String deletedByUserName = 'Field Staff',
    String deletedByUserRole = 'DATA_TAKER',
    String deviceId = 'dev-local',
  }) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      DatabaseTables.tablePatients,
      where: 'id = ? OR patient_id = ? COLLATE NOCASE',
      whereArgs: [patientIdOrUuid, patientIdOrUuid],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final patientRow = rows.first;
    final patientUuid = patientRow['id'] as String;
    final patientTokenId = patientRow['patient_id'] as String;
    final campId = patientRow['camp_id'] as String? ?? '';
    final patientName = '${patientRow['first_name'] ?? ''} ${patientRow['surname'] ?? ''}'.trim();

    // Find all clinical visits for this patient to record tombstones as well
    final visitRows = await db.query(
      DatabaseTables.tableClinicalVisits,
      columns: ['id'],
      where: 'patient_id = ? COLLATE NOCASE OR patient_id = ?',
      whereArgs: [patientTokenId, patientUuid],
    );
    final visitIds = visitRows.map((v) => v['id'] as String).toList();
    final nowIso = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(
        DatabaseTables.tableClinicalVisits,
        where: 'patient_id = ? COLLATE NOCASE OR patient_id = ?',
        whereArgs: [patientTokenId, patientUuid],
      );
      await txn.delete(
        DatabaseTables.tablePatients,
        where: 'id = ? OR patient_id = ? COLLATE NOCASE',
        whereArgs: [patientUuid, patientTokenId],
      );

      if (campId.isNotEmpty) {
        await txn.rawUpdate(
          'UPDATE ${DatabaseTables.tableCamps} SET total_patients_registered = CASE WHEN total_patients_registered > 0 THEN total_patients_registered - 1 ELSE 0 END WHERE id = ?',
          [campId],
        );
      }

      // Queue deletion tombstones for server sync using immutable UUIDs only
      // (never tombstone reusable human Token IDs like GC-...-00047).
      await txn.insert(
        DatabaseTables.tableDeletedEntitiesQueue,
        {
          'id': 'del-pat-$patientUuid',
          'entity_type': 'patient',
          'entity_id': patientUuid,
          'deleted_at': nowIso,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final vid in visitIds) {
        await txn.insert(
          DatabaseTables.tableDeletedEntitiesQueue,
          {
            'id': 'del-vis-$vid',
            'entity_type': 'clinical_visit',
            'entity_id': vid,
            'deleted_at': nowIso,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    if (_enableCentralSync) {
      await _pushDeletionsToServer(
        deviceId: deviceId,
        deletedPatientIds: [patientUuid],
        deletedVisitIds: visitIds,
      );
    }

    await _auditRepository.logActivity(
      userId: deletedByUserId,
      userName: deletedByUserName,
      userRole: deletedByUserRole,
      action: AppConstants.auditActionPatientDelete,
      entityType: 'Patient',
      entityId: patientTokenId,
      detailsJson: jsonEncode({
        'patientUuid': patientUuid,
        'patientId': patientTokenId,
        'name': patientName,
        'deletedVisitsCount': visitIds.length,
      }),
      deviceId: deviceId,
    );
  }

  @override
  Future<void> deleteClinicalVisit(
    String visitId, {
    String deletedByUserId = 'usr-local',
    String deletedByUserName = 'Field Staff',
    String deletedByUserRole = 'DATA_TAKER',
    String deviceId = 'dev-local',
  }) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      DatabaseTables.tableClinicalVisits,
      where: 'id = ?',
      whereArgs: [visitId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final visitRow = rows.first;
    final patientId = visitRow['patient_id'] as String? ?? '';
    final nowIso = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(
        DatabaseTables.tableClinicalVisits,
        where: 'id = ?',
        whereArgs: [visitId],
      );
      await txn.insert(
        DatabaseTables.tableDeletedEntitiesQueue,
        {
          'id': 'del-vis-$visitId',
          'entity_type': 'clinical_visit',
          'entity_id': visitId,
          'deleted_at': nowIso,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    if (_enableCentralSync) {
      await _pushDeletionsToServer(
        deviceId: deviceId,
        deletedVisitIds: [visitId],
      );
    }

    await _auditRepository.logActivity(
      userId: deletedByUserId,
      userName: deletedByUserName,
      userRole: deletedByUserRole,
      action: AppConstants.auditActionClinicalVisitDelete,
      entityType: 'ClinicalVisit',
      entityId: visitId,
      detailsJson: jsonEncode({
        'visitId': visitId,
        'patientId': patientId,
      }),
      deviceId: deviceId,
    );
  }

  @override
  Future<ClinicalVisitModel> recordNurseSeenQuickVisit({
    required PatientModel patient,
    required String nurseName,
    List<String> attendingNurses = const [],
    String? treatmentLevel,
    String? notes,
    required String userId,
    required String deviceId,
  }) async {
    final existing = await getLatestClinicalVisit(patient.patientId, patientUuid: patient.id);
    final now = DateTime.now();
    final effectiveNurses = attendingNurses.isNotEmpty
        ? attendingNurses
        : (nurseName.trim().isNotEmpty ? [nurseName.trim()] : const <String>[]);

    if (existing != null) {
      final mergedNurses = <String>{
        ...existing.attendingNurseNames,
        ...effectiveNurses,
      }.where((n) => n.trim().isNotEmpty).toList();
      final updatedVisit = existing.copyWith(
        primaryNurseName: nurseName.trim().isNotEmpty ? nurseName.trim() : existing.primaryNurseName,
        attendingNurseNames: mergedNurses,
        treatmentLevel: treatmentLevel ?? existing.treatmentLevel ?? patient.treatmentLevel ?? 'counseling',
        outtakeNotes: (notes != null && notes.trim().isNotEmpty) ? notes.trim() : existing.outtakeNotes,
        outtakeDate: existing.outtakeDate ?? now,
        updatedAt: now,
      );
      return saveClinicalVisit(
        updatedVisit,
        createdByUserId: userId,
        deviceId: deviceId,
      );
    }

    final quickVisit = ClinicalVisitModel(
      id: 'vis-${_uuid.v4()}',
      patientId: patient.patientId,
      campId: patient.campId,
      tenantId: patient.tenantId,
      visitDate: now,
      anamnesisDate: patient.intakeDate,
      outtakeDate: now,
      primaryNurseName: nurseName.trim(),
      attendingNurseNames: effectiveNurses,
      treatmentLevel: treatmentLevel ?? patient.treatmentLevel ?? 'counseling',
      outtakeNotes: (notes != null && notes.trim().isNotEmpty) ? notes.trim() : 'Nurse consultation / triage completed.',
      createdAt: now,
      updatedAt: now,
      createdByUserId: userId,
    );
    return saveClinicalVisit(
      quickVisit,
      createdByUserId: userId,
      deviceId: deviceId,
    );
  }

  Future<void> _pushDeletionsToServer({
    required String deviceId,
    List<String> deletedPatientIds = const [],
    List<String> deletedVisitIds = const [],
  }) async {
    try {
      final apiService = _centralApiService ?? HttpCentralApiService();
      if (_centralApiService == null) {
        final httpApi = apiService as HttpCentralApiService;
        if (!httpApi.isConfigured || HttpCentralApiService.isServerCooldownActive) return;
      }
      final payload = SyncPushPayload(
        deviceId: deviceId,
        generatedAt: DateTime.now(),
        deletedPatientIds: deletedPatientIds,
        deletedVisitIds: deletedVisitIds,
      );
      final response = await apiService.pushDelta(payload);
      if (response.success) {
        final db = await _databaseService.database;
        await _databaseService.purgeConfirmedDeletedTombstones(
          db,
          entityType: 'patient',
          pushedIds: deletedPatientIds,
          confirmedIds: response.deletedPatientIds,
        );
        await _databaseService.purgeConfirmedDeletedTombstones(
          db,
          entityType: 'clinical_visit',
          pushedIds: deletedVisitIds,
          confirmedIds: response.deletedVisitIds,
        );
      }
    } catch (_) {}
  }
}
