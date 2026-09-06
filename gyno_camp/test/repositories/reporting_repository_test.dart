import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/database/database_tables.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/reporting_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ReportingRepository SQLite Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late ReportingRepository reportingRepo;
    late Directory tempDir;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      reportingRepo = ReportingRepository(
        databaseService: dbService,
        auditRepository: auditRepo,
      );
      tempDir = Directory.systemTemp.createTempSync('gynocamp_test_reports_');
    });

    tearDown(() async {
      await testDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('getCampSummary fetches records from SQLite and aggregates metrics', () async {
      // 1. Seed camp
      final camp = CampModel(
        id: 'camp-rep-01',
        campCode: 'REP01',
        name: 'Kathmandu Health Camp',
        district: 'Kathmandu',
        municipality: 'Budhanilkantha',
        ward: '03',
        venue: 'Health Center',
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 5),
        createdAt: DateTime(2026, 3, 1),
      );
      await testDb.insert(DatabaseTables.tableCamps, camp.toMap());

      // 2. Seed patients
      final p1 = PatientModel(
        id: 'pat-rep-01',
        patientId: 'GC-REP01-2026-0001',
        campId: 'camp-rep-01',
        campCode: 'REP01',
        intakeDate: DateTime(2026, 3, 2),
        firstName: 'Laxmi',
        surname: 'Tamang',
        age: 38,
        ward: '03',
        mobile: '9841000111',
        createdByUserId: 'usr-1',
        createdByDeviceId: 'dev-1',
        createdAt: DateTime.now(),
      );
      await testDb.insert(DatabaseTables.tablePatients, p1.toMap());

      // 3. Seed clinical visit
      final v1 = ClinicalVisitModel(
        id: 'vis-rep-01',
        patientId: 'GC-REP01-2026-0001',
        campId: 'camp-rep-01',
        visitDate: DateTime(2026, 3, 2),
        popAnteriorStage: 2,
        popMiddleStage: 1,
        highestPopStage: 2,
        diagnoses: ['PID'],
        medications: ['Ciprofloxacin 500mg'],
        createdByUserId: 'usr-1',
        createdAt: DateTime.now(),
      );
      await testDb.insert(DatabaseTables.tableClinicalVisits, v1.toMap());

      // Test specific camp summary
      final summary = await reportingRepo.getCampSummary(campId: 'camp-rep-01');
      expect(summary.totalPatientsRegistered, 1);
      expect(summary.totalVisitsRecorded, 1);
      expect(summary.campCode, 'REP01');
      expect(summary.significantPopCount, 1);
      expect(summary.diagnosisCounts['PID'], 1);

      // Test all camps summary
      final allSummary = await reportingRepo.getCampSummary(campId: 'all');
      expect(allSummary.totalPatientsRegistered, 1);
      expect(allSummary.totalVisitsRecorded, 1);
    });

    test('generatePdfReport and generateExcelReport produce valid binaries', () async {
      final summary = await reportingRepo.getCampSummary(campId: 'all');

      final pdfBytes = await reportingRepo.generatePdfReport(summary);
      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(500));

      final excelBytes = await reportingRepo.generateExcelReport(summary);
      expect(excelBytes, isNotEmpty);
      expect(excelBytes.length, greaterThan(300));
    });

    test('saveReportToFile writes binary bytes to target directory', () async {
      final bytes = [1, 2, 3, 4, 5];
      final path = await reportingRepo.saveReportToFile(
        bytes: bytes,
        filename: 'test_report.bin',
        targetDirectoryPath: tempDir.path,
      );

      expect(File(path).existsSync(), isTrue);
      expect(File(path).readAsBytesSync(), equals(bytes));
    });

    test('auditReportExport records export event in SQLite audit log table', () async {
      await reportingRepo.auditReportExport(
        userId: 'usr-analyst-01',
        userName: 'Bikash Adhikari',
        userRole: 'DATA_ANALYST',
        deviceId: 'dev-tab-01',
        format: 'PDF',
        campCode: 'KTM01',
        totalPatients: 45,
        filePath: '/storage/reports/camp.pdf',
      );

      final logs = await testDb.query(DatabaseTables.tableAuditLogs);
      expect(logs.length, 1);
      expect(logs.first['action'], 'REPORT_PDF_EXPORTED');
      expect(logs.first['entity_id'], 'KTM01');
      expect(logs.first['user_name'], 'Bikash Adhikari');
    });
  });
}
