import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:nepali_utils/nepali_utils.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/nepali_date_helper.dart';
import '../core/services/gemini_ocr_service.dart';
import '../core/services/mlkit_ocr_service.dart';
import '../core/services/ocr_form_service.dart';
import '../models/clinical_visit_model.dart';
import '../models/ocr_scan_result_model.dart';
import '../models/patient_model.dart';
import 'audit_repository.dart';
import 'patient_repository.dart';

/// Safely extracts complaintDetails as `Map<String, dynamic>` regardless of
/// whether it's a List (from Gemini) or already a Map.
Map<String, dynamic> _safeComplaintDetailsMap(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is List) {
    final result = <String, dynamic>{};
    for (final item in raw) {
      if (item is Map) {
        final key = item['complaint']?.toString().trim();
        if (key != null && key.isNotEmpty) {
          result[key] = <String, dynamic>{
            'duration': item['duration']?.toString() ?? '',
            'remarks': item['remarks']?.toString() ?? '',
            'subOption': item['subOptions'] is List
                ? (item['subOptions'] as List).join(', ')
                : (item['subOption']?.toString() ?? ''),
          };
        }
      }
    }
    return result;
  }
  return <String, dynamic>{};
}

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
    String? primaryNurseName,
    List<String> attendingNurseNames = const [],
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
    String? primaryNurseName,
    List<String> attendingNurseNames = const [],
  }) async {
    final demo = verifiedScan.demographics;
    final obs = verifiedScan.obstetrics;
    final vitals = verifiedScan.vitals;
    final pop = verifiedScan.popStaging;

    // 1. Construct Patient Model
    final rawToken = (demo['patientId'] as String? ?? demo['patientTokenId'] as String? ?? '').trim();
    final normalizedPatientId = PatientModel.normalizePatientId(
      rawInput: rawToken,
      campCode: campCode,
    );

    DateTime parseDateSafe(String? raw) {
      if (raw == null || raw.trim().isEmpty) return DateTime.now();
      try {
        final clean = raw.replaceAll(RegExp(r'\s*BS', caseSensitive: false), '').trim();
        final parts = clean.split(RegExp(r'[-/]'));
        if (parts.length == 3) {
          final y = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final d = int.tryParse(parts[2]);
          if (y != null && m != null && d != null) {
            if (y >= 2070 && y <= 2120) {
              return NepaliDateHelper.toEnglish(NepaliDateTime(y, m, d));
            } else {
              return DateTime(y, m, d);
            }
          }
        }
        return DateTime.parse(clean);
      } catch (_) {
        return DateTime.now();
      }
    }

    final parsedIntake = parseDateSafe(verifiedScan.intakeDate ?? demo['intakeDate'] as String? ?? demo['date'] as String?);
    final parsedVisit = parseDateSafe(verifiedScan.treatmentDate ?? verifiedScan.conclusionDate ?? verifiedScan.examDate ?? verifiedScan.intakeDate);

    final patient = PatientModel(
      id: 'pat-${_uuid.v4()}',
      patientId: normalizedPatientId, // Pre-assigned token or auto-generated sequentially by repository if empty
      campId: campId,
      campCode: campCode,
      intakeDate: parsedIntake,
      firstName: (demo['firstName'] as String? ?? 'Sita').trim(),
      surname: (demo['surname'] as String? ?? 'Sharma').trim(),
      age: (demo['age'] as int? ?? 35),
      spouseOrFatherName: () {
        final relName = (demo['relativeName'] as String? ?? '').trim();
        final relSur = (demo['relativeSurname'] as String? ?? '').trim();
        if (relName.isEmpty) return relSur.isNotEmpty ? relSur : null;
        if (relSur.isNotEmpty && !relName.toLowerCase().contains(relSur.toLowerCase())) {
          return '$relName $relSur';
        }
        return relName;
      }(),
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
      reasonsForVisit: List<String>.from(demo['reasonsForVisit'] as List? ?? const <String>[]),
      consentTreatment: demo['consentTreatment'] as bool? ?? true,
      consentStoreMedicalInfo: demo['consentStoreMedicalInfo'] as bool? ?? true,
      treatmentLevel: PatientModel.normalizeTreatmentLevel(
        verifiedScan.treatmentLevel ?? demo['treatmentLevel'] as String? ?? demo['levelOfTreatment'] as String?,
      ),
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
    final Map<String, dynamic> anamnesisMap = {
      'clinicalComplaints': complaintsList,
      'complaintsDuration': duration,
    };
    final complaintDetails = _safeComplaintDetailsMap(obs['complaintDetails']);

    // Helper to find complaint details across all alias formats
    Map<String, dynamic> findDetails(String key) {
      if (complaintDetails.containsKey(key)) {
        return Map<String, dynamic>.from(complaintDetails[key] as Map? ?? {});
      }
      final lk = key.toLowerCase().trim();
      if (complaintDetails.containsKey(lk)) {
        return Map<String, dynamic>.from(complaintDetails[lk] as Map? ?? {});
      }
      final withSpaces = lk.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
      if (complaintDetails.containsKey(withSpaces)) {
        return Map<String, dynamic>.from(complaintDetails[withSpaces] as Map? ?? {});
      }
      final withUnderscores = lk.replaceAll(RegExp(r'[\s\-]+'), '_').trim();
      if (complaintDetails.containsKey(withUnderscores)) {
        return Map<String, dynamic>.from(complaintDetails[withUnderscores] as Map? ?? {});
      }
      for (final entry in complaintDetails.entries) {
        final ek = entry.key.toLowerCase().trim();
        if ((ek.contains('prolapse') || ek.contains('hanging')) && (lk.contains('prolapse') || lk.contains('hanging'))) {
          return Map<String, dynamic>.from(entry.value as Map? ?? {});
        }
        if ((ek.contains('urine') || ek.contains('micturition')) && (lk.contains('urine') || lk.contains('micturition'))) {
          return Map<String, dynamic>.from(entry.value as Map? ?? {});
        }
        if ((ek.contains('discharge') || ek.contains('itching')) && (lk.contains('discharge') || lk.contains('itching'))) {
          return Map<String, dynamic>.from(entry.value as Map? ?? {});
        }
        if (ek.contains('stool') && lk.contains('stool')) {
          return Map<String, dynamic>.from(entry.value as Map? ?? {});
        }
        if (ek.contains('menstrual') && lk.contains('menstrual')) {
          return Map<String, dynamic>.from(entry.value as Map? ?? {});
        }
        if (ek.contains('infertility') && lk.contains('infertility')) {
          return Map<String, dynamic>.from(entry.value as Map? ?? {});
        }
        if (ek.contains('abdomen') && lk.contains('abdomen')) {
          return Map<String, dynamic>.from(entry.value as Map? ?? {});
        }
        if (ek.contains('back') && lk.contains('back')) {
          return Map<String, dynamic>.from(entry.value as Map? ?? {});
        }
        if (ek.contains('checkup') && lk.contains('checkup')) {
          return Map<String, dynamic>.from(entry.value as Map? ?? {});
        }
      }
      return const {};
    }

    void storeAnamnesisItem(String primaryKey, Map<String, dynamic> itemDetails) {
      final itemDur = (itemDetails['duration'] as String?)?.isNotEmpty == true
          ? itemDetails['duration'] as String
          : duration;
      final itemRemarks = (itemDetails['remarks'] as String?) ?? '';
      final rawSub = itemDetails['subOption'] ?? itemDetails['subOptions'] ?? itemDetails['options'];
      final List<String> optionsList = [];
      if (rawSub is List) {
        for (final o in rawSub) {
          final s = o?.toString().trim();
          if (s != null && s.isNotEmpty && !optionsList.contains(s)) optionsList.add(s);
        }
      } else if (rawSub is String && rawSub.trim().isNotEmpty) {
        for (final o in rawSub.split(',')) {
          final s = o.trim();
          if (s.isNotEmpty && !optionsList.contains(s)) optionsList.add(s);
        }
      }
      final subOptionStr = optionsList.join(', ');

      final entryData = {
        'present': true,
        'active': true,
        'duration': itemDur,
        'remarks': itemRemarks,
        'subOption': subOptionStr,
        'subOptions': optionsList,
        'options': optionsList,
      };

      anamnesisMap[primaryKey] = entryData;
      final lowerC = primaryKey.toLowerCase().trim();
      final withSpaces = lowerC.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
      final withUnderscores = lowerC.replaceAll(RegExp(r'[\s\-]+'), '_').trim();
      anamnesisMap[lowerC] = entryData;
      anamnesisMap[withSpaces] = entryData;
      anamnesisMap[withUnderscores] = entryData;

      if (lowerC.contains('mass') || lowerC.contains('vagina') || lowerC.contains('prolapse') || lowerC.contains('hanging')) {
        anamnesisMap['prolapse'] = entryData;
        anamnesisMap['something hanging out'] = entryData;
        anamnesisMap['something_hanging_out'] = entryData;
      }
      if (lowerC.contains('discharge') || lowerC.contains('foul') || lowerC.contains('white') || lowerC.contains('itching')) {
        anamnesisMap['discharge'] = entryData;
        anamnesisMap['discharge and or itching'] = entryData;
        anamnesisMap['discharge_and_or_itching'] = entryData;
        anamnesisMap['discharge / itching'] = entryData;
        anamnesisMap['discharge___itching'] = entryData;
        anamnesisMap['discharge_itching'] = entryData;
      }
      if (lowerC.contains('micturition') || lowerC.contains('incontinence') || lowerC.contains('urine')) {
        anamnesisMap['urine'] = entryData;
        anamnesisMap['problems passing urine'] = entryData;
        anamnesisMap['problems_passing_urine'] = entryData;
      }
      if (lowerC == 'pain') {
        anamnesisMap['lower_abdomen_pain'] = entryData;
        anamnesisMap['lower abdomen pain'] = entryData;
      }
      if (lowerC.contains('stool') || lowerC.contains('bowel')) {
        anamnesisMap['stool'] = entryData;
        anamnesisMap['problems passing stool'] = entryData;
        anamnesisMap['problems_passing_stool'] = entryData;
      }
      if (lowerC.contains('menstrual')) {
        anamnesisMap['menstrual'] = entryData;
        anamnesisMap['menstrual problem'] = entryData;
        anamnesisMap['menstrual_problem'] = entryData;
      }
      if (lowerC.contains('infertility')) {
        anamnesisMap['infertility'] = entryData;
      }
      if (lowerC.contains('abdomen')) {
        anamnesisMap['lower_abdomen_pain'] = entryData;
        anamnesisMap['lower abdomen pain'] = entryData;
      }
      if (lowerC.contains('back')) {
        anamnesisMap['lower_back_pain'] = entryData;
        anamnesisMap['lower back pain'] = entryData;
      }
      if (lowerC.contains('checkup')) {
        anamnesisMap['checkup'] = entryData;
      }
    }

    // Process all complaints in complaintsList
    final processedComplaintKeys = <String>{};
    for (final c in complaintsList) {
      final details = findDetails(c);
      storeAnamnesisItem(c, details);
      processedComplaintKeys.add(c.toLowerCase().trim());
    }

    // Also include any complaint in complaintDetails that may have been missed
    for (final entry in complaintDetails.entries) {
      final k = entry.key.toLowerCase().trim();
      if (!processedComplaintKeys.contains(k) && entry.value is Map) {
        final val = Map<String, dynamic>.from(entry.value as Map);
        storeAnamnesisItem(entry.key, val);
      }
    }

    // Populate from intake reasons (Section B)
    final intakeReasons = List<String>.from(demo['reasonsForVisit'] as List? ?? const <String>[]);
    final syncedClinicalComplaints = <String>{...complaintsList};
    for (final r in intakeReasons) {
      final lowerR = r.toLowerCase();
      final defaultEntry = {'present': true, 'active': true, 'duration': duration, 'options': <String>[], 'subOptions': <String>[], 'subOption': '', 'remarks': ''};
      if (lowerR.contains('hanging') || lowerR.contains('prolapse')) {
        anamnesisMap.putIfAbsent('prolapse', () => defaultEntry);
        anamnesisMap.putIfAbsent('something hanging out', () => defaultEntry);
        anamnesisMap.putIfAbsent('something_hanging_out', () => defaultEntry);
        syncedClinicalComplaints.add('prolapse');
      }
      if (lowerR.contains('discharge') || lowerR.contains('itching')) {
        anamnesisMap.putIfAbsent('discharge', () => defaultEntry);
        anamnesisMap.putIfAbsent('discharge and or itching', () => defaultEntry);
        anamnesisMap.putIfAbsent('discharge_and_or_itching', () => defaultEntry);
        anamnesisMap.putIfAbsent('discharge / itching', () => defaultEntry);
        anamnesisMap.putIfAbsent('discharge___itching', () => defaultEntry);
        anamnesisMap.putIfAbsent('discharge_itching', () => defaultEntry);
        syncedClinicalComplaints.add('discharge');
      }
      if (lowerR.contains('urine')) {
        anamnesisMap.putIfAbsent('urine', () => defaultEntry);
        anamnesisMap.putIfAbsent('problems passing urine', () => defaultEntry);
        anamnesisMap.putIfAbsent('problems_passing_urine', () => defaultEntry);
        syncedClinicalComplaints.add('urine');
      }
      if (lowerR.contains('back') || lowerR.contains('ढाड') || lowerR.contains('कम्मर')) {
        anamnesisMap.putIfAbsent('lower_back_pain', () => defaultEntry);
        anamnesisMap.putIfAbsent('lower back pain', () => defaultEntry);
        syncedClinicalComplaints.add('lower_back_pain');
      } else if (lowerR.contains('pain') || lowerR.contains('abdomen') || lowerR.contains('दुख्ने')) {
        anamnesisMap.putIfAbsent('lower_abdomen_pain', () => defaultEntry);
        anamnesisMap.putIfAbsent('lower abdomen pain', () => defaultEntry);
        syncedClinicalComplaints.add('lower_abdomen_pain');
      }
      if (lowerR.contains('stool')) {
        anamnesisMap.putIfAbsent('stool', () => defaultEntry);
        anamnesisMap.putIfAbsent('problems passing stool', () => defaultEntry);
        anamnesisMap.putIfAbsent('problems_passing_stool', () => defaultEntry);
        syncedClinicalComplaints.add('stool');
      }
      if (lowerR.contains('menstrual')) {
        anamnesisMap.putIfAbsent('menstrual', () => defaultEntry);
        anamnesisMap.putIfAbsent('menstrual problem', () => defaultEntry);
        anamnesisMap.putIfAbsent('menstrual_problem', () => defaultEntry);
        syncedClinicalComplaints.add('menstrual');
      }
      if (lowerR.contains('infertility')) {
        anamnesisMap.putIfAbsent('infertility', () => defaultEntry);
        syncedClinicalComplaints.add('infertility');
      }
    }
    anamnesisMap['clinicalComplaints'] = syncedClinicalComplaints.toList();

    final clinicalVisit = ClinicalVisitModel(
      id: 'vis-${_uuid.v4()}',
      patientId: registeredPatient.patientId,
      campId: campId,
      tenantId: registeredPatient.tenantId,
      visitDate: parsedVisit,
      deliveries: obs['deliveries'] as int?,
      livingChildren: obs['livingChildren'] as int?,
      abortions: obs['abortions'] as int?,
      anamnesisComplaints: anamnesisMap,
      uterusInside: pop['uterusInside'] as bool? ?? false,
      cervixRemarks: pop['cervixRemarks'] as String?,
      vaginaRemarks: pop['vaginaRemarks'] as String?,
      vulvaRemarks: pop['vulvaRemarks'] as String?,
      uterusRemarks: pop['uterusRemarks'] as String?,
      popAnteriorStage: pop['anteriorStage'] as int? ?? 0,
      popMiddleStage: pop['middleStage'] as int? ?? 0,
      popPosteriorStage: pop['posteriorStage'] as int? ?? 0,
      highestPopStage: () {
        final explicit = (pop['highestPopStage'] ?? pop['highestStage'] ?? pop['stage']) as int?;
        if (explicit != null) return explicit;
        final a = pop['anteriorStage'] as int? ?? 0;
        final m = pop['middleStage'] as int? ?? 0;
        final p = pop['posteriorStage'] as int? ?? 0;
        return [a, m, p].reduce((x, y) => x > y ? x : y);
      }(),
      systolicBp: vitals['systolicBp'] as int? ?? 120,
      diastolicBp: vitals['diastolicBp'] as int? ?? 80,
      pulse: vitals['pulseRate'] as int? ?? 78,
      spo2: vitals['spo2'] as int? ?? 98,
      glucose: vitals['bloodGlucose'] as int? ?? 110,
      urineTest: vitals['urineTest'] as String? ?? 'normal',
      pregnancyTest: vitals['pregnancyTest'] as String? ?? 'neg',
      ecgNotes: ((vitals['ecgNotes'] as String?)?.trim().isNotEmpty == true)
          ? (vitals['ecgNotes'] as String).trim()
          : ((vitals['ecg'] as String?)?.trim().isNotEmpty == true
              ? (vitals['ecg'] as String).trim()
              : null),
      diagnoses: verifiedScan.diagnoses,
      counseling: verifiedScan.counseling,
      medications: verifiedScan.medications,
      pessaryType: verifiedScan.pessaryType ??
          ((verifiedScan.ringPessary || pop['ringPessary'] == true)
              ? (pop['pessaryType'] as String? ?? 'ring')
              : null),
      pessarySize: verifiedScan.ringPessarySize != null
          ? '${verifiedScan.ringPessarySize}mm'
          : (pop['ringPessarySize'] != null ? '${pop['ringPessarySize']}mm' : null),
      surgeryDone: verifiedScan.surgeryDone || pop['surgeryDone'] == true,
      surgeryType: verifiedScan.surgeryType ?? pop['surgeryType'] as String?,
      surgicalReferral: verifiedScan.surgicalReferral,
      followUpNeeded: (verifiedScan.followUpDestination != null &&
              verifiedScan.followUpDestination != 'No follow up needed') ||
          (pop['highestPopStage'] as int? ?? 0) >= 2,
      followUpDestination: verifiedScan.followUpDestination,
      outtakeNotes: verifiedScan.clinicalNotes,
      primaryDoctorName: primaryDoctorName ?? verifiedScan.examiningDoctor,
      attendingDoctorNames: attendingDoctorNames.isNotEmpty
          ? attendingDoctorNames
          : (verifiedScan.attendingDoctors.isNotEmpty
              ? verifiedScan.attendingDoctors
              : ((primaryDoctorName ?? verifiedScan.examiningDoctor) != null
                  ? [(primaryDoctorName ?? verifiedScan.examiningDoctor)!]
                  : const [])),
      primaryNurseName: primaryNurseName ?? verifiedScan.examiningNurse,
      attendingNurseNames: attendingNurseNames.isNotEmpty
          ? attendingNurseNames
          : (verifiedScan.attendingNurses.isNotEmpty
              ? verifiedScan.attendingNurses
              : ((primaryNurseName ?? verifiedScan.examiningNurse) != null
                  ? [(primaryNurseName ?? verifiedScan.examiningNurse)!]
                  : const [])),
      treatmentLevel: PatientModel.normalizeTreatmentLevel(
        verifiedScan.treatmentLevel ?? demo['treatmentLevel'] as String? ?? demo['levelOfTreatment'] as String?,
      ),
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
      detailsJson: jsonEncode({
        'patientId': registeredPatient.patientId,
        'confidence': verifiedScan.overallConfidence,
        'ocrEngine': verifiedScan.ocrEngine,
        'primaryDoctor': clinicalVisit.primaryDoctorName,
        'attendingDoctors': clinicalVisit.attendingDoctorNames,
        'primaryNurse': clinicalVisit.primaryNurseName,
        'attendingNurses': clinicalVisit.attendingNurseNames,
      }),
      deviceId: deviceId,
    );

    return registeredPatient;
  }
}
