import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:nepali_utils/nepali_utils.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/clinical_constants.dart';
import '../core/constants/nepal_geodata.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
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
    String? existingPatientUuid,
    String? existingVisitId,
    String? archiveItemId,
    Uint8List? page1ImageBytes,
    String? page1ImagePath,
    Uint8List? page2ImageBytes,
    String? page2ImagePath,
    String reviewStatus = 'verified',
    bool preservePhotoArchive = true,
  });

  Future<OfflineScanQueueItem> enqueueOfflineScan({
    required String campId,
    required String campCode,
    Uint8List? page1Bytes,
    String? page1Path,
    Uint8List? page2Bytes,
    String? page2Path,
    String? patientTokenHint,
    String? patientIdHint,
    String? intakeDateHint,
    String? examiningNurseHint,
    String? examiningDoctorHint,
    required String userId,
    required String userName,
    required String userRole,
    required String deviceId,
    String tenantId = 'tenant_default',
  });

  Future<List<OfflineScanQueueItem>> getOfflineScanQueue({String? campId});
  Future<List<OfflineScanQueueItem>> getScanPhotoArchiveForPatient({
    String? patientUuid,
    String? patientId,
    String? campId,
    bool includePending = false,
  });
  Future<int> getPendingOfflineScanCount({String? campId});
  Future<void> deleteOfflineScanQueueItem(String id);
  Future<void> deleteScanPhoto(String id, {int? pageNumber});
  Future<int> deleteAllScanPhotos({String? campId});
  Future<OcrScanResultModel> extractQueuedOfflineItem(OfflineScanQueueItem item);
  Future<int> syncAndProcessAllOfflineScans({
    String? defaultUserId,
    String? defaultUserName,
    String? defaultUserRole,
    String? defaultDeviceId,
  });
}

class OcrRepository implements IOcrRepository {
  final DatabaseService _databaseService;
  final OcrFormService _ocrService;
  final IPatientRepository _patientRepository;
  final AuditRepository _auditRepository;
  final GeminiOcrService _geminiService;
  final MlKitOcrService Function() _mlkitFactory;
  final Uuid _uuid = const Uuid();

