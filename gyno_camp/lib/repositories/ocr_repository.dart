import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/services/gemini_ocr_service.dart';
import '../core/services/mlkit_ocr_service.dart';
import '../core/services/ocr_form_service.dart';
import '../models/clinical_visit_model.dart';
import '../models/ocr_scan_result_model.dart';
import '../models/patient_model.dart';
import 'audit_repository.dart';
import 'patient_repository.dart';

enum OcrEngineMode {
  auto,
  onlineGemini,
  offlineOnly,
}

abstract class IOcrRepository {
  Future<OcrScanResultModel> processTextScan(String text, {int pageNumber = 0, String? imagePath});
  Future<OcrScanResultModel> processImageScan(
    XFile imageFile, {
    int pageNumber = 0,
    OcrEngineMode engineMode = OcrEngineMode.auto,
  });
  Future<OcrScanResultModel> processDualPageScan({
    required XFile page1File,
    required XFile page2File,
    OcrEngineMode engineMode = OcrEngineMode.auto,
  });
  Future<PatientModel> commitVerifiedScan({
    required OcrScanResultModel verifiedScan,
    required String campId,
    required String campCode,
    required String userId,
    required String userName,
    String userRole = 'NURSE',
    required String deviceId,
    String? primaryDoctorName,
    List<String> attendingDoctorNames = const [],
  });
}

class OcrRepository implements IOcrRepository {
  final OcrFormService _ocrService;
  final IPatientRepository _patientRepository;
  final AuditRepository _auditRepository;
  final GeminiOcrService _geminiService;
  final MlKitOcrService Function() _mlkitFactory;
  final Uuid _uuid = const Uuid();

  OcrRepository({
    OcrFormService? ocrService,
    IPatientRepository? patientRepository,
    AuditRepository? auditRepository,
    GeminiOcrService? geminiService,
    MlKitOcrService Function()? mlkitFactory,
  })  : _ocrService = ocrService ?? const OcrFormService(),
        _patientRepository = patientRepository ?? PatientRepository(),
        _auditRepository = auditRepository ?? AuditRepository(),
        _geminiService = geminiService ?? GeminiOcrService(),
        _mlkitFactory = mlkitFactory ?? (() => MlKitOcrService());

  @override
  Future<OcrScanResultModel> processTextScan(String text, {int pageNumber = 0, String? imagePath}) async {
    return _ocrService.parseFormText(text, pageNumber: pageNumber, imagePath: imagePath);
  }

  @override
  Future<OcrScanResultModel> processImageScan(
    XFile imageFile, {
    int pageNumber = 0,
    OcrEngineMode engineMode = OcrEngineMode.auto,
  }) async {
    final path = imageFile.path;
    final lowerPath = path.toLowerCase();

    // Determine which form page this image represents
    final int detectedPage;
    if (pageNumber == 1 || lowerPath.contains('page1') || lowerPath.contains('front')) {
      detectedPage = 1;
    } else if (pageNumber == 2 || lowerPath.contains('page2') || lowerPath.contains('back')) {
      detectedPage = 2;
    } else {
      detectedPage = pageNumber;
    }

    // 1. If engineMode is onlineGemini or auto: try Gemini Flash multimodal OCR first
    if (engineMode == OcrEngineMode.onlineGemini || engineMode == OcrEngineMode.auto) {
      try {
        if (kDebugMode) {
          debugPrint('[OcrRepo] 🌐 Attempting Gemini Flash OCR for page $detectedPage (Mode: $engineMode)...');
        }
        final geminiResult = await _geminiService.extractFromImage(imageFile, pageNumber: detectedPage);
        if (kDebugMode) {
          debugPrint('[OcrRepo] ✅ Gemini Flash extraction succeeded for page $detectedPage');
          debugPrint('[OcrRepo] Demographics: ${geminiResult.demographics["firstName"]} ${geminiResult.demographics["surname"]}');
        }
        return geminiResult;
      } catch (e) {
        if (engineMode == OcrEngineMode.onlineGemini) {
          // Strict online mode: propagate failure to user
          if (kDebugMode) {
            debugPrint('[OcrRepo] ❌ Gemini Flash OCR failed in strict online mode: $e');
          }
          rethrow;
        }
        // Auto mode: log warning and smoothly fall back to On-Device ML Kit
        if (kDebugMode) {
          debugPrint('[OcrRepo] ⚠️ Gemini Flash failed in AUTO mode: $e. Falling back to On-Device ML Kit.');
        }
      }
    }

    // 2. Offline / On-Device ML Kit OCR (Android/iOS ML Kit, Windows WinRT OCR)
    return _processOfflineMlKitScan(imageFile, detectedPage: detectedPage);
  }

