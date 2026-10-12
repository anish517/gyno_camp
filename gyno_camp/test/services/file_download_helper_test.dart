import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/file_download_helper.dart';

void main() {
  group('ReportFilenameHelper Tests', () {
    final fixedDate = DateTime(2026, 4, 15, 14, 30);

    test('encounterSlip formats consistently with date and sanitized ID', () {
      final name = ReportFilenameHelper.encounterSlip('GC-DHN-2026-00042', fixedDate);
      expect(name, equals('EncounterSlip_GC-DHN-2026-00042_20260415.pdf'));
    });

    test('encounterSlip handles special characters in ID', () {
      final name = ReportFilenameHelper.encounterSlip('PAT/001 #2', fixedDate);
      expect(name, equals('EncounterSlip_PAT_001__2_20260415.pdf'));
    });

    test('patientDossier formats consistently with date and sanitized ID', () {
      final name = ReportFilenameHelper.patientDossier('GC-KTM-2026-00100', fixedDate);
      expect(name, equals('PatientDossier_GC-KTM-2026-00100_20260415.pdf'));
    });

    test('campSummary formats with camp code and timestamp', () {
      final name = ReportFilenameHelper.campSummary('DHN', fixedDate);
      expect(name, equals('CampReport_DHN_20260415_1430.pdf'));
    });

    test('campExcelRegister formats with camp code and timestamp', () {
      final name = ReportFilenameHelper.campExcelRegister('DHN', fixedDate);
      expect(name, equals('CampRegister_DHN_20260415_1430.xlsx'));
    });

    test('auditTrailCsv and auditTrailJson format cleanly', () {
      final csv = ReportFilenameHelper.auditTrailCsv('PATIENT', fixedDate);
      expect(csv, equals('AuditTrail_patient_20260415_1430.csv'));

      final json = ReportFilenameHelper.auditTrailJson(fixedDate);
      expect(json, equals('AuditTrail_Vault_20260415_1430.json'));
    });

    test('databaseBackup formats cleanly', () {
      final backup = ReportFilenameHelper.databaseBackup(fixedDate);
      expect(backup, equals('Gynocamp_Backup_20260415_1430.json'));
    });
  });

  group('DownloadResult Tests', () {
    test('fromSavedPath constructs success DownloadResult with clean location', () {
      final res = DownloadResult.fromSavedPath(
        savedPath: '/downloads/EncounterSlip_001.pdf',
        filename: 'EncounterSlip_001.pdf',
        mimeType: 'application/pdf',
      );

      expect(res.isSuccess, isTrue);
      expect(res.filename, equals('EncounterSlip_001.pdf'));
      expect(res.mimeType, equals('application/pdf'));
    });
  });
}
