import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/services/mlkit_ocr_service.dart';
import '../core/services/ocr_form_service.dart';
import '../models/clinical_visit_model.dart';
import '../models/ocr_scan_result_model.dart';
import '../models/patient_model.dart';
import 'audit_repository.dart';
import 'patient_repository.dart';

abstract class IOcrRepository {
  Future<OcrScanResultModel> processTextScan(String text, {int pageNumber = 0, String? imagePath});
  Future<OcrScanResultModel> processImageScan(XFile imageFile, {int pageNumber = 0});
  Future<OcrScanResultModel> processDualPageScan({required XFile page1File, required XFile page2File});
  Future<PatientModel> commitVerifiedScan({
    required OcrScanResultModel verifiedScan,
    required String campId,
    required String campCode,
    required String userId,
    required String userName,
    required String deviceId,
  });
}

class OcrRepository implements IOcrRepository {
  final OcrFormService _ocrService;
  final IPatientRepository _patientRepository;
  final AuditRepository _auditRepository;
  final Uuid _uuid = const Uuid();

  OcrRepository({
    OcrFormService? ocrService,
    IPatientRepository? patientRepository,
    AuditRepository? auditRepository,
  })  : _ocrService = ocrService ?? const OcrFormService(),
        _patientRepository = patientRepository ?? PatientRepository(),
        _auditRepository = auditRepository ?? AuditRepository();

  @override
  Future<OcrScanResultModel> processTextScan(String text, {int pageNumber = 0, String? imagePath}) async {
    return _ocrService.parseFormText(text, pageNumber: pageNumber, imagePath: imagePath);
  }

  @override
  Future<OcrScanResultModel> processImageScan(XFile imageFile, {int pageNumber = 0}) async {
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

    // Attempt real OCR via Google ML Kit (Android / iOS only)
    final mlkit = MlKitOcrService();
    final extractedText = await mlkit.extractText(imageFile);
    await mlkit.dispose();

    // extractedText is empty when ML Kit is unavailable (Windows / Web / bad image)
    final isSimulated = extractedText.trim().isEmpty;
    final String textToProcess;
    if (isSimulated) {
      // Graceful fallback: use sample text so the pipeline stays functional,
      // but flag the result so the UI can display a clear warning banner.
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

    // Propagate simulation flag so FormScanView can show the amber warning banner
    return isSimulated ? result.copyWith(isSimulated: true) : result;
  }

  @override
  Future<OcrScanResultModel> processDualPageScan({
    required XFile page1File,
    required XFile page2File,
  }) async {
    final scan1 = await processImageScan(page1File, pageNumber: 1);
    final scan2 = await processImageScan(page2File, pageNumber: 2);
    return OcrScanResultModel.merge(scan1, scan2);
  }

  @override
  Future<PatientModel> commitVerifiedScan({
    required OcrScanResultModel verifiedScan,
    required String campId,
    required String campCode,
    required String userId,
    required String userName,
    required String deviceId,
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
      district: (demo['district'] as String? ?? 'Kathmandu'),
      municipality: (demo['municipality'] as String? ?? 'Ward 03'),
      ward: (demo['ward'] as String? ?? '03').padLeft(2, '0'),
      maritalStatus: (demo['maritalStatus'] as String? ?? 'married'),
      reasonsForVisit: List<String>.from(demo['reasonsForVisit'] as List? ?? ['Something hanging out / Prolapse']),
      consentTreatment: true,
      consentStoreMedicalInfo: true,
      createdAt: DateTime.now(),
      createdByUserId: userId,
      createdByDeviceId: deviceId,
    );

    // Save Patient in SQLite
    final registeredPatient = await _patientRepository.registerPatient(
      patient,
      createdByUserId: userId,
      deviceId: deviceId,
    );

    // 2. Construct Clinical Visit Model
    final clinicalVisit = ClinicalVisitModel(
      id: 'vis-${_uuid.v4()}',
      patientId: registeredPatient.patientId,
      campId: campId,
      tenantId: registeredPatient.tenantId,
      visitDate: DateTime.now(),
      deliveries: obs['deliveries'] as int? ?? 3,
      livingChildren: obs['livingChildren'] as int? ?? 3,
      abortions: obs['abortions'] as int? ?? 0,
      uterusInside: pop['uterusInside'] as bool? ?? false,
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
      surgicalReferral: verifiedScan.surgicalReferral,
      followUpNeeded: (pop['highestPopStage'] as int? ?? 0) >= 2,
      followUpDestination: verifiedScan.followUpDestination ?? 'Health Post',
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
      userRole: AppConstants.roleDataTaker,
      action: AppConstants.auditActionPatientRegisteredViaOcr,
      entityType: 'PATIENT',
      entityId: registeredPatient.id,
      detailsJson: '{"patientId":"${registeredPatient.patientId}","confidence":${verifiedScan.overallConfidence}}',
      deviceId: deviceId,
    );

    return registeredPatient;
  }
}
