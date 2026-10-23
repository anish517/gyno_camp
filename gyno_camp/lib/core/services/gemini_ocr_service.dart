import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../constants/app_constants.dart';
import '../constants/clinical_constants.dart';
import '../constants/nepal_geodata.dart';
import '../../models/nurse_profile.dart';
import '../../models/ocr_scan_result_model.dart';
import '../security/security_service.dart';
import 'http_central_api_service.dart';
import 'session_service.dart';

class GeminiOcrException implements Exception {
  final String message;
  final int? statusCode;
  const GeminiOcrException(this.message, {this.statusCode});

  @override
  String toString() => 'GeminiOcrException: $message (status: $statusCode)';
}

/// Cloud multimodal OCR client for the Nepal MoHP Yellow Form.
///
/// SECURITY: this client NEVER holds or sends a Gemini API key. Images are sent
/// to the GynoCamp central server (`POST /api/ocr/extract`), which authenticates
/// the approved device, applies rate limits, and calls Gemini using a key that
/// exists only in the server environment.
///
/// Features:
/// - Direct visual parsing of photographed Yellow Intake Forms (Nepal MoHP format).
/// - Built-in image optimization (scales large images to max 1600px to reduce payload size).
/// - Structured JSON output mapped directly to [OcrScanResultModel] with `ocrEngine: 'gemini_flash'`.
/// - Model failover and retry logic live on the server.
class GeminiOcrService {
  final http.Client _client;
  final String? _explicitBaseUrl;
  final String? _explicitFingerprint;
  final String? _explicitDeviceSecret;

  /// The server may fail over across several models (30s each), so allow time.
  static const Duration requestTimeout = Duration(seconds: 75);

  GeminiOcrService({
    http.Client? httpClient,
    String? baseUrl,
    String? deviceFingerprint,
    String? deviceSecret,
  })  : _client = httpClient ?? http.Client(),
        _explicitBaseUrl = baseUrl,
        _explicitFingerprint = deviceFingerprint,
        _explicitDeviceSecret = deviceSecret;

  String get _baseUrl {
    final explicit = _explicitBaseUrl?.trim();
    final raw = (explicit != null && explicit.isNotEmpty)
        ? explicit
        : HttpCentralApiService(client: _client).baseUrl;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  String get _deviceFingerprint =>
      (_explicitFingerprint != null && _explicitFingerprint.trim().isNotEmpty)
          ? _explicitFingerprint.trim()
          : SecurityService.generateDeviceFingerprint();

  String get _deviceSecret {
    final explicit = _explicitDeviceSecret?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return SessionService.current?.getOrCreateDeviceSecret() ?? '';
  }

  /// Sends an image of a Yellow Form to the GynoCamp server for Gemini extraction.
  ///
  /// [pageNumber]:
  /// - 1: Front page (Demographics, Obstetric History, Section B Visit Reasons, Section C Consent)
  /// - 2: Back page (Station 1 Vitals, Station 2 POP Exam & Staging, Station 3-4 Diagnoses, Station 5 Medications, Station 6 Referral)
  /// - 0: Auto-detect or full form
  Future<OcrScanResultModel> extractFromImage(
    XFile imageFile, {
    int pageNumber = 0,
  }) async {
    final rawBytes = await imageFile.readAsBytes();
    if (rawBytes.isEmpty) {
      throw const GeminiOcrException('Image file is empty or unreadable.');
    }

    final secret = _deviceSecret;
    if (secret.isEmpty) {
      throw const GeminiOcrException('Device credentials are unavailable for cloud OCR.');
    }

    // Prepare & optimize image (<= 1600px max dimension, quality 85% JPEG)
    final prepared = await _prepareImage(rawBytes);

    final uri = Uri.parse('$_baseUrl/api/ocr/extract');
    final headers = {
      'Content-Type': 'application/json',
      'X-Device-Fingerprint': _deviceFingerprint,
      'X-Device-Secret': secret,
    };
    final body = jsonEncode({
      'imageBase64': prepared.base64,
      'mimeType': prepared.mimeType,
      'pageNumber': pageNumber,
    });

    if (kDebugMode) {
      debugPrint('[GeminiOCR] Sending image to server (${rawBytes.length ~/ 1024} KB raw, Page: $pageNumber)...');
    }

    http.Response response;
    try {
      response = await _client.post(uri, headers: headers, body: body).timeout(requestTimeout);
    } on TimeoutException {
      throw const GeminiOcrException('Cloud OCR timed out. Check the server connection and try again.');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GeminiOCR] Network error: ${e.runtimeType}');
      }
      throw const GeminiOcrException('Cannot reach the GynoCamp server for cloud OCR.');
    }