  Future<OcrScanResultModel> _processOfflineMlKitScan(XFile imageFile, {required int detectedPage}) async {
    final path = imageFile.path;
    final mlkit = _mlkitFactory();
    String extractedText = '';
    String? ocrError;
    try {
      extractedText = await mlkit.extractText(imageFile);
      if (kDebugMode) {
        debugPrint('[OcrRepo] ✅ ML Kit extracted ${extractedText.length} chars for page $detectedPage');
        debugPrint('[OcrRepo] Image path: $path');
      }
    } catch (e) {
      ocrError = e.toString();
      extractedText = '';
      if (kDebugMode) {
        debugPrint('[OcrRepo] ❌ ML Kit OCR FAILED for page $detectedPage: $ocrError');
        debugPrint('[OcrRepo] Image path: $path');
        debugPrint('[OcrRepo] Falling back to sample text (SIMULATION MODE)');
      }
    } finally {
      await mlkit.dispose();
    }

    // extractedText is empty when OCR failed or is unavailable (Web / bad image)
    final isSimulated = extractedText.trim().isEmpty;
    final String textToProcess;
    if (isSimulated) {
      if (kDebugMode) {
        debugPrint('[OcrRepo] ⚠️  SIMULATION MODE active for page $detectedPage');
        if (ocrError != null) {
          debugPrint('[OcrRepo] Reason: OCR engine error — $ocrError');
        } else {
          debugPrint('[OcrRepo] Reason: OCR returned empty text (image may be too blurry/dark)');
        }
      }
      textToProcess = detectedPage == 1
          ? OcrFormService.samplePage1Text
          : (detectedPage == 2
              ? OcrFormService.samplePage2Text
              : OcrFormService.sampleFullFormText);
    } else {
      textToProcess = extractedText;
    }

    final result = _ocrService.parseFormText(
      textToProcess,
      pageNumber: detectedPage,
      imagePath: path,
    );

    if (kDebugMode) {
      final demo = result.demographics;
      debugPrint('[OcrRepo] Parsed fields → Name: ${demo['firstName']} ${demo['surname']}, '
          'Age: ${demo['age']}, Mobile: ${demo['mobile']}, Ward: ${demo['ward']}');
      debugPrint('[OcrRepo] Overall confidence: ${(result.overallConfidence * 100).toStringAsFixed(0)}%');
    }

    return result.copyWith(
      isSimulated: isSimulated,
      ocrEngine: isSimulated ? AppConstants.ocrEngineSimulation : AppConstants.ocrEngineMlKitOffline,
    );
  }

  @override
  Future<OcrScanResultModel> processDualPageScan({
    required XFile page1File,
    required XFile page2File,
    OcrEngineMode engineMode = OcrEngineMode.auto,
  }) async {
    final scan1 = await processImageScan(page1File, pageNumber: 1, engineMode: engineMode);
    final scan2 = await processImageScan(page2File, pageNumber: 2, engineMode: engineMode);
    return OcrScanResultModel.merge(scan1, scan2);
  }

