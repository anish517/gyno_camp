import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gyno_camp/core/constants/app_constants.dart';
import 'package:gyno_camp/core/services/gemini_ocr_service.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/ocr_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// Builds a client wired to a fake GynoCamp server (the proxy), never to Google.
  GeminiOcrService buildService(http.Client client) => GeminiOcrService(
        httpClient: client,
        baseUrl: 'http://test-server:8080',
        deviceFingerprint: 'TESTFINGERPRINT0123456789ABCDEF',
        deviceSecret: 'a' * 64,
      );

  /// Server proxy success envelope: the extracted JSON is returned as `text`.
  http.Response proxyOk(Map<String, dynamic> extracted) => http.Response(
        jsonEncode({'success': true, 'text': jsonEncode(extracted)}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  group('GeminiOcrService Unit Tests', () {
    test('parses mock Gemini multimodal JSON response correctly', () async {
      final mockJsonResponse = {
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'text': jsonEncode({
                    'pageNumber': 1,
                    'demographics': {
                      'patientTokenId': 'GC-KTM01-2026-001',
                      'firstName': 'MAYA',
                      'surname': 'TAMANG',
                      'age': 44,
                      'maritalStatus': 'married',
                      'relativeName': 'SOM BAHADUR TAMANG',
                      'mobile': '9841987654',
                      'maritalAge': 18,
                      'contactPerson': 'BISHAL TAMANG',
                      'contactMobile': '9851234567',
                      'province': 'BAGMATI',
                      'district': 'KATHMANDU',
                      'municipality': 'BUDHANILKANTHA',
                      'ward': '04',
                      'reasonsForVisit': [
                        'Something Hanging Out / Prolapse (पाठेघर खस्ने)',
                        'Vaginal Discharge / Itching (स्राव / खटिरा)',
                        'Problems Passing Urine (पिसाब सम्बन्धी समस्या)',
                        'Menstrual Problem (महिनावारी सम्बन्धी समस्या)'
                      ],
                      'consentTreatment': true,
                      'consentStoreMedicalInfo': true
                    },
                    'obstetrics': {
                      'deliveries': 3,
                      'livingChildren': 3,
                      'abortions': 0,
                      'complaintsDuration': '> 1 year',
                      'clinicalComplaints': [
                        'Lower Abdominal Pain',
                        'White / Foul Discharge',
                        'Pelvic Heaviness',
                        'Mass Per Vagina'
                      ]
                    },
                    'popStaging': {
                      'uterusInside': false,
                      'pelvicFloorTone': 'hypertonic',
                      'anteriorStage': 2,
                      'middleStage': 3,
                      'posteriorStage': 1,
                      'highestPopStage': 3,
                      'cervixRemarks': 'Erosion, contact bleeding',
                      'vaginaRemarks': 'Mild atrophic vaginitis, discharge'
                    },
                    'vitals': {
                      'systolicBp': 130,
                      'diastolicBp': 85,
                      'pulseRate': 78,
                      'spo2': 98,
                      'bloodGlucose': 115,
                      'urineTest': 'Protein+, Glucose+',
                      'pregnancyTest': 'Negative'
                    },
                    'diagnoses': ['candid infection'],
                    'medications': ['metronidazol'],
                    'ringPessary': true,
                    'ringPessarySize': 65,
                    'surgeryDone': false,
                    'followUpNeeded': true,
                    'followUpDestination': 'GynaeSupport Nurse in 2 weeks',
                    'surgicalReferral': 'Scheer Memorial Hospital',
                    'clinicalNotes': 'Fitted size 65mm ring pessary. Review at health center in 2 weeks.',
                    'rawSummary': 'Maya Tamang, 44y, P3L3A0, POP Stage 3, Ring Pessary 65mm fitted'
                  })
                }
              ]
            }
          }
        ]
      };

      final mockClient = MockClient((request) async {
        // Must talk to OUR server proxy, never directly to Google.
        expect(request.url.toString(), 'http://test-server:8080/api/ocr/extract');
        expect(request.url.host, isNot(contains('googleapis')));
        expect(request.headers['Content-Type'], 'application/json');
        expect(request.headers['X-Device-Fingerprint'], 'TESTFINGERPRINT0123456789ABCDEF');
        expect(request.headers['X-Device-Secret'], 'a' * 64);
        // No provider key may ever be sent from the client.
        expect(request.headers.keys.map((k) => k.toLowerCase()), isNot(contains('x-goog-api-key')));
        expect(request.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));

        final bodyJson = jsonDecode(request.body) as Map<String, dynamic>;
        expect(bodyJson['imageBase64'], isNotEmpty);
        expect(bodyJson['mimeType'], anyOf('image/jpeg', 'image/png'));
        expect(bodyJson['pageNumber'], 1);
        // Prompt and model config are owned by the server, not the client.
        expect(bodyJson.containsKey('contents'), false);
        expect(bodyJson.containsKey('generationConfig'), false);

        final text = mockJsonResponse['candidates'] as List;
        final extractedText = ((text[0] as Map)['content'] as Map)['parts'][0]['text'] as String;
        return http.Response(
          jsonEncode({'success': true, 'text': extractedText}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = buildService(mockClient);

      final sampleFile = XFile('test_samples/sample_yellow_form_filled_page1.jpg');
      final result = await service.extractFromImage(sampleFile, pageNumber: 1);

      expect(result.ocrEngine, AppConstants.ocrEngineGeminiFlash);
      expect(result.pageNumber, 1);
      expect(result.isSimulated, false);
      // Demographics strictly matching Yellow Form Page 1
      expect(result.demographics['firstName'], 'MAYA');
      expect(result.demographics['surname'], 'TAMANG');
      expect(result.demographics['age'], 44);
      expect(result.demographics['maritalStatus'], 'married');
      expect(result.demographics['relativeName'], 'SOM BAHADUR TAMANG');
      expect(result.demographics['mobile'], '9841987654');
      expect(result.demographics['maritalAge'], 18);
      expect(result.demographics['contactPerson'], 'BISHAL TAMANG');
      expect(result.demographics['contactMobile'], '9851234567');
      expect(result.demographics['province'], 'Bagmati');
      expect(result.demographics['district'], 'Kathmandu');
      expect(result.demographics['municipality'], 'BUDHANILKANTHA');
      expect(result.demographics['ward'], '04');
      expect(result.demographics['reasonsForVisit'], contains('something hanging out'));
      expect(result.surgeryDone, false);
      expect(result.ringPessary, true);
      expect(result.ringPessarySize, 65);
      expect(result.demographics['consentTreatment'], true);
      expect(result.demographics['consentStoreMedicalInfo'], true);
      // Verify NO phantom fields
      expect(result.demographics.containsKey('casteEthnicity'), false);
      expect(result.demographics.containsKey('education'), false);
      expect(result.demographics.containsKey('occupation'), false);

      // Station 1: Obstetrics
      expect(result.obstetrics['deliveries'], 3);
      expect(result.obstetrics['livingChildren'], 3);
      expect(result.obstetrics['abortions'], 0);
      expect(result.obstetrics['complaintsDuration'], '> 1 year');
      expect(result.obstetrics['clinicalComplaints'], contains('Mass Per Vagina'));
      expect(result.obstetrics.containsKey('gravida'), false);

      // Station 2: POP Staging
      expect(result.popStaging['uterusInside'], false);
      expect(result.popStaging['pelvicFloorTone'], 'hypertonic');
      expect(result.popStaging['anteriorStage'], 2);
      expect(result.popStaging['middleStage'], 3);
      expect(result.popStaging['posteriorStage'], 1);
      expect(result.popStaging['highestPopStage'], 3);

      // Station 3: Vitals
      expect(result.vitals['systolicBp'], 130);
      expect(result.vitals['diastolicBp'], 85);
      expect(result.vitals['pulseRate'], 78);
      expect(result.vitals['spo2'], 98);
      expect(result.vitals['bloodGlucose'], 115);
      expect(result.vitals['urineTest'], contains('Protein+'));
      expect(result.vitals.containsKey('respiratoryRate'), false);
      expect(result.vitals.containsKey('temperature'), false);

      // Station 4: Diagnoses & Station 5: Meds
      expect(result.diagnoses, contains('candid infection'));
      expect(result.medications, contains('metronidazol'));
      expect(result.medications, contains('Ring Pessary 65mm'));

      // Station 6: Referral
      expect(result.surgicalReferral, 'Scheer Memorial Hospital');
      expect(result.followUpDestination, 'GynaeSupport Nurse in 2 weeks');
      expect(result.overallConfidence, greaterThanOrEqualTo(0.90));
      expect(result.rawText, contains('GEMINI FLASH CLOUD OCR'));
    });

    test('throws GeminiOcrException with server message on HTTP error status', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'code': 'DEVICE_NOT_APPROVED', 'error': 'This device is not approved for cloud OCR.'}),
          403,
        );
      });

      final service = buildService(mockClient);

      final sampleFile = XFile('test_samples/sample_yellow_form_filled_page1.jpg');
      expect(
        () => service.extractFromImage(sampleFile, pageNumber: 1),
        throwsA(
          isA<GeminiOcrException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', contains('not approved')),
        ),
      );
    });

    test('throws GeminiOcrException when the server is unreachable', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('connection refused');
      });
      final service = buildService(mockClient);

      final sampleFile = XFile('test_samples/sample_yellow_form_filled_page1.jpg');
      expect(
        () => service.extractFromImage(sampleFile, pageNumber: 1),
        throwsA(isA<GeminiOcrException>()),
      );
    });

    test('refuses to call the server without device credentials', () async {
      var called = false;
      final mockClient = MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      });
      // No explicit secret and no SessionService instance -> empty secret.
      final service = GeminiOcrService(
        httpClient: mockClient,
        baseUrl: 'http://test-server:8080',
        deviceFingerprint: 'FP',
      );

      final sampleFile = XFile('test_samples/sample_yellow_form_filled_page1.jpg');
      await expectLater(
        service.extractFromImage(sampleFile, pageNumber: 1),
        throwsA(isA<GeminiOcrException>()),
      );
      expect(called, false);
    });
  });

  group('OcrRepository Dual-Engine Strategy Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late PatientRepository patientRepo;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      patientRepo = PatientRepository(databaseService: dbService, auditRepository: auditRepo);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('in AUTO mode, uses Gemini when available', () async {
      final mockGeminiSuccess = MockClient((request) async {
        return proxyOk({
          'pageNumber': 1,
          'demographics': {'firstName': 'Gita', 'surname': 'Rai', 'age': 42},
          'obstetrics': {},
          'vitals': {},
          'popStaging': {},
          'diagnoses': [],
          'medications': [],
          'rawSummary': 'Gita Rai 42y',
        });
      });

      final geminiService = buildService(mockGeminiSuccess);
      final ocrRepo = OcrRepository(
        patientRepository: patientRepo,
        auditRepository: auditRepo,
        geminiService: geminiService,
      );

      final sampleFile = XFile('test_samples/sample_yellow_form_filled_page1.jpg');
      final result = await ocrRepo.processImageScan(
        sampleFile,
        pageNumber: 1,
        engineMode: OcrEngineMode.auto,
      );

      expect(result.ocrEngine, AppConstants.ocrEngineGeminiFlash);
      expect(result.demographics['firstName'], 'Gita');
      expect(result.demographics['surname'], 'Rai');
    });

    test('in AUTO mode, automatically falls back to ML Kit when Gemini fails (offline fallback)', () async {
      final mockGeminiFailing = MockClient((request) async {
        return http.Response('Service Unavailable', 503);
      });

      final geminiService = buildService(mockGeminiFailing);
      final ocrRepo = OcrRepository(
        patientRepository: patientRepo,
        auditRepository: auditRepo,
        geminiService: geminiService,
      );

      final sampleFile = XFile('test_samples/sample_yellow_form_filled_page1.jpg');
      final result = await ocrRepo.processImageScan(
        sampleFile,
        pageNumber: 1,
        engineMode: OcrEngineMode.auto,
      );

      // Successfully returned result via fallback rather than throwing
      expect(result.demographics, isNotNull);
      expect(
        result.ocrEngine == AppConstants.ocrEngineMlKitOffline || result.ocrEngine == AppConstants.ocrEngineSimulation,
        isTrue,
      );
    });

    test('in OFFLINE_ONLY mode, directly uses ML Kit without calling Gemini', () async {
      bool geminiWasCalled = false;
      final mockGemini = MockClient((request) async {
        geminiWasCalled = true;
        return http.Response('Should not be called', 500);
      });

      final geminiService = buildService(mockGemini);
      final ocrRepo = OcrRepository(
        patientRepository: patientRepo,
        auditRepository: auditRepo,
        geminiService: geminiService,
      );

      final sampleFile = XFile('test_samples/sample_yellow_form_filled_page1.jpg');
      final result = await ocrRepo.processImageScan(
        sampleFile,
        pageNumber: 1,
        engineMode: OcrEngineMode.offlineOnly,
      );

      expect(geminiWasCalled, false);
      expect(
        result.ocrEngine == AppConstants.ocrEngineMlKitOffline || result.ocrEngine == AppConstants.ocrEngineSimulation,
        isTrue,
      );
    });

    test('in STRICT ONLINE_GEMINI mode, throws error if Gemini fails', () async {
      final mockGeminiFailing = MockClient((request) async {
        return http.Response('Unauthorized', 401);
      });

      final geminiService = buildService(mockGeminiFailing);
      final ocrRepo = OcrRepository(
        patientRepository: patientRepo,
        auditRepository: auditRepo,
        geminiService: geminiService,
      );

      final sampleFile = XFile('test_samples/sample_yellow_form_filled_page1.jpg');
      expect(
        () => ocrRepo.processImageScan(
          sampleFile,
          pageNumber: 1,
          engineMode: OcrEngineMode.onlineGemini,
        ),
        throwsA(isA<GeminiOcrException>()),
      );
    });

    test('commitVerifiedScan records ocrEngine in cryptographic audit log', () async {
      final mockGeminiSuccess = MockClient((request) async {
        return proxyOk({
          'pageNumber': 1,
          'demographics': {'firstName': 'Sunita', 'surname': 'Gurung', 'age': 34, 'ward': '02'},
          'obstetrics': {},
          'vitals': {'systolicBp': 118, 'diastolicBp': 78},
          'popStaging': {'stage': 2, 'highestPopStage': 2},
          'diagnoses': ['POP Stage II'],
          'medications': ['Pelvic Floor Muscle Training'],
          'rawSummary': 'Sunita Gurung',
        });
      });

      final geminiService = buildService(mockGeminiSuccess);
      final ocrRepo = OcrRepository(
        patientRepository: patientRepo,
        auditRepository: auditRepo,
        geminiService: geminiService,
      );

      final sampleFile = XFile('test_samples/sample_yellow_form_filled_page1.jpg');
      final scanResult = await ocrRepo.processImageScan(sampleFile, pageNumber: 1);

      final patient = await ocrRepo.commitVerifiedScan(
        verifiedScan: scanResult,
        campId: 'camp-dhading-01',
        campCode: 'DHD01',
        userId: 'usr-nurse-01',
        userName: 'Pooja Thapa',
        deviceId: 'dev-tab-02',
      );

      expect(patient.fullName, 'Sunita Gurung');

      // Verify audit log has ocrEngine recorded
      final logs = await auditRepo.getRecentLogs();
      final ocrAudit = logs.firstWhere((l) => l.action == AppConstants.auditActionPatientRegisteredViaOcr);
      expect(ocrAudit.detailsJson, contains('"ocrEngine":"gemini_flash"'));
    });
  });
}
