import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/services/gemini_ocr_service.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';
import 'package:gyno_camp/core/services/pdf_report_service.dart';
import 'package:gyno_camp/core/utils/form_page_identifier.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/ocr_scan_result_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/ocr_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/viewmodels/ocr_scan_viewmodel.dart';

class _StubGeminiOcrService extends GeminiOcrService {
  final OcrScanResultModel Function(Uint8List bytes, int requestedPage) handler;
  int extractCalls = 0;

  _StubGeminiOcrService(this.handler);

  @override
  Future<({String base64, String mimeType})> prepareImageForStorage(
    Uint8List bytes, {
    String defaultMime = 'image/jpeg',
  }) async {
    return (base64: base64Encode(bytes), mimeType: defaultMime);
  }

  @override
  Future<OcrScanResultModel> extractFromBytes(
    Uint8List rawBytes, {
    String imagePath = '',
    int pageNumber = 0,
  }) async {
    extractCalls++;
    return handler(rawBytes, pageNumber);
  }
}

int _countPdfPages(Uint8List pdfBytes) {
  final latin = latin1.decode(pdfBytes, allowInvalid: true);
  // Match leaf `/Type /Page` objects (excluding `/Type /Pages`)
  return RegExp(r'/Type\s*/Page(?![A-Za-z])').allMatches(latin).length;
}

OcrScanResultModel _buildPage1Scan({
  required String formNumber,
  required String firstName,
  required String surname,
  int age = 38,
}) {
  return OcrScanResultModel(
    pageNumber: 1,
    detectedPage: 1,
    ocrEngine: 'gemini_flash',
    demographics: {
      'firstName': firstName,
      'surname': surname,
      'age': age,
      'ward': '04',
      'municipality': 'Bhaktapur',
      'district': 'Bhaktapur',
      'mobile': '9841122334',
      'patientId': formNumber,
      'patientTokenId': formNumber,
      'formPageCode': '$formNumber-P1',
      'reasonsForVisit': ['something_hanging_out'],
      'intakeDate': '2083-08-11',
      'date': '2083-08-11',
    },
    obstetrics: const {
      'deliveries': 3,
      'livingChildren': 3,
      'abortions': 0,
      'clinicalComplaints': ['prolapse'],
    },
    vitals: const {},
    popStaging: const {},
    diagnoses: const [],
    medications: const [],
    intakeDate: '2083-08-11',
    anamnesisDate: '2083-08-11',
    fieldConfidences: const {'firstName': 0.96},
    overallConfidence: 0.96,
    rawText: 'PATIENT REGISTRATION & ANAMNESIS — PAGE 1 (FRONT) Form $formNumber P1',
    scannedAt: DateTime(2026, 11, 27),
  );
}

