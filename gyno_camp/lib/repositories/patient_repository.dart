import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../core/services/duplicate_detection_service.dart';
import '../models/clinical_visit_model.dart';
import '../models/patient_model.dart';
import 'audit_repository.dart';

abstract class IPatientRepository {
  Future<PatientModel> registerPatient(
    PatientModel patient, {
    required String createdByUserId,
    required String deviceId,
  });
  Future<List<PatientModel>> getPatientsByCamp(String campId);
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
  final Uuid _uuid = const Uuid();

  PatientRepository({
    DatabaseService? databaseService,
    AuditRepository? auditRepository,
  })  : _databaseService = databaseService ?? DatabaseService(),
        _auditRepository = auditRepository ?? AuditRepository();

  @override
  Future<PatientModel> registerPatient(
    PatientModel patient, {
    required String createdByUserId,
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
      final nextSeq = (countResult ?? 0) + 1;
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

    // Increment camp patient count
    await db.rawUpdate(
      'UPDATE ${DatabaseTables.tableCamps} SET total_patients_registered = total_patients_registered + 1 WHERE id = ?',
      [patient.campId],
    );

    // Audit log
    await _auditRepository.logActivity(
      userId: createdByUserId,
      userName: 'Field Nurse',
      userRole: AppConstants.roleDataTaker,
      action: AppConstants.auditActionPatientRegister,
      entityType: 'Patient',
      entityId: newPatient.patientId,
      detailsJson: '{"patientId":"${newPatient.patientId}","name":"${newPatient.fullName}","age":${newPatient.age},"ward":"${newPatient.ward}"}',
      deviceId: deviceId,
    );

    return newPatient;
  }

  @override
  Future<List<PatientModel>> getPatientsByCamp(String campId) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      DatabaseTables.tablePatients,
      where: 'camp_id = ?',
      whereArgs: [campId],
      orderBy: 'created_at DESC',
    );
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
      createdAt: DateTime.now(),
      createdByUserId: createdByUserId,
      isSynced: false,
    );

    await db.insert(
      DatabaseTables.tableClinicalVisits,
      newVisit.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

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

    await _auditRepository.logActivity(
      userId: createdByUserId,
      userName: 'Field Doctor / Nurse',
      userRole: AppConstants.roleDataTaker,
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