  @override
  Future<PatientModel> commitVerifiedScan({
    required OcrScanResultModel verifiedScan,
    required String campId,
    required String campCode,
    required String userId,
    required String userName,
    String userRole = 'NURSE',
    required String deviceId,
    String? primaryDoctorName,
    List<String> attendingDoctorNames = const [],
  }) async {
    final demo = verifiedScan.demographics;
    final obs = verifiedScan.obstetrics;
    final vitals = verifiedScan.vitals;
    final pop = verifiedScan.popStaging;

    // 1. Construct Patient Model
    final patient = PatientModel(
      id: 'pat-${_uuid.v4()}',
      patientId: '', // Auto-generated sequentially in repository
      campId: campId,
      campCode: campCode,
      intakeDate: DateTime.now(),
      firstName: (demo['firstName'] as String? ?? 'Sita').trim(),
      surname: (demo['surname'] as String? ?? 'Sharma').trim(),
      age: (demo['age'] as int? ?? 35),
      spouseOrFatherName: demo['relativeName'] as String?,
      relationshipType: demo['relativeType'] as String? ?? 'Husband',
      mobile: (demo['mobile'] as String? ?? ''),
      // Contact fields — now parsed by OCR service and carried through to DB
      contactPerson: demo['contactPerson'] as String?,
      contactMobile: demo['contactMobile'] as String?,
      // Marriage age — parsed from 'Age at Marriage' field on form
      maritalAge: demo['maritalAge'] as int?,
      province: (demo['province'] as String?)?.trim() ?? 'Bagmati',
      district: (demo['district'] as String? ?? 'Kathmandu'),
      municipality: (demo['municipality'] as String? ?? 'Ward 03'),
      ward: (demo['ward'] as String? ?? '03').padLeft(2, '0'),
      maritalStatus: (demo['maritalStatus'] as String? ?? 'married'),
      reasonsForVisit: List<String>.from(demo['reasonsForVisit'] as List? ?? ['something hanging out']),
      consentTreatment: demo['consentTreatment'] as bool? ?? true,
      consentStoreMedicalInfo: demo['consentStoreMedicalInfo'] as bool? ?? true,
      createdAt: DateTime.now(),
      createdByUserId: userId,
      createdByDeviceId: deviceId,
    );

    // Save Patient in SQLite
    final registeredPatient = await _patientRepository.registerPatient(
      patient,
      createdByUserId: userId,
      createdByUserName: userName,
      createdByUserRole: userRole,
      deviceId: deviceId,
    );

    // 2. Construct Clinical Visit Model
    final rawComplaints = obs['clinicalComplaints'];
    final List<String> complaintsList = rawComplaints is List ? List<String>.from(rawComplaints) : [];
    final duration = obs['complaintsDuration'] as String? ?? '';
    final Map<String, dynamic> anamnesisMap = {};
    for (final c in complaintsList) {
      anamnesisMap[c] = {
        'present': true,
        'duration': duration,
      };
    }

    final clinicalVisit = ClinicalVisitModel(
      id: 'vis-${_uuid.v4()}',
      patientId: registeredPatient.patientId,
      campId: campId,
      tenantId: registeredPatient.tenantId,
      visitDate: DateTime.now(),
      deliveries: obs['deliveries'] as int?,
      livingChildren: obs['livingChildren'] as int?,
      abortions: obs['abortions'] as int?,
      anamnesisComplaints: anamnesisMap,
      uterusInside: pop['uterusInside'] as bool? ?? false,
      cervixRemarks: pop['cervixRemarks'] as String?,
      vaginaRemarks: pop['vaginaRemarks'] as String?,
      vulvaRemarks: pop['vulvaRemarks'] as String?,
      pelvicFloorTone: pop['pelvicFloorTone'] as String? ?? 'weak',
      popAnteriorStage: pop['anteriorStage'] as int? ?? 2,
      popMiddleStage: pop['middleStage'] as int? ?? 3,
      popPosteriorStage: pop['posteriorStage'] as int? ?? 1,
      highestPopStage: pop['highestPopStage'] as int? ?? 3,
      systolicBp: vitals['systolicBp'] as int? ?? 120,
      diastolicBp: vitals['diastolicBp'] as int? ?? 80,
      pulse: vitals['pulseRate'] as int? ?? 78,
      spo2: vitals['spo2'] as int? ?? 98,
      glucose: vitals['bloodGlucose'] as int? ?? 110,
      urineTest: vitals['urineTest'] as String? ?? 'normal',
      pregnancyTest: vitals['pregnancyTest'] as String? ?? 'neg',
      diagnoses: verifiedScan.diagnoses,
      counseling: const [],
      medications: verifiedScan.medications,
      pessaryType: (verifiedScan.ringPessary || pop['ringPessary'] == true) ? 'ring' : null,
      pessarySize: verifiedScan.ringPessarySize != null
          ? '${verifiedScan.ringPessarySize}mm'
          : (pop['ringPessarySize'] != null ? '${pop['ringPessarySize']}mm' : null),
      surgeryDone: verifiedScan.surgeryDone || pop['surgeryDone'] == true,
      surgeryType: verifiedScan.surgeryType ?? pop['surgeryType'] as String?,
      surgicalReferral: verifiedScan.surgicalReferral,
      followUpNeeded: (pop['highestPopStage'] as int? ?? 0) >= 2,
      followUpDestination: verifiedScan.followUpDestination ?? 'Health Post',
      primaryDoctorName: primaryDoctorName ?? verifiedScan.examiningDoctor,
      attendingDoctorNames: attendingDoctorNames.isNotEmpty
          ? attendingDoctorNames
          : (verifiedScan.attendingDoctors.isNotEmpty
              ? verifiedScan.attendingDoctors
              : ((primaryDoctorName ?? verifiedScan.examiningDoctor) != null
                  ? [(primaryDoctorName ?? verifiedScan.examiningDoctor)!]
                  : const [])),
      createdAt: DateTime.now(),
      createdByUserId: userId,
    );

    // Save Clinical Visit in SQLite
    await _patientRepository.saveClinicalVisit(
      clinicalVisit,
      createdByUserId: userId,
      deviceId: deviceId,
    );

    // 3. Log Audit Activity with SHA-256 Chaining
    await _auditRepository.logActivity(
      userId: userId,
      userName: userName,
      userRole: userRole,
      action: AppConstants.auditActionPatientRegisteredViaOcr,
      entityType: 'PATIENT',
      entityId: registeredPatient.id,
      detailsJson: '{"patientId":"${registeredPatient.patientId}","confidence":${verifiedScan.overallConfidence},"ocrEngine":"${verifiedScan.ocrEngine}"}',
      deviceId: deviceId,
    );

    return registeredPatient;
  }
}