  OcrRepository({
    DatabaseService? databaseService,
    OcrFormService? ocrService,
    IPatientRepository? patientRepository,
    AuditRepository? auditRepository,
    GeminiOcrService? geminiService,
    MlKitOcrService Function()? mlkitFactory,
  })  : _databaseService = databaseService ?? DatabaseService(),
        _ocrService = ocrService ?? const OcrFormService(),
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
          debugPrint('[OcrRepo] 🌐 Attempting server OCR for page $detectedPage...');
        }
        final geminiResult = await _geminiService.extractFromImage(imageFile, pageNumber: detectedPage);
        if (kDebugMode) {
          debugPrint('[OcrRepo] ✅ Server OCR extraction succeeded for page $detectedPage');
          debugPrint('[OcrRepo] Demographics: ${geminiResult.demographics["firstName"]} ${geminiResult.demographics["surname"]}');
        }
        return geminiResult;
      } catch (e) {
        if (engineMode == OcrEngineMode.onlineGemini) {
          // Strict online mode: propagate failure to user
          if (kDebugMode) {
            debugPrint('[OcrRepo] ❌ Server OCR failed in strict online mode: $e');
          }
          rethrow;
        }
        // Auto mode: log warning and smoothly fall back to On-Device OCR
        if (kDebugMode) {
          debugPrint('[OcrRepo] ⚠️ Server OCR failed in AUTO mode: $e. Falling back to On-Device OCR.');
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

  /// Parses form/OCR BS (years 2070..2120) or AD date strings into Gregorian AD DateTimes.
  /// Clamps out-of-range BS days against the actual month length instead of resetting to day 1.
  @visibleForTesting
  static DateTime? parseFormDateOrNull(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    var clean = raw.trim();
    if (clean.toLowerCase() == 'null' || clean == '—' || clean == '-') return null;
    const devanagari = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];
    for (int i = 0; i < devanagari.length; i++) {
      clean = clean.replaceAll(devanagari[i], i.toString());
    }
    clean = clean.replaceAll(RegExp(r'\s*(BS|AD)\b', caseSensitive: false), '').trim();

    DateTime? bsToAdSafe(int year, int month, int day) {
      final safeMonth = month.clamp(1, 12);
      final maxDays = NepaliDateHelper.getDaysInBsMonth(year, safeMonth).clamp(1, 32);
      for (int tryDay = day.clamp(1, maxDays); tryDay >= 1; tryDay--) {
        try {
          return NepaliDateHelper.toEnglish(NepaliDateTime(year, safeMonth, tryDay));
        } catch (_) {}
      }
      return null;
    }

    try {
      final parts = clean.split(RegExp(r'[-/.\s]+')).where((s) => s.isNotEmpty).toList();
      if (parts.length == 3) {
        final p0 = int.tryParse(parts[0]);
        final p1 = int.tryParse(parts[1]);
        final p2 = int.tryParse(parts[2]);
        if (p0 != null && p1 != null && p2 != null) {
          int y;
          int m;
          int d;
          if (p0 >= 1900) {
            y = p0;
            m = p1;
            d = p2;
          } else if (p2 >= 1900) {
            // DD-MM-YYYY or DD/MM/YYYY
            d = p0;
            m = p1;
            y = p2;
          } else if (p0 >= 75 && p0 <= 99) {
            y = 2000 + p0;
            m = p1;
            d = p2;
          } else if (p2 >= 75 && p2 <= 99) {
            d = p0;
            m = p1;
            y = 2000 + p2;
          } else {
            y = p0;
            m = p1;
            d = p2;
          }
          if (m > 12 && d <= 12) {
            final tmp = m;
            m = d;
            d = tmp;
          }
          m = m.clamp(1, 12);
          if (y >= 2070 && y <= 2120) {
            return bsToAdSafe(y, m, d);
          } else if (y >= 1900 && y < 2070) {
            return DateTime(y, m, d.clamp(1, 31));
          }
        }
      }
      final iso = DateTime.tryParse(clean);
      if (iso != null) {
        if (iso.year >= 2070 && iso.year <= 2120) {
          return bsToAdSafe(iso.year, iso.month, iso.day) ?? iso;
        }
        return iso;
      }
      return null;
    } catch (_) {
      return null;
    }
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
    String? existingPatientUuid,
    String? existingVisitId,
    String? archiveItemId,
    Uint8List? page1ImageBytes,
    String? page1ImagePath,
    Uint8List? page2ImageBytes,
    String? page2ImagePath,
    String reviewStatus = 'verified',
    bool preservePhotoArchive = true,
  }) async {
    final demo = verifiedScan.demographics;
    final obs = verifiedScan.obstetrics;
    final vitals = verifiedScan.vitals;
    final pop = verifiedScan.popStaging;

    // 1. Construct Patient Model
    final rawToken = (demo['patientId'] as String? ?? demo['patientTokenId'] as String? ?? '').trim();

    DateTime? parseDateOrNull(String? raw) => parseFormDateOrNull(raw);

    DateTime parseDateSafe(String? raw) {
      return parseDateOrNull(raw) ?? DateTime.now();
    }

    final parsedIntake = parseDateSafe(
      verifiedScan.intakeDate ??
          demo['intakeDate'] as String? ??
          demo['date'] as String? ??
          verifiedScan.effectiveAnamnesisDate ??
          verifiedScan.anamnesisDate ??
          verifiedScan.examDate ??
          verifiedScan.treatmentDate ??
          verifiedScan.conclusionDate ??
          verifiedScan.labTestDate ??
          verifiedScan.outtakeDate,
    );
    final parsedVisit = parseDateSafe(
      verifiedScan.treatmentDate ??
          verifiedScan.conclusionDate ??
          verifiedScan.examDate ??
          verifiedScan.labTestDate ??
          verifiedScan.outtakeDate ??
          verifiedScan.effectiveAnamnesisDate ??
          verifiedScan.anamnesisDate ??
          verifiedScan.intakeDate ??
          demo['intakeDate'] as String? ??
          demo['date'] as String?,
    );

    final normalizedPatientId = PatientModel.normalizePatientId(
      rawInput: rawToken,
      campCode: campCode,
      year: parsedIntake.year,
    );

    // Resolve active camp location as fallback when Province / District / Palika / Ward were left blank on the paper form
    String campProvince = '';
    String campDistrict = '';
    String campMunicipality = '';
    String campWard = '';
    try {
      final db = await _databaseService.database;
      final campRows = await db.query(
        DatabaseTables.tableCamps,
        columns: ['province', 'district', 'municipality', 'ward'],
        where: 'id = ?',
        whereArgs: [campId],
        limit: 1,
      );
      if (campRows.isNotEmpty) {
        campProvince = (campRows.first['province'] as String?)?.trim() ?? '';
        campDistrict = (campRows.first['district'] as String?)?.trim() ?? '';
        campMunicipality = (campRows.first['municipality'] as String?)?.trim() ?? '';
        campWard = (campRows.first['ward'] as String?)?.trim() ?? '';
      }
    } catch (_) {}

    final resolvedDistrict = () {
      final d = (demo['district'] as String?)?.trim() ?? '';
      return d.isNotEmpty ? d : campDistrict;
    }();

    final resolvedProvince = () {
      final rawProv = (demo['province'] as String?)?.trim() ?? '';
      if (rawProv.isNotEmpty &&
          (resolvedDistrict.isEmpty ||
              NepalGeodata.districtsFor(rawProv)
                  .any((d) => d.toLowerCase() == resolvedDistrict.toLowerCase()))) {
        return rawProv;
      }
      if (resolvedDistrict.isNotEmpty) {
        return NepalGeodata.provinceOf(resolvedDistrict);
      }
      return rawProv.isNotEmpty ? rawProv : campProvince;
    }();

    final resolvedMunicipality = () {
      final m = (demo['municipality'] as String?)?.trim() ?? '';
      return m.isNotEmpty ? m : campMunicipality;
    }();

    final resolvedWard = () {
      final w = (demo['ward'] as String?)?.trim() ?? '';
      if (w.isNotEmpty) return w.padLeft(2, '0');
      if (campWard.isNotEmpty) return campWard.padLeft(2, '0');
      return '';
    }();

    final patient = PatientModel(
      id: 'pat-${_uuid.v4()}',
      patientId: normalizedPatientId, // Pre-assigned token or auto-generated sequentially by repository if empty
      campId: campId,
      campCode: campCode,
      intakeDate: parsedIntake,
      firstName: (demo['firstName'] as String? ?? '').trim(),
      surname: (demo['surname'] as String? ?? '').trim(),
      age: (demo['age'] as num?)?.toInt() ?? 0,
      spouseOrFatherName: () {
        final relName = (demo['relativeName'] as String? ?? '').trim();
        final relSur = (demo['relativeSurname'] as String? ?? '').trim();
        if (relName.isEmpty) return relSur.isNotEmpty ? relSur : null;
        if (relSur.isNotEmpty && !relName.toLowerCase().contains(relSur.toLowerCase())) {
          return '$relName $relSur';
        }
        return relName;
      }(),
      relationshipType: () {
        final rt = (demo['relativeType'] as String?)?.trim();
        return (rt != null && rt.isNotEmpty) ? rt : null;
      }(),
      mobile: (demo['mobile'] as String? ?? '').trim(),
      // Contact fields — now parsed by OCR service and carried through to DB
      contactPerson: demo['contactPerson'] as String?,
      contactMobile: demo['contactMobile'] as String?,
      // Marriage age — parsed from 'Age at Marriage' field on form
      maritalAge: (demo['maritalAge'] as num?)?.toInt(),
      province: resolvedProvince,
      district: resolvedDistrict,
      municipality: resolvedMunicipality,
      ward: resolvedWard,
      maritalStatus: (demo['maritalStatus'] as String? ?? '').trim(),
      reasonsForVisit: List<String>.from(demo['reasonsForVisit'] as List? ?? const <String>[]),
      consentTreatment: demo['consentTreatment'] as bool? ?? false,
      consentStoreMedicalInfo: demo['consentStoreMedicalInfo'] as bool? ?? false,
      treatmentLevel: PatientModel.normalizeTreatmentLevel(
        verifiedScan.treatmentLevel ?? demo['treatmentLevel'] as String? ?? demo['levelOfTreatment'] as String?,
      ),
      createdAt: DateTime.now(),
      createdByUserId: userId,
      createdByDeviceId: deviceId,
    );

    // Save or Update Patient in SQLite (if reviewing an existing committed patient or Token ID already exists, update existing record in-place)
    PatientModel? existingPatient;
    if (existingPatientUuid != null && existingPatientUuid.trim().isNotEmpty) {
      final db = await DatabaseService().database;
      final rows = await db.query(
        DatabaseTables.tablePatients,
        where: 'id = ?',
        whereArgs: [existingPatientUuid.trim()],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        existingPatient = PatientModel.fromMap(rows.first);
      }
    }
    existingPatient ??= normalizedPatientId.isNotEmpty
        ? await _patientRepository.getPatientByPatientId(normalizedPatientId)
        : null;

    final PatientRepository? concreteRepo =
        _patientRepository is PatientRepository ? _patientRepository : null;

    final PatientModel registeredPatient;
    if (existingPatient != null) {
      final updated = patient.copyWith(
        id: existingPatient.id,
        patientId: normalizedPatientId.isNotEmpty ? normalizedPatientId : existingPatient.patientId,
        createdAt: existingPatient.createdAt,
      );
      registeredPatient = concreteRepo != null
          ? await concreteRepo.updatePatient(
              updated,
              updatedByUserId: userId,
              updatedByUserName: userName,
              updatedByUserRole: userRole,
              deviceId: deviceId,
              pushToServer: false,
            )
          : await _patientRepository.updatePatient(
              updated,
              updatedByUserId: userId,
              updatedByUserName: userName,
              updatedByUserRole: userRole,
              deviceId: deviceId,
            );
    } else {
      registeredPatient = concreteRepo != null
          ? await concreteRepo.registerPatient(
              patient,
              createdByUserId: userId,
              createdByUserName: userName,
              createdByUserRole: userRole,
              deviceId: deviceId,
              pushToServer: false,
            )
          : await _patientRepository.registerPatient(
              patient,
              createdByUserId: userId,
              createdByUserName: userName,
              createdByUserRole: userRole,
              deviceId: deviceId,
            );
    }

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
        if (!syncedClinicalComplaints.contains('lower_back_pain')) {
          anamnesisMap.putIfAbsent('lower_abdomen_pain', () => defaultEntry);
          anamnesisMap.putIfAbsent('lower abdomen pain', () => defaultEntry);
          syncedClinicalComplaints.add('lower_abdomen_pain');
        }
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
      if (lowerR.contains('checkup')) {
        anamnesisMap.putIfAbsent('checkup', () => defaultEntry);
        syncedClinicalComplaints.add('checkup');
      }
    }
    anamnesisMap['clinicalComplaints'] = syncedClinicalComplaints.toList();

    final defaultMedsLow = ClinicalConstants.defaultMedications.map((m) => m.toLowerCase()).toSet();
    final formularyMeds = <String>[];
    final nonDefaultMeds = <String>[];
    for (final rawMed in verifiedScan.medications) {
      final clean = rawMed.trim();
      if (clean.isEmpty) continue;
      final low = clean.toLowerCase();
      if (defaultMedsLow.contains(low) || low == 'ring pessary') {
        formularyMeds.add(clean);
      } else {
        nonDefaultMeds.add(clean);
      }
    }

    String resolvedVisitId = 'vis-${_uuid.v4()}';
    if (existingVisitId != null && existingVisitId.trim().isNotEmpty) {
      resolvedVisitId = existingVisitId.trim();
    } else if (existingPatient != null &&
        ((archiveItemId != null && archiveItemId.trim().isNotEmpty) ||
            (existingPatientUuid != null && existingPatientUuid.trim().isNotEmpty))) {
      final latestVisit = await _patientRepository.getLatestClinicalVisit(
        registeredPatient.patientId,
        patientUuid: registeredPatient.id,
      );
      if (latestVisit != null && latestVisit.id.isNotEmpty) {
        resolvedVisitId = latestVisit.id;
      }
    }

    final clinicalVisit = ClinicalVisitModel(
      id: resolvedVisitId,
      patientId: registeredPatient.patientId,
      campId: campId,
      tenantId: registeredPatient.tenantId,
      visitDate: parsedVisit,
      anamnesisDate: parseDateOrNull(verifiedScan.effectiveAnamnesisDate ?? verifiedScan.anamnesisDate ?? demo['anamnesisDate'] as String? ?? verifiedScan.intakeDate ?? demo['intakeDate'] as String? ?? demo['date'] as String?),
      examDate: parseDateOrNull(verifiedScan.examDate),
      labTestDate: parseDateOrNull(verifiedScan.labTestDate),
      conclusionDate: parseDateOrNull(verifiedScan.conclusionDate),
      treatmentDate: parseDateOrNull(verifiedScan.treatmentDate),
      outtakeDate: parseDateOrNull(verifiedScan.outtakeDate),
      deliveries: (obs['deliveries'] as num?)?.toInt(),
      livingChildren: (obs['livingChildren'] as num?)?.toInt(),
      abortions: (obs['abortions'] as num?)?.toInt(),
      anamnesisComplaints: anamnesisMap,
      uterusInside: pop['uterusInside'] as bool?,
      pelvicFloorTone: () {
        final t = (pop['pelvicFloorTone'] as String?)?.trim().toLowerCase();
        return (t != null && t.isNotEmpty && t != 'null') ? t : null;
      }(),
      cervixRemarks: () {
        final s = (pop['cervixRemarks'] as String?)?.trim();
        return (s != null && s.isNotEmpty && s.toLowerCase() != 'null') ? s : null;
      }(),
      vaginaRemarks: () {
        final s = (pop['vaginaRemarks'] as String?)?.trim();
        return (s != null && s.isNotEmpty && s.toLowerCase() != 'null') ? s : null;
      }(),
      vulvaRemarks: () {
        final s = (pop['vulvaRemarks'] as String?)?.trim();
        return (s != null && s.isNotEmpty && s.toLowerCase() != 'null') ? s : null;
      }(),
      uterusRemarks: () {
        final s = (pop['uterusRemarks'] as String?)?.trim();
        return (s != null && s.isNotEmpty && s.toLowerCase() != 'null') ? s : null;
      }(),
      popAnteriorStage: (pop['anteriorStage'] as num?)?.toInt(),
      popMiddleStage: (pop['middleStage'] as num?)?.toInt(),
      popPosteriorStage: (pop['posteriorStage'] as num?)?.toInt(),
      highestPopStage: () {
        final explicit = ((pop['highestPopStage'] ?? pop['highestStage'] ?? pop['stage']) as num?)?.toInt();
        if (explicit != null) return explicit;
        return ClinicalVisitModel.computeHighestPopStageOrNull(
          (pop['anteriorStage'] as num?)?.toInt(),
          (pop['middleStage'] as num?)?.toInt(),
          (pop['posteriorStage'] as num?)?.toInt(),
        );
      }(),
      systolicBp: () {
        final v = (vitals['systolicBp'] as num?)?.toInt();
        return (v != null && v > 0) ? v : null;
      }(),
      diastolicBp: () {
        final v = (vitals['diastolicBp'] as num?)?.toInt();
        return (v != null && v > 0) ? v : null;
      }(),
      pulse: () {
        final v = ((vitals['pulseRate'] ?? vitals['pulse']) as num?)?.toInt();
        return (v != null && v > 0) ? v : null;
      }(),
      spo2: () {
        final v = (vitals['spo2'] as num?)?.toInt();
        return (v != null && v > 0) ? v : null;
      }(),
      glucose: () {
        final v = ((vitals['bloodGlucose'] ?? vitals['glucose']) as num?)?.toInt();
        return (v != null && v > 0) ? v : null;
      }(),
      urineTest: () {
        final u = (vitals['urineTest'] as String?)?.trim();
        return (u != null && u.isNotEmpty && u.toLowerCase() != 'null') ? u : null;
      }(),
      pregnancyTest: () {
        final p = (vitals['pregnancyTest'] as String?)?.trim();
        return (p != null && p.isNotEmpty && p.toLowerCase() != 'null') ? p : null;
      }(),
      ecgNotes: () {
        final rawEcg = (vitals['ecg'] as String?)?.trim();
        final rawNotes = (vitals['ecgNotes'] as String?)?.trim();
        if (rawNotes != null && rawNotes.isNotEmpty) {
          if (rawEcg != null && rawEcg.isNotEmpty && !rawNotes.toLowerCase().contains(rawEcg.toLowerCase())) {
            return '$rawEcg: $rawNotes';
          }
          return rawNotes;
        }
        return (rawEcg != null && rawEcg.isNotEmpty) ? rawEcg : null;
      }(),
      diagnoses: verifiedScan.diagnoses,
      counseling: verifiedScan.counseling,
      medications: formularyMeds,
      customMedication: nonDefaultMeds.isNotEmpty ? nonDefaultMeds.join(', ') : null,
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
              verifiedScan.followUpDestination!.trim().toLowerCase() != 'no follow up needed') ||
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

    // Save Clinical Visit in SQLite (deferring server push until both rows exist locally)
    final savedVisit = concreteRepo != null
        ? await concreteRepo.saveClinicalVisit(
            clinicalVisit,
            createdByUserId: userId,
            deviceId: deviceId,
            pushToServer: false,
          )
        : await _patientRepository.saveClinicalVisit(
            clinicalVisit,
            createdByUserId: userId,
            deviceId: deviceId,
          );

    // Push patient + clinical visit together in one central sync payload
    if (concreteRepo != null) {
      unawaited(
        concreteRepo.pushPatientAndVisitToServer(
          patient: registeredPatient,
          visit: savedVisit,
          deviceId: deviceId,
        ),
      );
    }

    // 2b. Persist or update the scanned Yellow Form photos (Page 1 & Page 2) in local archive
    // so staff can review and correct extracted fields later or delete the photos when done.
    try {
      await _persistCommittedScanPhotoArchive(
        archiveItemId: archiveItemId,
        verifiedScan: verifiedScan,
        registeredPatient: registeredPatient,
        savedVisit: savedVisit,
        campId: campId,
        campCode: campCode,
        userId: userId,
        userName: userName,
        userRole: userRole,
        deviceId: deviceId,
        page1ImageBytes: page1ImageBytes,
        page1ImagePath: page1ImagePath ?? verifiedScan.page1ImagePath ?? verifiedScan.imagePath,
        page2ImageBytes: page2ImageBytes,
        page2ImagePath: page2ImagePath ?? verifiedScan.page2ImagePath,
        reviewStatus: reviewStatus,
        preservePhotoArchive: preservePhotoArchive,
      );
    } catch (_) {}

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

  @override
  Future<OfflineScanQueueItem> enqueueOfflineScan({
    required String campId,
    required String campCode,
    Uint8List? page1Bytes,
    String? page1Path,
    Uint8List? page2Bytes,
    String? page2Path,
    String? patientTokenHint,
    String? patientIdHint,
    String? intakeDateHint,
    String? examiningNurseHint,
    String? examiningDoctorHint,
    required String userId,
    required String userName,
    required String userRole,
    required String deviceId,
    String tenantId = 'tenant_default',
  }) async {
    final db = await _databaseService.database;
    String? p1Base64;
    if (page1Bytes != null && page1Bytes.isNotEmpty) {
      final prepared = await _geminiService.prepareImageForStorage(page1Bytes);
      p1Base64 = prepared.base64;
    }
    String? p2Base64;
    if (page2Bytes != null && page2Bytes.isNotEmpty) {
      final prepared = await _geminiService.prepareImageForStorage(page2Bytes);
      p2Base64 = prepared.base64;
    }

    final effectiveTokenHint = (patientTokenHint != null && patientTokenHint.trim().isNotEmpty)
        ? patientTokenHint.trim()
        : patientIdHint?.trim();

    final now = DateTime.now();
    final item = OfflineScanQueueItem(
      id: 'offscan-${_uuid.v4()}',
      campId: campId,
      campCode: campCode,
      page1ImageBase64: p1Base64,
      page1ImagePath: page1Path,
      page2ImageBase64: p2Base64,
      page2ImagePath: page2Path,
      patientTokenHint: effectiveTokenHint,
      intakeDateHint: intakeDateHint?.trim(),
      examiningNurseHint: examiningNurseHint?.trim(),
      examiningDoctorHint: examiningDoctorHint?.trim(),
      status: 'pending',
      createdByUserId: userId,
      createdByUserName: userName,
      createdByUserRole: userRole,
      deviceId: deviceId,
      tenantId: tenantId,
      createdAt: now,
      updatedAt: now,
    );

    await db.insert(
      DatabaseTables.tableOfflineScanQueue,
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _auditRepository.logActivity(
      userId: userId,
      userName: userName,
      userRole: userRole,
      action: AppConstants.auditActionOfflineScanQueued,
      entityType: 'OfflineScanQueue',
      entityId: item.id,
      detailsJson: jsonEncode({
        'campId': campId,
        'campCode': campCode,
        'hasPage1': item.hasPage1,
        'hasPage2': item.hasPage2,
        'patientTokenHint': item.patientTokenHint,
        'intakeDateHint': item.intakeDateHint,
      }),
      deviceId: deviceId,
    );

    return item;
  }

  Future<void> _persistCommittedScanPhotoArchive({
    String? archiveItemId,
    required OcrScanResultModel verifiedScan,
    required PatientModel registeredPatient,
    required ClinicalVisitModel savedVisit,
    required String campId,
    required String campCode,
    required String userId,
    required String userName,
    required String userRole,
    required String deviceId,
    Uint8List? page1ImageBytes,
    String? page1ImagePath,
    Uint8List? page2ImageBytes,
    String? page2ImagePath,
    required String reviewStatus,
    required bool preservePhotoArchive,
  }) async {
    final db = await _databaseService.database;
    final nowIso = DateTime.now().toIso8601String();
    final extractedJsonStr = jsonEncode(verifiedScan.toMap());

    // Prepare Page 1 & Page 2 in parallel so multi-megabyte Android camera photos
    // compress concurrently across background isolates instead of sequentially.
    final preparedPages = await Future.wait<String?>([
      (page1ImageBytes != null && page1ImageBytes.isNotEmpty)
          ? _geminiService
              .prepareImageForStorage(page1ImageBytes)
              .then((p) => p.base64)
          : Future<String?>.value(null),
      (page2ImageBytes != null && page2ImageBytes.isNotEmpty)
          ? _geminiService
              .prepareImageForStorage(page2ImageBytes)
              .then((p) => p.base64)
          : Future<String?>.value(null),
    ]);
    final String? p1Base64 = preparedPages[0];
    final String? p2Base64 = preparedPages[1];

    if (archiveItemId != null && archiveItemId.trim().isNotEmpty) {
      final targetArchiveId = archiveItemId.trim();
      final updateMap = <String, dynamic>{
        'status': 'completed',
        'review_status': reviewStatus,
        'error_message': null,
        'committed_patient_uuid': registeredPatient.id,
        'committed_patient_id': registeredPatient.patientId,
        'committed_patient_name': registeredPatient.fullName,
        'committed_visit_id': savedVisit.id,
        'patient_token_hint': registeredPatient.patientId,
        'extracted_json': extractedJsonStr,
        'updated_at': nowIso,
      };
      if (p1Base64 != null) updateMap['page1_image_base64'] = p1Base64;
      if (page1ImagePath != null && page1ImagePath.trim().isNotEmpty) {
        updateMap['page1_image_path'] = page1ImagePath.trim();
      }
      if (p2Base64 != null) updateMap['page2_image_base64'] = p2Base64;
      if (page2ImagePath != null && page2ImagePath.trim().isNotEmpty) {
        updateMap['page2_image_path'] = page2ImagePath.trim();
      }
      await db.update(
        DatabaseTables.tableOfflineScanQueue,
        updateMap,
        where: 'id = ?',
        whereArgs: [targetArchiveId],
      );
      // Clean up any duplicate completed archive rows for this same patient UUID
      await db.delete(
        DatabaseTables.tableOfflineScanQueue,
        where: "status = 'completed' AND committed_patient_uuid = ? AND id != ?",
        whereArgs: [registeredPatient.id, targetArchiveId],
      );
      return;
    }

    if (!preservePhotoArchive) return;
    final hasAnyPhoto = (p1Base64 != null && p1Base64.isNotEmpty) ||
        (p2Base64 != null && p2Base64.isNotEmpty) ||
        (page1ImagePath != null && page1ImagePath.trim().isNotEmpty) ||
        (page2ImagePath != null && page2ImagePath.trim().isNotEmpty);
    if (!hasAnyPhoto) return;

    final canonicalArchiveId = 'scanarch-${registeredPatient.id}';
    // Ensure at most one completed archive row exists per committed patient UUID
    await db.delete(
      DatabaseTables.tableOfflineScanQueue,
      where: "status = 'completed' AND committed_patient_uuid = ? AND id != ?",
      whereArgs: [registeredPatient.id, canonicalArchiveId],
    );

    final now = DateTime.now();
    final archiveItem = OfflineScanQueueItem(
      id: canonicalArchiveId,
      campId: campId,
      campCode: campCode,
      page1ImageBase64: p1Base64,
      page1ImagePath: page1ImagePath,
      page2ImageBase64: p2Base64,
      page2ImagePath: page2ImagePath,
      patientTokenHint: registeredPatient.patientId,
      intakeDateHint: verifiedScan.intakeDate,
      examiningNurseHint: savedVisit.primaryNurseName,
      examiningDoctorHint: savedVisit.primaryDoctorName,
      status: 'completed',
      reviewStatus: reviewStatus,
      committedPatientUuid: registeredPatient.id,
      committedPatientId: registeredPatient.patientId,
      committedPatientName: registeredPatient.fullName,
      committedVisitId: savedVisit.id,
      extractedJson: extractedJsonStr,
      createdByUserId: userId,
      createdByUserName: userName,
      createdByUserRole: userRole,
      deviceId: deviceId,
      tenantId: registeredPatient.tenantId,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert(
      DatabaseTables.tableOfflineScanQueue,
      archiveItem.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Reads a potentially large TEXT column (such as Base64 scan images) in 800 KB
  /// SUBSTR chunks so it NEVER exceeds Android's 2 MB SQLite CursorWindow limit,
  /// even for legacy uncompressed multi-megabyte rows already stored on disk.
  Future<String?> _readChunkedTextColumn(
    Database db,
    String rowId,
    String columnName,
    int totalLen,
  ) async {
    if (totalLen <= 0) return null;
    const int chunkSize = 800000;
    if (totalLen <= chunkSize) {
      final rows = await db.rawQuery(
        'SELECT $columnName AS val FROM ${DatabaseTables.tableOfflineScanQueue} WHERE id = ? LIMIT 1',
        [rowId],
      );
      if (rows.isEmpty) return null;
      return rows.first['val'] as String?;
    }

    final buffer = StringBuffer();
    int offset = 1; // SQLite SUBSTR is 1-indexed
    while (offset <= totalLen) {
      final rows = await db.rawQuery(
        'SELECT SUBSTR($columnName, ?, ?) AS chunk FROM ${DatabaseTables.tableOfflineScanQueue} WHERE id = ? LIMIT 1',
        [offset, chunkSize, rowId],
      );
      if (rows.isEmpty) break;
      final chunk = rows.first['chunk'] as String?;
      if (chunk == null || chunk.isEmpty) break;
      buffer.write(chunk);
      offset += chunkSize;
    }
    final result = buffer.toString();
    return result.isNotEmpty ? result : null;
  }

  /// Queries `offline_scan_queue` safely across all platforms.
  /// On Web (no Android 2 MB CursorWindow limit), uses a single query to minimize
  /// Web Worker IPC round-trips. On native platforms (Android/iOS/Desktop), reads
  /// large Base64 image columns in 800 KB SUBSTR chunks so Android's 2 MB
  /// SQLite CursorWindow never overflows.
  Future<List<OfflineScanQueueItem>> _queryOfflineScanItems(
    Database db, {
    String? where,
    List<Object?>? whereArgs,
    String orderBy = 'updated_at DESC, created_at DESC',
    int? limit,
  }) async {
    if (kIsWeb) {
      final rows = await db.query(
        DatabaseTables.tableOfflineScanQueue,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
      );
      return rows.map((r) => OfflineScanQueueItem.fromMap(r)).toList();
    }

    final whereClause = (where != null && where.trim().isNotEmpty)
        ? 'WHERE $where'
        : '';
    final limitClause = limit != null ? 'LIMIT $limit' : '';
    final metaRows = await db.rawQuery(
      '''
      SELECT id, camp_id, camp_code, page1_image_path, page2_image_path,
             patient_token_hint, intake_date_hint, examining_nurse_hint, examining_doctor_hint,
             status, review_status, error_message,
             committed_patient_uuid, committed_patient_id, committed_patient_name, committed_visit_id,
             extracted_json, created_by_user_id, created_by_user_name, created_by_user_role,
             device_id, tenant_id, created_at, updated_at,
             LENGTH(page1_image_base64) AS p1_len,
             LENGTH(page2_image_base64) AS p2_len
      FROM ${DatabaseTables.tableOfflineScanQueue}
      $whereClause
      ORDER BY $orderBy
      $limitClause
      ''',
      whereArgs,
    );

    final items = <OfflineScanQueueItem>[];
    for (final meta in metaRows) {
      final rowId = meta['id'] as String? ?? '';
      if (rowId.isEmpty) continue;
      final p1Len = (meta['p1_len'] as num?)?.toInt() ?? 0;
      final p2Len = (meta['p2_len'] as num?)?.toInt() ?? 0;

      final p1Base64 = await _readChunkedTextColumn(
        db,
        rowId,
        'page1_image_base64',
        p1Len,
      );
      final p2Base64 = await _readChunkedTextColumn(
        db,
        rowId,
        'page2_image_base64',
        p2Len,
      );

      final fullMap = Map<String, dynamic>.from(meta)
        ..['page1_image_base64'] = p1Base64
        ..['page2_image_base64'] = p2Base64;
      items.add(OfflineScanQueueItem.fromMap(fullMap));
    }
    return items;
  }

  @override
  Future<List<OfflineScanQueueItem>> getOfflineScanQueue({String? campId}) async {
    final db = await _databaseService.database;
    final hasCampFilter = campId != null && campId.isNotEmpty && campId != 'all';
    return _queryOfflineScanItems(
      db,
      where: hasCampFilter ? 'camp_id = ?' : null,
      whereArgs: hasCampFilter ? [campId] : null,
      orderBy: 'updated_at DESC, created_at DESC',
    );
  }

  @override
  Future<List<OfflineScanQueueItem>> getScanPhotoArchiveForPatient({
    String? patientUuid,
    String? patientId,
    String? campId,
    bool includePending = false,
  }) async {
    final db = await _databaseService.database;
    final cleanUuid = patientUuid?.trim() ?? '';
    final cleanPid = patientId?.trim() ?? '';
    final cleanCampId = campId?.trim() ?? '';
    if (cleanUuid.isEmpty && cleanPid.isEmpty) return const [];

    final idClauses = <String>[];
    final args = <Object?>[];
    if (cleanUuid.isNotEmpty) {
      idClauses.add('committed_patient_uuid = ? OR id = ?');
      args.addAll([cleanUuid, 'scanarch-$cleanUuid']);
    }
    if (cleanPid.isNotEmpty) {
      if (cleanUuid.isNotEmpty) {
        idClauses.add(
          "((committed_patient_uuid IS NULL OR TRIM(committed_patient_uuid) = '' OR committed_patient_uuid = ?) "
          'AND (LOWER(committed_patient_id) = LOWER(?) OR LOWER(patient_token_hint) = LOWER(?)))',
        );
        args.addAll([cleanUuid, cleanPid, cleanPid]);
      } else {
        idClauses.add(
          '(LOWER(committed_patient_id) = LOWER(?) OR LOWER(patient_token_hint) = LOWER(?))',
        );
        args.addAll([cleanPid, cleanPid]);
      }
    }

    final whereParts = <String>['(${idClauses.join(' OR ')})'];
    if (cleanCampId.isNotEmpty && cleanCampId != 'all') {
      whereParts.add('camp_id = ?');
      args.add(cleanCampId);
    }
    if (!includePending) {
      whereParts.add("status = 'completed'");
    }

    final items = await _queryOfflineScanItems(
      db,
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'updated_at DESC, created_at DESC',
    );
    return items.where((item) => item.hasAnyImage).toList();
  }

  @override
  Future<int> getPendingOfflineScanCount({String? campId}) async {
    final db = await _databaseService.database;
    final hasCampFilter = campId != null && campId.isNotEmpty && campId != 'all';
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        hasCampFilter
            ? "SELECT COUNT(*) FROM ${DatabaseTables.tableOfflineScanQueue} WHERE camp_id = ? AND status IN ('pending', 'failed')"
            : "SELECT COUNT(*) FROM ${DatabaseTables.tableOfflineScanQueue} WHERE status IN ('pending', 'failed')",
        hasCampFilter ? [campId] : null,
      ),
    );
    return count ?? 0;
  }

  @override
  Future<void> deleteOfflineScanQueueItem(String id) async {
    final db = await _databaseService.database;
    await db.delete(
      DatabaseTables.tableOfflineScanQueue,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteScanPhoto(String id, {int? pageNumber}) async {
    final db = await _databaseService.database;
    if (pageNumber == null) {
      final metaRows = await db.query(
        DatabaseTables.tableOfflineScanQueue,
        columns: ['camp_id', 'status', 'committed_patient_uuid'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      await deleteOfflineScanQueueItem(id);
      if (metaRows.isNotEmpty) {
        final meta = metaRows.first;
        final status = (meta['status'] as String?)?.trim() ?? '';
        final patUuid = (meta['committed_patient_uuid'] as String?)?.trim() ?? '';
        final rowCampId = (meta['camp_id'] as String?)?.trim() ?? '';
        if (status == 'completed' && patUuid.isNotEmpty) {
          if (rowCampId.isNotEmpty) {
            await db.delete(
              DatabaseTables.tableOfflineScanQueue,
              where: "status = 'completed' AND committed_patient_uuid = ? AND camp_id = ?",
              whereArgs: [patUuid, rowCampId],
            );
          } else {
            await db.delete(
              DatabaseTables.tableOfflineScanQueue,
              where: "status = 'completed' AND committed_patient_uuid = ?",
              whereArgs: [patUuid],
            );
          }
        }
      }
      return;
    }
    final rows = await db.rawQuery(
      '''
      SELECT id, page1_image_path, page2_image_path,
             LENGTH(page1_image_base64) AS p1_len,
             LENGTH(page2_image_base64) AS p2_len
      FROM ${DatabaseTables.tableOfflineScanQueue}
      WHERE id = ?
      LIMIT 1
      ''',
      [id],
    );
    if (rows.isEmpty) return;

    final row = rows.first;
    final hasP1 = ((row['p1_len'] as num?)?.toInt() ?? 0) > 0 ||
        ((row['page1_image_path'] as String?)?.trim().isNotEmpty ?? false);
    final hasP2 = ((row['p2_len'] as num?)?.toInt() ?? 0) > 0 ||
        ((row['page2_image_path'] as String?)?.trim().isNotEmpty ?? false);
    final clearPage1 = pageNumber == 1;
    final clearPage2 = pageNumber == 2;
    final remainingHasPage1 = !clearPage1 && hasP1;
    final remainingHasPage2 = !clearPage2 && hasP2;

    if (!remainingHasPage1 && !remainingHasPage2) {
      await deleteOfflineScanQueueItem(id);
      return;
    }

    await db.update(
      DatabaseTables.tableOfflineScanQueue,
      {
        if (clearPage1) 'page1_image_base64': null,
        if (clearPage1) 'page1_image_path': null,
        if (clearPage2) 'page2_image_base64': null,
        if (clearPage2) 'page2_image_path': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<int> deleteAllScanPhotos({String? campId}) async {
    final db = await _databaseService.database;
    final cleanCampId = campId?.trim() ?? '';
    final hasCampFilter = cleanCampId.isNotEmpty && cleanCampId != 'all';
    final where = hasCampFilter
        ? "status = 'completed' AND camp_id = ?"
        : "status = 'completed'";
    final whereArgs = hasCampFilter ? <Object?>[cleanCampId] : null;
    return db.delete(
      DatabaseTables.tableOfflineScanQueue,
      where: where,
      whereArgs: whereArgs,
    );
  }

  @override
  Future<OcrScanResultModel> extractQueuedOfflineItem(OfflineScanQueueItem item) async {
    OcrScanResultModel? scan1;
    OcrScanResultModel? scan2;

    if (item.page1ImageBase64 != null && item.page1ImageBase64!.isNotEmpty) {
      final bytes1 = base64Decode(item.page1ImageBase64!);
      scan1 = await _geminiService.extractFromBytes(
        bytes1,
        imagePath: item.page1ImagePath ?? 'offline_page1.jpg',
        pageNumber: 1,
      );
    } else if (item.page1ImagePath != null && item.page1ImagePath!.isNotEmpty) {
      scan1 = await _geminiService.extractFromImage(
        XFile(item.page1ImagePath!),
        pageNumber: 1,
      );
    }

    if (item.page2ImageBase64 != null && item.page2ImageBase64!.isNotEmpty) {
      final bytes2 = base64Decode(item.page2ImageBase64!);
      scan2 = await _geminiService.extractFromBytes(
        bytes2,
        imagePath: item.page2ImagePath ?? 'offline_page2.jpg',
        pageNumber: 2,
      );
    } else if (item.page2ImagePath != null && item.page2ImagePath!.isNotEmpty) {
      scan2 = await _geminiService.extractFromImage(
        XFile(item.page2ImagePath!),
        pageNumber: 2,
      );
    }

    OcrScanResultModel result;
    if (scan1 != null && scan2 != null) {
      result = OcrScanResultModel.merge(scan1, scan2);
    } else if (scan1 != null) {
      result = scan1;
    } else if (scan2 != null) {
      result = scan2;
    } else {
      throw const GeminiOcrException('Offline scan item contains no readable image data.');
    }

    // Apply any operator-supplied hints recorded when queued offline
    final updatedDemo = Map<String, dynamic>.from(result.demographics);
    String? effectiveIntake = result.intakeDate;
    if (item.patientTokenHint != null && item.patientTokenHint!.trim().isNotEmpty) {
      updatedDemo['patientId'] = item.patientTokenHint!.trim();
      updatedDemo['patientTokenId'] = item.patientTokenHint!.trim();
    }
    if (item.intakeDateHint != null && item.intakeDateHint!.trim().isNotEmpty) {
      effectiveIntake = item.intakeDateHint!.trim();
      updatedDemo['intakeDate'] = effectiveIntake;
      updatedDemo['date'] = effectiveIntake;
    }

    return result.copyWith(
      demographics: updatedDemo,
      intakeDate: effectiveIntake,
      examiningNurse: (item.examiningNurseHint != null && item.examiningNurseHint!.trim().isNotEmpty)
          ? item.examiningNurseHint!.trim()
          : result.examiningNurse,
      attendingNurses: (item.examiningNurseHint != null && item.examiningNurseHint!.trim().isNotEmpty)
          ? <String>{...result.attendingNurses, item.examiningNurseHint!.trim()}.toList()
          : result.attendingNurses,
      examiningDoctor: (item.examiningDoctorHint != null && item.examiningDoctorHint!.trim().isNotEmpty)
          ? item.examiningDoctorHint!.trim()
          : result.examiningDoctor,
      attendingDoctors: (item.examiningDoctorHint != null && item.examiningDoctorHint!.trim().isNotEmpty)
          ? <String>{...result.attendingDoctors, item.examiningDoctorHint!.trim()}.toList()
          : result.attendingDoctors,
    );
  }

  @override
  Future<int> syncAndProcessAllOfflineScans({
    String? defaultUserId,
    String? defaultUserName,
    String? defaultUserRole,
    String? defaultDeviceId,
  }) async {
    final db = await _databaseService.database;
    final items = await _queryOfflineScanItems(
      db,
      where: "status IN ('pending', 'failed')",
      orderBy: 'created_at ASC',
    );
    if (items.isEmpty) return 0;

    int processedCount = 0;
    for (final item in items) {
      try {
        await db.update(
          DatabaseTables.tableOfflineScanQueue,
          {'status': 'processing', 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [item.id],
        );

        final extracted = await extractQueuedOfflineItem(item);
        await commitVerifiedScan(
          verifiedScan: extracted,
          campId: item.campId,
          campCode: item.campCode,
          userId: item.createdByUserId.isNotEmpty ? item.createdByUserId : (defaultUserId ?? 'usr-local'),
          userName: item.createdByUserName.isNotEmpty ? item.createdByUserName : (defaultUserName ?? 'Field Staff'),
          userRole: item.createdByUserRole.isNotEmpty ? item.createdByUserRole : (defaultUserRole ?? 'DATA_TAKER'),
          deviceId: item.deviceId.isNotEmpty ? item.deviceId : (defaultDeviceId ?? 'dev-local'),
          primaryDoctorName: extracted.examiningDoctor,
          attendingDoctorNames: extracted.attendingDoctors,
          primaryNurseName: extracted.examiningNurse,
          attendingNurseNames: extracted.attendingNurses,
          archiveItemId: item.id,
          reviewStatus: 'needs_review',
        );

        processedCount++;
      } catch (e) {
        await db.update(
          DatabaseTables.tableOfflineScanQueue,
          {
            'status': 'failed',
            'error_message': e.toString(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [item.id],
        );
        // Stop draining if server is unreachable so we retry on next connectivity wakeup
        if (e is GeminiOcrException && e.message.contains('Cannot reach')) {
          break;
        }
      }
    }
    return processedCount;
  }
}
