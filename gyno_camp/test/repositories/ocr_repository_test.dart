import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/ocr_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('OcrRepository SQLite Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late PatientRepository patientRepo;
    late OcrRepository ocrRepo;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      patientRepo = PatientRepository(databaseService: dbService, auditRepository: auditRepo);
      ocrRepo = OcrRepository(
        ocrService: const OcrFormService(),
        patientRepository: patientRepo,
        auditRepository: auditRepo,
      );
    });

    tearDown(() async {
      await testDb.close();
    });

    test('processTextScan returns parsed scan result model with confidence', () async {
      final result = await ocrRepo.processTextScan(OcrFormService.sampleFullFormText);

      expect(result.demographics['firstName'], 'Maya');
      expect(result.demographics['surname'], 'Tamang');
      expect(result.vitals['systolicBp'], 130);
      expect(result.popStaging['highestPopStage'], 3);
      expect(result.overallConfidence, greaterThanOrEqualTo(0.80));
    });

    test('processDualPageScan processes Page 1 and Page 2 and merges results', () async {
      final page1File = XFile('test_samples/yellow_form_sample_page1.jpg');
      final page2File = XFile('test_samples/yellow_form_sample_page2.jpg');

      final result = await ocrRepo.processDualPageScan(page1File: page1File, page2File: page2File);

      expect(result.isDualPage, true);
      expect(result.demographics['firstName'], isNotNull);
      expect(result.demographics['surname'], isNotNull);
      expect(result.popStaging['highestPopStage'], isNotNull);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('commitVerifiedScan saves patient, clinical visit and cryptographic audit log', () async {
      final scan = await ocrRepo.processTextScan(OcrFormService.sampleFullFormText);

      final patient = await ocrRepo.commitVerifiedScan(
        verifiedScan: scan,
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-datataker-01',
        userName: 'Sita Sharma',
        deviceId: 'dev-tab-01',
      );

      // Verify Patient in SQLite
      expect(patient.patientId, startsWith('GC-KTM01-2026-'));
      expect(patient.fullName, 'Maya Tamang');
      expect(patient.ward, '04');

      // Verify Clinical Visit in SQLite
      final visits = await patientRepo.getClinicalVisits(patient.id);
      expect(visits.length, 1);
      final visit = visits.first;
      expect(visit.systolicBp, 130);
      expect(visit.diastolicBp, 85);
      expect(visit.highestPopStage, 3);
      expect(visit.diagnoses, contains('POP'));
      expect(visit.medications, contains('Metronidazole'));
      expect(visit.surgicalReferral, 'Scheer Memorial Hospital');

      // Verify Audit Log in SQLite
      final auditLogs = await auditRepo.getRecentLogs();
      final ocrAudit = auditLogs.firstWhere((log) => log.action == 'PATIENT_REGISTERED_VIA_OCR');
      expect(ocrAudit.userName, 'Sita Sharma');
      expect(ocrAudit.logHash, isNotEmpty);
    });
  });
}