    if (response.statusCode != 200) {
      var message = 'Cloud OCR unavailable (status ${response.statusCode}).';
      try {
        final err = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final serverMessage = err['error'];
        if (serverMessage is String && serverMessage.isNotEmpty) message = serverMessage;
      } catch (_) {}
      throw GeminiOcrException(message, statusCode: response.statusCode);
    }

    try {
      final envelope = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final extractedText = envelope['text'] as String?;
      if (extractedText == null || extractedText.trim().isEmpty) {
        throw const GeminiOcrException('Cloud OCR returned no result.');
      }
      final parsedData = jsonDecode(extractedText) as Map<String, dynamic>;

      return _mapJsonToScanResult(
        parsedData: parsedData,
        imagePath: imageFile.path,
        fallbackPageNumber: pageNumber,
      );
    } catch (e) {
      if (e is GeminiOcrException) rethrow;
      throw GeminiOcrException('Failed to parse OCR output: $e');
    }
  }

  /// Scales image down if larger than 1600px to ensure fast mobile upload.
  Future<({String base64, String mimeType})> _prepareImage(Uint8List bytes) async {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null && (decoded.width > 1600 || decoded.height > 1600)) {
        final resized = img.copyResize(
          decoded,
          width: decoded.width > decoded.height ? 1600 : null,
          height: decoded.height >= decoded.width ? 1600 : null,
        );
        final compressedJpg = img.encodeJpg(resized, quality: 85);
        return (base64: base64Encode(compressedJpg), mimeType: 'image/jpeg');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GeminiOCR] Image resize skipped: $e');
      }
    }
    final isPng = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
    return (base64: base64Encode(bytes), mimeType: isPng ? 'image/png' : 'image/jpeg');
  }

  /// Maps structured JSON returned by Gemini to [OcrScanResultModel].
  OcrScanResultModel _mapJsonToScanResult({
    required Map<String, dynamic> parsedData,
    required String imagePath,
    required int fallbackPageNumber,
  }) {
    final int detectedPage = (parsedData['pageNumber'] as num?)?.toInt() ?? fallbackPageNumber;

    final rawDemo = (parsedData['demographics'] as Map<String, dynamic>?) ?? {};
    final rawObs = (parsedData['obstetrics'] as Map<String, dynamic>?) ?? {};
    final rawVitals = (parsedData['vitals'] as Map<String, dynamic>?) ?? {};
    final rawPop = (parsedData['popStaging'] as Map<String, dynamic>?) ?? {};
    final rawDiagnoses = (parsedData['diagnoses'] as List<dynamic>?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() ?? <String>[];
    final rawMeds = (parsedData['medications'] as List<dynamic>?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() ?? <String>[];
    final rawCounseling = (parsedData['counseling'] as List<dynamic>?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() ?? <String>[];
    // Station 5 extra items (Ring Pessary & Surgery)
    // NOTE: Pessary is a device fitting, NOT a dispensed medication.
    // We do NOT inject it into rawMeds. It stays in ringPessary/pessaryType/ringPessarySize.
    final ringPessary = parsedData['ringPessary'] == true || rawPop['ringPessary'] == true;
    final ringPessarySize = (parsedData['ringPessarySize'] as num?)?.toInt() ?? (rawPop['ringPessarySize'] as num?)?.toInt();
    // Read pessaryType from Gemini (ring / ring with support / ring with knob)
    final rawPessaryType = parsedData['pessaryType']?.toString().trim();
    final String? pessaryType = (rawPessaryType != null && rawPessaryType.isNotEmpty && rawPessaryType.toLowerCase() != 'null')
        ? rawPessaryType.toLowerCase()
        : null;

    final surgicalRef = parsedData['surgicalReferral']?.toString().trim();
    final followUp = parsedData['followUpDestination']?.toString().trim();
    final rawExaminingDoctor = parsedData['examiningDoctor']?.toString().trim();
    final String? examiningDoctor = (rawExaminingDoctor != null && rawExaminingDoctor.isNotEmpty && rawExaminingDoctor.toLowerCase() != 'null')
        ? (rawExaminingDoctor.toLowerCase().startsWith('dr') ? rawExaminingDoctor : 'Dr. $rawExaminingDoctor')
        : null;
    final List<String> rawAttendingDoctors = (parsedData['attendingDoctors'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty && e.toLowerCase() != 'null')
            .map((e) => e.toLowerCase().startsWith('dr') ? e : 'Dr. $e')
            .toSet()
            .toList()
            .cast<String>() ??
        <String>[];
    if (examiningDoctor != null &&
        examiningDoctor.isNotEmpty &&
        !rawAttendingDoctors.contains(examiningDoctor)) {
      rawAttendingDoctors.insert(0, examiningDoctor);
    }
    final rawExaminingNurse = parsedData['examiningNurse']?.toString().trim();
    final String? examiningNurse = (rawExaminingNurse != null &&
            rawExaminingNurse.isNotEmpty &&
            rawExaminingNurse.toLowerCase() != 'null')
        ? NurseProfile.stripPrefixes(rawExaminingNurse)
        : null;
    final List<String> rawAttendingNurses = (parsedData['attendingNurses'] as List?)
            ?.map((e) => NurseProfile.stripPrefixes(e.toString().trim()))
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
            .cast<String>() ??
        <String>[];
    if (examiningNurse != null &&
        examiningNurse.isNotEmpty &&
        !rawAttendingNurses.contains(examiningNurse)) {
      rawAttendingNurses.insert(0, examiningNurse);
    }
    final rawSummary = parsedData['rawSummary']?.toString().trim() ?? '';
    final rawTreatmentLevel = parsedData['treatmentLevel']?.toString().toLowerCase().trim() ??
        parsedData['levelOfTreatment']?.toString().toLowerCase().trim() ??
        parsedData['consultation']?.toString().toLowerCase().trim();
    String? treatmentLevel;
    if (rawTreatmentLevel != null && rawTreatmentLevel.isNotEmpty) {
      if (rawTreatmentLevel.contains('counsel') || rawTreatmentLevel.contains('council') || rawTreatmentLevel.contains('काउन्सिलिङ')) {
        treatmentLevel = 'counseling';
      } else if (rawTreatmentLevel.contains('gyno') || rawTreatmentLevel.contains('full') || rawTreatmentLevel.contains('गाइनो') || rawTreatmentLevel.contains('पूर्ण')) {
        treatmentLevel = 'gyno_checkup';
      }
    }

    // Normalize Province (case-insensitive)
    String normProvince(String? raw) {
      if (raw == null || raw.trim().isEmpty) return 'Bagmati';
      final clean = raw.trim().toLowerCase();
      for (final p in ClinicalConstants.nepalProvinces) {
        if (p.toLowerCase() == clean) return p;
      }
      return 'Bagmati';
    }

    // Normalize District (case-insensitive against NepalGeodata)
    String normDistrict(String? raw, String prov) {
      if (raw == null || raw.trim().isEmpty) return '';
      final clean = raw.trim().toLowerCase();
      final provDistricts = NepalGeodata.districtsFor(prov);
      for (final d in provDistricts) {
        if (d.toLowerCase() == clean) return d;
      }
      for (final d in provDistricts) {
        if (clean.contains(d.toLowerCase()) || d.toLowerCase().contains(clean)) return d;
      }
      // Search across all districts if province was misidentified
      for (final d in NepalGeodata.allDistricts) {
        if (d.toLowerCase() == clean) return d;
      }
      for (final d in NepalGeodata.allDistricts) {
        if (clean.contains(d.toLowerCase()) || d.toLowerCase().contains(clean)) return d;
      }
      return raw.trim();
    }

    // Normalize Reasons for Visit (to canonical keys)
    List<String> normReasons(dynamic raw) {
      if (raw is! List) return <String>[];
      final result = <String>[];
      for (final item in raw) {
        final str = item.toString().toLowerCase().trim();
        if (str.isEmpty) continue;
        if (str.contains('hanging') || str.contains('prolapse') || str.contains('पाठेघर खस्ने') || str.contains('something hanging out')) {
          if (!result.contains('something hanging out')) result.add('something hanging out');
        } else if (str.contains('discharge') || str.contains('itching') || str.contains('स्राव') || str.contains('चिलाउने') || str.contains('खटिरा') || str.contains('discharge and or itching')) {
          if (!result.contains('discharge and or itching')) result.add('discharge and or itching');
        } else if (str.contains('urine') || str.contains('पिसाब') || str.contains('incontinence') || str.contains('problems passing urine')) {
          if (!result.contains('problems passing urine')) result.add('problems passing urine');
        } else if (str.contains('stool') || str.contains('दिसा') || str.contains('problems passing stool')) {
          if (!result.contains('problems passing stool')) result.add('problems passing stool');
        } else if (str.contains('menstrual') || str.contains('महिनावारी') || str.contains('menstrual problem')) {
          if (!result.contains('menstrual problem')) result.add('menstrual problem');
        } else if (str.contains('infertility') || str.contains('बाँझोपन')) {
          if (!result.contains('infertility')) result.add('infertility');
        } else if (str.contains('pain') || str.contains('दुखाई') || str.contains('तल्लो पेट')) {
          if (!result.contains('pain')) result.add('pain');
        } else if (str.contains('checkup') || str.contains('जाँच') || str.contains('check') || str.contains('general checkup')) {
          if (!result.contains('checkup')) result.add('checkup');
        } else if (ClinicalConstants.visitReasonOptions.containsKey(str)) {
          if (!result.contains(str)) result.add(str);
        } else {
          result.add(item.toString().trim());
        }
      }
      return result;
    }

    // Normalize Surgery Done and Surgery Route
    final rawSurgeryDone = parsedData['surgeryDone'] == true ||
        rawPop['surgeryDone'] == true ||
        (parsedData['surgeryType']?.toString().trim().isNotEmpty == true) ||
        (rawPop['surgeryType']?.toString().trim().isNotEmpty == true);
    final rawSurgeryType = parsedData['surgeryType']?.toString().trim() ?? rawPop['surgeryType']?.toString().trim();
    String? normSurgeryType;
    if (rawSurgeryType != null && rawSurgeryType.isNotEmpty && rawSurgeryType.toLowerCase() != 'none') {
      final sLower = rawSurgeryType.toLowerCase();
      if (sLower.contains('laparo') || sLower.contains('दूरबिन') || sLower.contains('दुरबिन')) {
        normSurgeryType = 'Laparoscopy';
      } else if (sLower.contains('vagin') || sLower.contains('योनी') || sLower.contains('vaginal route')) {
        normSurgeryType = 'Vaginal route';
      } else if (sLower.contains('open') || sLower.contains('खुला') || sLower.contains('open surgery')) {
        normSurgeryType = 'Open surgery';
      } else {
        normSurgeryType = rawSurgeryType;
      }
    }

    final normProv = normProvince(rawDemo['province']?.toString());
    final normDist = normDistrict(rawDemo['district']?.toString(), normProv);
    final normalizedReasons = normReasons(rawDemo['reasonsForVisit']);

    // Normalize demographics (strictly Yellow Form Page 1 fields — NO caste/education/occupation)
    final demographics = <String, dynamic>{
      'firstName': rawDemo['firstName']?.toString().trim() ?? '',
      'surname': rawDemo['surname']?.toString().trim() ?? '',
      'age': (rawDemo['age'] as num?)?.toInt(),
      'maritalStatus': rawDemo['maritalStatus']?.toString().toLowerCase().trim() ?? 'married',
      'relativeName': rawDemo['relativeName']?.toString().trim() ?? (rawDemo['spouseOrFatherName']?.toString().trim() ?? ''),
      'relativeType': () {
        // Read from Gemini data first (ticked/circled label on form)
        final raw = rawDemo['relationType']?.toString().trim();
        if (raw != null && raw.isNotEmpty && raw.toLowerCase() != 'null') {
          if (raw.toLowerCase().contains('father') || raw.contains('बुबा')) return 'Father';
          if (raw.toLowerCase().contains('husband') || raw.contains('श्रीमान्')) return 'Husband';
          return raw;
        }
        // Fallback: guess from age only if no Gemini data
        final age = (rawDemo['age'] as num?)?.toInt();
        return (age != null && age < 20) ? 'Father' : 'Husband';
      }(),
      'relativeSurname': rawDemo['relativeSurname']?.toString().trim() ?? '',
      'mobile': rawDemo['mobile']?.toString().trim() ?? '',
      'maritalAge': (rawDemo['maritalAge'] as num?)?.toInt() ?? (rawObs['ageAtMarriage'] as num?)?.toInt(),
      'contactPerson': rawDemo['contactPerson']?.toString().trim() ?? '',
      'contactMobile': rawDemo['contactMobile']?.toString().trim() ?? '',
      'province': normProv,
      'district': normDist,
      'municipality': rawDemo['municipality']?.toString().trim() ?? '',
      'ward': rawDemo['ward']?.toString().trim() ?? '',
      'reasonsForVisit': normalizedReasons,
      'consentTreatment': rawDemo['consentTreatment'] ?? true,
      'consentStoreMedicalInfo': rawDemo['consentStoreMedicalInfo'] ?? true,
      'patientId': (rawDemo['patientId'] ?? rawDemo['patientTokenId'] ?? parsedData['patientId'] ?? parsedData['patientTokenId'] ?? '').toString().trim(),
      'patientTokenId': (rawDemo['patientId'] ?? rawDemo['patientTokenId'] ?? parsedData['patientId'] ?? parsedData['patientTokenId'] ?? '').toString().trim(),
    };

    // Normalize obstetrics (strictly Yellow Form Station 1 fields — NO gravida/deliveries-years-ago)
    final obstetrics = <String, dynamic>{
      'deliveries': (rawObs['deliveries'] as num?)?.toInt() ?? (rawObs['para'] as num?)?.toInt(),
      'livingChildren': (rawObs['livingChildren'] as num?)?.toInt(),
      'abortions': (rawObs['abortions'] as num?)?.toInt(),
      'complaintsDuration': rawObs['complaintsDuration']?.toString().trim() ?? '',
      'clinicalComplaints': (rawObs['clinicalComplaints'] as List<dynamic>?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() ?? <String>[],
      'complaintDetails': () {
        // Gemini returns complaintDetails as a List of {complaint, subOptions, duration, remarks}.
        // The UI/viewmodel/repository expects a Map keyed by complaint name.
        final rawDetails = rawObs['complaintDetails'];
        final result = <String, dynamic>{};
        if (rawDetails is List) {
          for (final item in rawDetails) {
            if (item is Map<String, dynamic>) {
              final key = item['complaint']?.toString().trim();
              if (key != null && key.isNotEmpty) {
                final subOptions = item['subOptions'];
                result[key] = <String, dynamic>{
                  'duration': item['duration']?.toString() ?? '',
                  'remarks': item['remarks']?.toString() ?? '',
                  'subOption': subOptions is List ? subOptions.join(', ') : (subOptions?.toString() ?? ''),
                };
              }
            }
          }
        } else if (rawDetails is Map) {
          // Already in the expected format
          result.addAll(Map<String, dynamic>.from(rawDetails));
        }
        return result;
      }(),
    };

    // Normalize vitals (strictly Yellow Form Station 3 fields — NO respiratory rate/temp/weight/height)
    final vitals = <String, dynamic>{
      'systolicBp': (rawVitals['systolicBp'] as num?)?.toInt(),
      'diastolicBp': (rawVitals['diastolicBp'] as num?)?.toInt(),
      'pulseRate': (rawVitals['pulseRate'] as num?)?.toInt() ?? (rawVitals['pulse'] as num?)?.toInt(),
      'pulse': (rawVitals['pulseRate'] as num?)?.toInt() ?? (rawVitals['pulse'] as num?)?.toInt(),
      'spo2': (rawVitals['spo2'] as num?)?.toInt(),
      'bloodGlucose': (rawVitals['bloodGlucose'] as num?)?.toInt() ?? (rawVitals['glucose'] as num?)?.toInt() ?? (rawVitals['bloodSugar'] as num?)?.toInt(),
      'glucose': (rawVitals['bloodGlucose'] as num?)?.toInt() ?? (rawVitals['glucose'] as num?)?.toInt() ?? (rawVitals['bloodSugar'] as num?)?.toInt(),
      'urineTest': rawVitals['urineTest']?.toString().trim() ?? 'normal',
      'pregnancyTest': () {
        final raw = rawVitals['pregnancyTest']?.toString().trim().toLowerCase() ?? '';
        if (raw.contains('pos')) return 'pos';
        if (raw.contains('not') || raw.contains('done')) return 'not_done';
        return 'neg';
      }(),
      'ecg': rawVitals['ecg']?.toString().trim() ?? '',
      'ecgNotes': rawVitals['ecgNotes']?.toString().trim() ?? rawVitals['ecg']?.toString().trim() ?? '',
    };

    // Normalize POP Staging (strictly Yellow Form Station 2 fields)
    // Preserve null for undetected stages — do NOT default to 0
    final int? ant = (rawPop['anteriorStage'] as num?)?.toInt();
    final int? mid = (rawPop['middleStage'] as num?)?.toInt();
    final int? post = (rawPop['posteriorStage'] as num?)?.toInt();
    final int? popStageNum = (rawPop['highestPopStage'] as num?)?.toInt() ??
        (rawPop['stage'] as num?)?.toInt() ??
        (ant != null || mid != null || post != null
            ? [ant ?? 0, mid ?? 0, post ?? 0].reduce((a, b) => a > b ? a : b)
            : null);

    final popStaging = <String, dynamic>{
      'anteriorStage': ant,
      'middleStage': mid,
      'posteriorStage': post,
      'highestPopStage': popStageNum,
      'stage': popStageNum,
      'uterusInside': rawPop['uterusInside'],  // preserve null if undetected
      'pelvicFloorTone': rawPop['pelvicFloorTone']?.toString().toLowerCase().trim(),  // null if undetected
      'vulvaRemarks': rawPop['vulvaRemarks']?.toString().trim(),
      'cervixRemarks': rawPop['cervixRemarks']?.toString().trim() ?? (rawPop['cervixDescription']?.toString().trim()),
      'vaginaRemarks': rawPop['vaginaRemarks']?.toString().trim(),
      'uterusRemarks': rawPop['uterusRemarks']?.toString().trim(),
      'ringPessary': ringPessary,
      'ringPessarySize': ringPessarySize,
      'surgeryDone': rawSurgeryDone,
      'surgeryType': normSurgeryType,
    };

    // Compute field confidences
    final confidences = <String, double>{};
    void markConf(String key, dynamic value) {
      if (value != null) {
        if (value is String && value.isNotEmpty) {
          confidences[key] = 0.96;
        } else if (value is num) {
          confidences[key] = 0.98;
        } else if (value is List && value.isNotEmpty) {
          confidences[key] = 0.95;
        } else if (value is bool) {
          confidences[key] = 0.99;
        }
      }
    }

    demographics.forEach(markConf);
    obstetrics.forEach(markConf);
    vitals.forEach(markConf);
    popStaging.forEach(markConf);
    if (rawDiagnoses.isNotEmpty) confidences['diagnoses'] = 0.95;
    if (rawMeds.isNotEmpty) confidences['medications'] = 0.95;
    if (surgicalRef != null && surgicalRef.isNotEmpty && surgicalRef != 'None') confidences['surgicalReferral'] = 0.95;
    if (followUp != null && followUp.isNotEmpty) confidences['followUpDestination'] = 0.95;
    if (treatmentLevel != null) confidences['treatmentLevel'] = 0.95;

    final overallConf = confidences.isNotEmpty ? 0.96 : 0.50;

    // Construct readable rawText for clinical inspection & verification
    final buffer = StringBuffer();
    buffer.writeln('[GEMINI FLASH CLOUD OCR]');
    buffer.writeln('Page: $detectedPage');
    if (treatmentLevel != null) {
      buffer.writeln('Consultation: ${(treatmentLevel == "counseling" || treatmentLevel == "council_level") ? "Counseling" : "Gynocheckup"}');
    }
    if (demographics['firstName'] != '' || demographics['surname'] != '') {
      buffer.writeln('Patient Name: ${demographics['firstName']} ${demographics['surname']}');
      buffer.writeln('Age: ${demographics['age'] ?? 'N/A'}, Marital: ${demographics['maritalStatus']}, Relative: ${demographics['relativeName']}');
      buffer.writeln('Location: Ward ${demographics['ward']}, ${demographics['municipality']}, ${demographics['district']}, ${demographics['province']}');
      buffer.writeln('Mobile: ${demographics['mobile']}, Contact: ${demographics['contactPerson']} (${demographics['contactMobile']})');
      final reasons = demographics['reasonsForVisit'] as List?;
      if (reasons != null && reasons.isNotEmpty) {
        buffer.writeln('Reasons for Visit: ${reasons.join(', ')}');
      }
    }
    if (obstetrics['deliveries'] != null) {
      buffer.writeln('Obstetrics: Deliveries(P) ${obstetrics['deliveries']}, Living ${obstetrics['livingChildren']}, Abortions ${obstetrics['abortions']}');
      if (obstetrics['complaintsDuration'] != '') {
        buffer.writeln('Complaints Duration: ${obstetrics['complaintsDuration']}');
      }
      final complaints = obstetrics['clinicalComplaints'] as List?;
      if (complaints != null && complaints.isNotEmpty) {
        buffer.writeln('Clinical Complaints: ${complaints.join(', ')}');
      }
    }
    if (vitals['systolicBp'] != null) {
      buffer.writeln('Vitals: BP ${vitals['systolicBp']}/${vitals['diastolicBp']} mmHg, Pulse ${vitals['pulseRate']} bpm, SpO2 ${vitals['spo2']}%, Blood Glucose ${vitals['bloodGlucose']} mg/dL');
      buffer.writeln('Labs: Urine: ${vitals['urineTest']}, UPT: ${vitals['pregnancyTest']}');
    }
    if (popStaging['highestPopStage'] != null) {
      buffer.writeln('POP Staging: Highest Stage ${popStaging['highestPopStage']} (Anterior: ${popStaging['anteriorStage']}, Middle: ${popStaging['middleStage']}, Posterior: ${popStaging['posteriorStage']})');
      buffer.writeln('POP Exam: Uterus Inside: ${popStaging['uterusInside'] == true ? "Yes" : "No"}, Pelvic Floor Muscle: ${popStaging['pelvicFloorTone']}');
    }
    if (rawDiagnoses.isNotEmpty) {
      buffer.writeln('Diagnoses: ${rawDiagnoses.join(', ')}');
    }
    if (rawMeds.isNotEmpty) {
      buffer.writeln('Prescriptions: ${rawMeds.join(', ')}');
    }
    if (surgicalRef != null && surgicalRef.isNotEmpty && surgicalRef != 'None') {
      buffer.writeln('Surgical Referral: $surgicalRef');
    }
    if (followUp != null && followUp.isNotEmpty) {
      buffer.writeln('Follow-up Destination: $followUp');
    }
    if (examiningDoctor != null && examiningDoctor.isNotEmpty) {
      buffer.writeln('Examining Doctor: $examiningDoctor');
    }
    if (examiningNurse != null && examiningNurse.isNotEmpty) {
      buffer.writeln('Examining Nurse: $examiningNurse');
    }
    if (rawSummary.isNotEmpty) {
      buffer.writeln('\n--- DETECTED TEXT SUMMARY ---\n$rawSummary');
    }

    // Extract station dates from Gemini response
    final String? intakeDate = _extractDate(parsedData['intakeDate']);
    final String? examDate = _extractDate(parsedData['examDate']);
    final String? labTestDate = _extractDate(parsedData['labTestDate']);
    final String? conclusionDate = _extractDate(parsedData['conclusionDate']);
    final String? treatmentDate = _extractDate(parsedData['treatmentDate']);
    final String? outtakeDate = _extractDate(parsedData['outtakeDate']);

    // Extract clinical notes from Station 6
    final rawClinicalNotes = parsedData['clinicalNotes']?.toString().trim();
    final String? clinicalNotes = (rawClinicalNotes != null && rawClinicalNotes.isNotEmpty && rawClinicalNotes.toLowerCase() != 'null')
        ? rawClinicalNotes
        : null;

    return OcrScanResultModel(
      pageNumber: detectedPage,
      imagePath: imagePath,
      isDualPage: detectedPage == 0,
      isSimulated: false,
      ocrEngine: AppConstants.ocrEngineGeminiFlash,
      demographics: demographics,
      obstetrics: obstetrics,
      vitals: vitals,
      popStaging: popStaging,
      diagnoses: rawDiagnoses,
      counseling: rawCounseling,
      medications: rawMeds,
      surgicalReferral: (surgicalRef?.isNotEmpty == true && surgicalRef != 'None') ? surgicalRef : null,
      followUpDestination: (followUp?.isNotEmpty == true) ? followUp : null,
      surgeryDone: rawSurgeryDone,
      surgeryType: normSurgeryType,
      ringPessary: ringPessary,
      pessaryType: pessaryType,
      ringPessarySize: ringPessarySize,
      examiningDoctor: examiningDoctor,
      attendingDoctors: rawAttendingDoctors.isNotEmpty
          ? rawAttendingDoctors
          : (examiningDoctor != null ? [examiningDoctor] : const []),
      examiningNurse: examiningNurse,
      attendingNurses: rawAttendingNurses,
      treatmentLevel: treatmentLevel,
      clinicalNotes: clinicalNotes,
      intakeDate: intakeDate,
      examDate: examDate,
      labTestDate: labTestDate,
      conclusionDate: conclusionDate,
      treatmentDate: treatmentDate,
      outtakeDate: outtakeDate,
      fieldConfidences: confidences,
      overallConfidence: overallConf,
      rawText: buffer.toString(),
      scannedAt: DateTime.now(),
    );
  }

  /// Extract and validate a date string from Gemini JSON.
  /// Returns YYYY-MM-DD format or null.
  static String? _extractDate(dynamic raw) {
    if (raw == null) return null;
    final str = raw.toString().trim();
    if (str.isEmpty || str.toLowerCase() == 'null') return null;
    // Accept YYYY-MM-DD format
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(str)) return str;
    // Try to parse other formats
    try {
      final dt = DateTime.parse(str);
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return str; // Return raw if we can't parse, let the UI handle it
    }
  }

  void dispose() {
    _client.close();
  }
}