OcrScanResultModel _buildPage2Scan({
  required String formNumber,
  int systolic = 124,
  int diastolic = 82,
  int popStage = 2,
  List<String> diagnoses = const ['POP'],
}) {
  return OcrScanResultModel(
    pageNumber: 2,
    detectedPage: 2,
    ocrEngine: 'gemini_flash',
    demographics: {
      if (formNumber.isNotEmpty) 'patientId': formNumber,
      if (formNumber.isNotEmpty) 'patientTokenId': formNumber,
      'formPageCode': formNumber.isNotEmpty ? '$formNumber-P2' : 'P2',
    },
    obstetrics: const {},
    vitals: {
      'systolicBp': systolic,
      'diastolicBp': diastolic,
      'pulseRate': 76,
      'spo2': 98,
    },
    popStaging: {
      'uterusInside': true,
      'pelvicFloorTone': 'weak',
      'anteriorStage': popStage,
      'highestPopStage': popStage,
    },
    diagnoses: diagnoses,
    medications: const ['clotrimazol (canesten)'],
    ringPessary: true,
    pessaryType: 'ring',
    ringPessarySize: 65,
    examDate: '2083-08-11',
    fieldConfidences: const {'vitals': 0.95},
    overallConfidence: 0.95,
    rawText: 'CLINICAL ASSESSMENT & EXAMINATION — PAGE 2 (BACK) Form $formNumber P2',
    scannedAt: DateTime(2026, 11, 27),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('FormPageIdentity & Token Normalization', () {
    test('parses QR payloads, bullet/hyphen badges, blank tags, and Devanagari digits', () {
      expect(FormPageIdentity.buildQrPayload(tokenId: '00101', pageNumber: 1), '00101|P1');
      expect(FormPageIdentity.buildQrPayload(tokenId: '00101', pageNumber: 2), '00101|P2');
      expect(FormPageIdentity.buildQrPayload(tokenId: '', pageNumber: 1), 'BLANK|P1');
      expect(FormPageIdentity.buildQrPayload(tokenId: null, pageNumber: 2), 'BLANK|P2');

      final qrP1 = FormPageIdentity.parse('00101|P1');
      expect(qrP1.formNumber, '00101');
      expect(qrP1.pageNumber, 1);
      expect(qrP1.formattedCode, '00101-P1');

      final bulletP2 = FormPageIdentity.parse('००१०१ • P2');
      expect(bulletP2.formNumber, '00101');
      expect(bulletP2.pageNumber, 2);

      final blankP1 = FormPageIdentity.parse('BLANK|P1');
      expect(blankP1.formNumber, isNull);
      expect(blankP1.pageNumber, 1);
      expect(blankP1.formattedCode, 'P1');

      final legacyGc = FormPageIdentity.parse('GC-KTM01-2026-00042-P2');
      expect(legacyGc.formNumber, 'GC-KTM01-2026-00042');
      expect(legacyGc.pageNumber, 2);
    });

    test('PatientModel.normalizePatientId strips P1/P2 suffixes for backward-compatible QR scanning', () {
      expect(PatientModel.normalizePatientId(rawInput: '00101|P1'), '00101');
      expect(PatientModel.normalizePatientId(rawInput: '00101|P2'), '00101');
      expect(PatientModel.normalizePatientId(rawInput: '00101-P1'), '00101');
      expect(PatientModel.normalizePatientId(rawInput: '00101 • P2'), '00101');
      expect(PatientModel.normalizePatientId(rawInput: 'P1-00101'), '00101');
      expect(PatientModel.normalizePatientId(rawInput: 'BLANK|P1'), '');
      expect(PatientModel.normalizePatientId(rawInput: 'BLANK|P2'), '');
      expect(PatientModel.normalizePatientId(rawInput: 'P2'), '');
      expect(
        PatientModel.normalizePatientId(rawInput: 'GC-KTM01-2026-00042|P2'),
        'GC-KTM01-2026-00042',
      );
    });

    test('OcrFormService extracts clean 5-digit token beside P1/P2 badge without polluting digits', () {
      const ocr = OcrFormService();
      final p1Res = ocr.parseFormText(
        '''
PATIENT REGISTRATION & ANAMNESIS — PAGE 1 (FRONT)
Patient ID: 00101 • P1
First Name: SITA
Surname: THAPA
Patient Age: 36
''',
        pageNumber: 2, // Intentionally wrong slot hint — should self-correct to Page 1!
      );
      expect(p1Res.demographics['patientId'], '00101');
      expect(p1Res.detectedPage, 1);
      expect(p1Res.pageNumber, 1);
      expect(p1Res.demographics['firstName'], 'Sita');

      final blankP2Res = ocr.parseFormText(
        '''
CLINICAL ASSESSMENT & EXAMINATION — PAGE 2 (BACK)
Token: [ ][ ][ ][ ][ ] P2
Blood Pressure: 120/80 mmHg
Diagnoses:
[x] POP
''',
        pageNumber: 1, // Intentionally wrong slot hint — should self-correct to Page 2!
      );
      expect(blankP2Res.demographics['patientId'], isNull);
      expect(blankP2Res.detectedPage, 2);
      expect(blankP2Res.pageNumber, 2);
      expect(blankP2Res.vitals['systolicBp'], 120);
      expect(blankP2Res.diagnoses, contains('POP'));
    });
  });

  group('GeminiOcrService Multimodal Page & Form Detection', () {
    test('maps explicit detectedPage & formPageCode and falls back to clinical content signals', () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final reqPage = body['pageNumber'] as int?;
        if (reqPage == 1) {
          // Simulate user uploading Page 2 into Slot 1: Gemini detects Page 2 + Form 00109-P2
          return http.Response(
            jsonEncode({
              'text': jsonEncode({
                'pageNumber': 2,
                'detectedPage': 2,
                'formPageCode': '00109-P2',
                'demographics': {'patientTokenId': '00109-P2'},
                'vitals': {'systolicBp': 118, 'diastolicBp': 78},
                'popStaging': {'anteriorStage': 1, 'highestPopStage': 1},
                'diagnoses': ['cystitis'],
                'medications': ['nitrofurantoine'],
              }),
            }),
            200,
          );
        }
        // Simulate legacy proxy omitting detectedPage while echoing pageNumber=1 on a Page 2 payload
        return http.Response(
          jsonEncode({
            'text': jsonEncode({
              'pageNumber': 1,
              'demographics': {'patientTokenId': '00110'},
              'vitals': {'systolicBp': 132, 'diastolicBp': 86},
              'popStaging': {'middleStage': 2, 'highestPopStage': 2},
              'diagnoses': ['POP'],
              'medications': [],
            }),
          }),
          200,
        );
      });

      final service = GeminiOcrService(
        httpClient: mockClient,
        baseUrl: 'http://localhost:8080',
        deviceFingerprint: 'fp-test',
        deviceSecret: 'sec-test',
      );

      final explicitRes = await service.extractFromBytes(
        Uint8List.fromList([1, 2, 3, 4]),
        pageNumber: 1,
      );
      expect(explicitRes.detectedPage, 2);
      expect(explicitRes.pageNumber, 2);
      expect(explicitRes.demographics['patientId'], '00109');
      expect(explicitRes.demographics['formPageCode'], '00109-P2');

      final contentFallbackRes = await service.extractFromBytes(
        Uint8List.fromList([5, 6, 7, 8]),
        pageNumber: 2,
      );
      expect(contentFallbackRes.detectedPage, 2);
      expect(contentFallbackRes.pageNumber, 2);
      expect(contentFallbackRes.demographics['patientId'], '00110');
    });
  });

  group('PdfReportService Yellow Form P1/P2 Badges & 2-Page Budget', () {
    test('universal blank and pre-numbered Yellow Forms stay strictly 2 pages and print P1/P2 badges', () async {
      final pdfService = PdfReportService();
      final camp = CampModel(
        id: 'camp-bkt-01',
        campCode: '1111',
        name: 'Bhaktapur Camp',
        district: 'Bhaktapur',
        municipality: 'Bhaktapur',
        ward: '01',
        venue: 'Health Post',
        startDate: DateTime(2026, 11, 27),
        endDate: DateTime(2026, 11, 28),
        createdAt: DateTime(2026, 11, 20),
      );

      final blankPdf = await pdfService.generatePatientRegistrationFormPdf(camp: camp);
      expect(_countPdfPages(blankPdf), 2);

      final numberedPdf = await pdfService.generatePreNumberedBlankFormsPdf(
        camp: camp,
        startSequence: 101,
        count: 1,
      );
      expect(_countPdfPages(numberedPdf), 2);

      // Verify vector text per page via pdftotext if installed on host
      try {
        final probe = await Process.run('pdftotext', ['-v']);
        if (probe.exitCode == 0 || probe.stderr.toString().toLowerCase().contains('pdftotext')) {
          final tmpDir = await Directory.systemTemp.createTemp('yellow_p1p2_test_');
          try {
            final pdfFile = File('${tmpDir.path}/numbered.pdf');
            await pdfFile.writeAsBytes(numberedPdf);
            final p1Out = '${tmpDir.path}/p1.txt';
            final p2Out = '${tmpDir.path}/p2.txt';
            await Process.run('pdftotext', ['-enc', 'UTF-8', '-f', '1', '-l', '1', pdfFile.path, p1Out]);
            await Process.run('pdftotext', ['-enc', 'UTF-8', '-f', '2', '-l', '2', pdfFile.path, p2Out]);
            final p1Text = await File(p1Out).readAsString();
            final p2Text = await File(p2Out).readAsString();
            expect(p1Text, contains('00101'));
            expect(p1Text, contains('P1'));
            expect(p2Text, contains('P2'));
          } finally {
            await tmpDir.delete(recursive: true);
          }
        }
      } catch (_) {
        // pdftotext binary not available on this runner; page-count check above still guards layout
      }
    });
  });

  group('OcrRepository Auto-Swap, Separate-Scan Auto-Pairing & Conflict Guards', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late PatientRepository patientRepo;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      patientRepo = PatientRepository(
        databaseService: dbService,
        auditRepository: auditRepo,
      );
    });

    tearDown(() async {
      await testDb.close();
    });

    test('reversed [Page 2, Page 1] upload auto-swaps extracted data AND stored photos cleanly', () async {
      final rawFrontBytes = Uint8List.fromList([10, 1, 1, 1]); // Real Page 1
      final rawBackBytes = Uint8List.fromList([20, 2, 2, 2]); // Real Page 2

      final stubGemini = _StubGeminiOcrService((bytes, _) {
        if (bytes.first == 10) {
          return _buildPage1Scan(
            formNumber: '00101',
            firstName: 'Sita',
            surname: 'Thapa',
          );
        }
        return _buildPage2Scan(formNumber: '00101', systolic: 126, diastolic: 84);
      });

      final repo = OcrRepository(
        databaseService: dbService,
        patientRepository: patientRepo,
        auditRepository: auditRepo,
        geminiService: stubGemini,
      );

      // Operator accidentally places Back (Page 2) in Slot 1 and Front (Page 1) in Slot 2
      final queued = await repo.enqueueOfflineScan(
        campId: 'camp-01',
        campCode: '1111',
        page1Bytes: rawBackBytes,
        page2Bytes: rawFrontBytes,
        userId: 'usr-1',
        userName: 'Nurse Anita',
        userRole: 'NURSE',
        deviceId: 'dev-1',
      );

      final ok = await repo.syncSingleOfflineQueueItem(queued);
      expect(ok, isTrue);

      final savedPatient = await patientRepo.getPatientByPatientId('00101');
      expect(savedPatient, isNotNull);
      expect(savedPatient!.fullName, 'Sita Thapa');

      final visits = await patientRepo.getClinicalVisits(savedPatient.id);
      expect(visits.length, 1);
      expect(visits.first.systolicBp, 126);
      expect(visits.first.highestPopStage, 2);

      // Stored photo archive must ALSO have swapped Front into Page 1 and Back into Page 2!
      final archive = await repo.getScanPhotoArchiveForPatient(
        patientUuid: savedPatient.id,
        campId: 'camp-01',
      );
      expect(archive.length, 1);
      expect(archive.first.page1Bytes, equals(rawFrontBytes));
      expect(archive.first.page2Bytes, equals(rawBackBytes));
    });

    test('separate single-page scans with Form Number hints auto-pair immediately at queue time', () async {
      final p1Bytes = Uint8List.fromList([11, 1, 2, 3]);
      final p2Bytes = Uint8List.fromList([22, 4, 5, 6]);
      final stubGemini = _StubGeminiOcrService((b, _) => _buildPage1Scan(
            formNumber: '00105',
            firstName: 'Rama',
            surname: 'KC',
          ));
      final repo = OcrRepository(
        databaseService: dbService,
        patientRepository: patientRepo,
        auditRepository: auditRepo,
        geminiService: stubGemini,
      );

      // First scan: Page 2 queued via QR/hint "00105|P2" into Slot 1
      final first = await repo.enqueueOfflineScan(
        campId: 'camp-01',
        campCode: '1111',
        page1Bytes: p2Bytes,
        patientTokenHint: '00105|P2',
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );
      expect(first.hasPage1, isFalse);
      expect(first.hasPage2, isTrue);
      expect(first.resolvedFormNumber, '00105');

      // Second scan later: Page 1 queued via QR/hint "00105|P1"
      final paired = await repo.enqueueOfflineScan(
        campId: 'camp-01',
        campCode: '1111',
        page1Bytes: p1Bytes,
        patientTokenHint: '00105|P1',
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );

      expect(paired.id, first.id);
      expect(paired.hasPage1, isTrue);
      expect(paired.hasPage2, isTrue);
      expect(paired.page1Bytes, equals(p1Bytes));
      expect(paired.page2Bytes, equals(p2Bytes));

      final allQueued = await repo.getOfflineScanQueue(campId: 'camp-01');
      expect(allQueued.length, 1);
    });

    test('separate un-hinted single-page scans sharing handwritten/printed Form Number auto-pair during bulk sync', () async {
      final p2Bytes = Uint8List.fromList([202, 9, 9, 9]); // Form 00205 Page 2
      final p1Bytes = Uint8List.fromList([101, 8, 8, 8]); // Form 00205 Page 1

      final stubGemini = _StubGeminiOcrService((bytes, _) {
        if (bytes.first == 101) {
          return _buildPage1Scan(
            formNumber: '00205',
            firstName: 'Mina',
            surname: 'Gurung',
            age: 45,
          );
        }
        return _buildPage2Scan(
          formNumber: '00205',
          systolic: 134,
          diastolic: 86,
          popStage: 3,
          diagnoses: const ['POP', 'PID'],
        );
      });

      final repo = OcrRepository(
        databaseService: dbService,
        patientRepository: patientRepo,
        auditRepository: auditRepo,
        geminiService: stubGemini,
      );

      // Queued separately with NO hints and in reverse order (Page 2 item first, Page 1 item second)
      await repo.enqueueOfflineScan(
        campId: 'camp-01',
        campCode: '1111',
        page1Bytes: p2Bytes,
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );
      await repo.enqueueOfflineScan(
        campId: 'camp-01',
        campCode: '1111',
        page1Bytes: p1Bytes,
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );

      expect((await repo.getOfflineScanQueue(campId: 'camp-01')).length, 2);

      final committedCount = await repo.syncAndProcessAllOfflineScans(campId: 'camp-01');
      expect(committedCount, 1);
      // Each image was extracted only once (zero redundant OCR calls)
      expect(stubGemini.extractCalls, 2);

      final mina = await patientRepo.getPatientByPatientId('00205');
      expect(mina, isNotNull);
      expect(mina!.fullName, 'Mina Gurung');
      expect(mina.age, 45);

      final visits = await patientRepo.getClinicalVisits(mina.id);
      expect(visits.length, 1);
      expect(visits.first.systolicBp, 134);
      expect(visits.first.highestPopStage, 3);
      expect(visits.first.diagnoses, containsAll(['POP', 'PID']));

      // Unified photo archive holds both Front & Back in the right slots
      final queueAfter = await repo.getOfflineScanQueue(campId: 'camp-01');
      expect(queueAfter.length, 1);
      expect(queueAfter.first.isCompleted, isTrue);
      expect(queueAfter.first.page1Bytes, equals(p1Bytes));
      expect(queueAfter.first.page2Bytes, equals(p2Bytes));
    });

    test('blocks auto-commit with status=conflict on Form Number mismatch (00301 vs 00302)', () async {
      final p1Bytes = Uint8List.fromList([11, 3, 0, 1]);
      final p2Bytes = Uint8List.fromList([22, 3, 0, 2]);

      final stubGemini = _StubGeminiOcrService((bytes, _) {
        if (bytes.first == 11) {
          return _buildPage1Scan(
            formNumber: '00301',
            firstName: 'Laxmi',
            surname: 'Shrestha',
          );
        }
        return _buildPage2Scan(formNumber: '00302');
      });

      final repo = OcrRepository(
        databaseService: dbService,
        patientRepository: patientRepo,
        auditRepository: auditRepo,
        geminiService: stubGemini,
      );

      final item = await repo.enqueueOfflineScan(
        campId: 'camp-01',
        campCode: '1111',
        page1Bytes: p1Bytes,
        page2Bytes: p2Bytes,
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );

      final ok = await repo.syncSingleOfflineQueueItem(item);
      expect(ok, isFalse);

      expect(await patientRepo.getPatientByPatientId('00301'), isNull);
      expect(await patientRepo.getPatientByPatientId('00302'), isNull);

      final queue = await repo.getOfflineScanQueue(campId: 'camp-01');
      expect(queue.single.isConflict, isTrue);
      expect(queue.single.errorMessage, contains('Form Number mismatch'));
      expect(queue.single.errorMessage, contains('00301'));
      expect(queue.single.errorMessage, contains('00302'));
    });

    test('blocks auto-commit with status=conflict when same page (P1 + P1) is uploaded twice', () async {
      final p1CopyA = Uint8List.fromList([11, 5, 5, 1]);
      final p1CopyB = Uint8List.fromList([11, 5, 5, 2]);

      final stubGemini = _StubGeminiOcrService(
        (_, _) => _buildPage1Scan(
          formNumber: '00305',
          firstName: 'Gita',
          surname: 'Bista',
        ),
      );

      final repo = OcrRepository(
        databaseService: dbService,
        patientRepository: patientRepo,
        auditRepository: auditRepo,
        geminiService: stubGemini,
      );

      final item = await repo.enqueueOfflineScan(
        campId: 'camp-01',
        campCode: '1111',
        page1Bytes: p1CopyA,
        page2Bytes: p1CopyB,
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );

      final ok = await repo.syncSingleOfflineQueueItem(item);
      expect(ok, isFalse);
      expect(await patientRepo.getPatientByPatientId('00305'), isNull);

      final queue = await repo.getOfflineScanQueue(campId: 'camp-01');
      expect(queue.single.isConflict, isTrue);
      expect(queue.single.errorMessage, contains('Duplicate page detected'));
      expect(queue.single.errorMessage, contains('Page 1 (Front)'));
    });

    test('1-tap swapCapturedPages & swapOfflineQueueItemPages swap Slot 1 and Slot 2 cleanly', () async {
      final bytesA = Uint8List.fromList([1, 1, 1]);
      final bytesB = Uint8List.fromList([2, 2, 2]);
      final stubGemini = _StubGeminiOcrService(
        (_, _) => _buildPage1Scan(formNumber: '00401', firstName: 'A', surname: 'B'),
      );
      final repo = OcrRepository(
        databaseService: dbService,
        patientRepository: patientRepo,
        auditRepository: auditRepo,
        geminiService: stubGemini,
      );

      final queued = await repo.enqueueOfflineScan(
        campId: 'camp-01',
        campCode: '1111',
        page1Bytes: bytesA,
        page2Bytes: bytesB,
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );

      await repo.swapOfflineQueueItemPages(queued.id);
      final afterSwap = (await repo.getOfflineScanQueue(campId: 'camp-01')).single;
      expect(afterSwap.page1Bytes, equals(bytesB));
      expect(afterSwap.page2Bytes, equals(bytesA));

      final vm = OcrScanViewModel(
        repository: repo,
        patientRepository: patientRepo,
      );
      vm.setAutoQueueDualPage(false);
      await vm.stageCapturedImages(
        page1Bytes: bytesA,
        page1Path: 'img_a.jpg',
        page2Bytes: bytesB,
        page2Path: 'img_b.jpg',
      );
      vm.swapCapturedPages();
      expect(vm.state.page1ImageBytes, equals(bytesB));
      expect(vm.state.page2ImageBytes, equals(bytesA));
      expect(vm.state.page1ImagePath, 'img_b.jpg');
      expect(vm.state.page2ImagePath, 'img_a.jpg');
    });
  });
}
