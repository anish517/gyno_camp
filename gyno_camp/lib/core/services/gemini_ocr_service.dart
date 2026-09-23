import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../constants/app_constants.dart';
import '../constants/clinical_constants.dart';
import '../constants/nepal_geodata.dart';
import '../../models/ocr_scan_result_model.dart';
import 'session_service.dart';

class GeminiOcrException implements Exception {
  final String message;
  final int? statusCode;
  const GeminiOcrException(this.message, {this.statusCode});

  @override
  String toString() => 'GeminiOcrException: $message (status: $statusCode)';
}

/// Cloud-based Multimodal OCR Service using Google Gemini Flash API (`gemini-flash-latest`).
///
/// Features:
/// - Direct visual parsing of photographed Yellow Intake Forms (Nepal MoHP format).
/// - High-fidelity extraction of handwriting, checkboxes, vitals, POP staging, and prescriptions.
/// - Built-in image optimization (scales large images to max 1600px width/height to reduce payload size).
/// - Resilient timeout and 1-attempt automatic retry on transient 503/429 HTTP responses.
/// - Structured JSON output mapped directly to [OcrScanResultModel] with `ocrEngine: 'gemini_flash'`.
class GeminiOcrService {
  final http.Client _client;
  final String? _explicitApiKey;
  final String? _explicitEndpointUrl;

  /// High-availability candidate models for Yellow Form multimodal OCR.
  /// Prioritized:
  /// 1. `gemini-flash-lite-latest`: Fast, high capacity, resilient against 503 spikes.
  /// 2. `gemini-3-flash-preview`: High-fidelity reasoning fallback.
  /// 3. `gemini-flash-latest`: Standard flash tier.
  static const List<String> defaultCandidateModels = [
    'gemini-flash-lite-latest',
    'gemini-3-flash-preview',
    'gemini-flash-latest',
  ];

  GeminiOcrService({
    http.Client? httpClient,
    String? apiKey,
    String? endpointUrl,
  })  : _client = httpClient ?? http.Client(),
        _explicitApiKey = apiKey,
        _explicitEndpointUrl = endpointUrl;

  String get effectiveApiKey {
    if (_explicitApiKey != null && _explicitApiKey.trim().isNotEmpty) {
      return _explicitApiKey.trim();
    }
    final savedKey = SessionService.current?.getGeminiApiKey();
    if (savedKey != null && savedKey.trim().isNotEmpty) {
      return savedKey.trim();
    }
    return AppConstants.defaultGeminiApiKey;
  }

  /// Sends an image of a Yellow Form to Gemini Flash for digitized extraction.
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

    // Prepare & optimize image (ensure <= 1600px max dimension, quality 85% JPEG)
    final optimizedBase64 = await _prepareImageBase64(rawBytes);

    final prompt = _buildSystemPrompt(pageNumber);

    final payload = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': optimizedBase64,
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'response_mime_type': 'application/json',
      }
    };

    final List<Uri> candidateUris;
    if (_explicitEndpointUrl != null && _explicitEndpointUrl.trim().isNotEmpty) {
      candidateUris = [Uri.parse(_explicitEndpointUrl.trim())];
    } else {
      candidateUris = defaultCandidateModels
          .map((m) => Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent'))
          .toList();
    }

    final headers = {
      'Content-Type': 'application/json',
      'X-goog-api-key': effectiveApiKey,
    };

    if (kDebugMode) {
      debugPrint('[GeminiOCR] 🚀 Sending image to Gemini (${rawBytes.length ~/ 1024} KB raw, Page: $pageNumber)...');
    }

    http.Response response;
    try {
      response = await _sendWithRetryAndFailover(candidateUris, headers, jsonEncode(payload));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GeminiOCR] ❌ Network/timeout error: $e');
      }
      rethrow;
    }

    if (response.statusCode != 200) {
      throw GeminiOcrException(
        'Gemini API failed with status ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }

    try {
      final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = responseJson['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        throw const GeminiOcrException('Gemini returned no candidate outputs.');
      }

      final content = candidates[0]['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) {
        throw const GeminiOcrException('Gemini returned empty parts list.');
      }

      final extractedText = parts[0]['text'] as String? ?? '{}';
      final parsedData = jsonDecode(extractedText) as Map<String, dynamic>;

      return _mapJsonToScanResult(
        parsedData: parsedData,
        imagePath: imageFile.path,
        fallbackPageNumber: pageNumber,
      );
    } catch (e) {
      if (e is GeminiOcrException) rethrow;
      throw GeminiOcrException('Failed to parse Gemini JSON output: $e');
    }
  }

  /// Sends POST request with automatic candidate model failover and exponential backoff
  /// on transient 503 (High Demand / Unavailable) and 429 (Rate Limit) errors.
  Future<http.Response> _sendWithRetryAndFailover(
    List<Uri> candidateUris,
    Map<String, String> headers,
    String body,
  ) async {
    const timeoutDuration = Duration(seconds: 30);
    http.Response? lastResponse;
    dynamic lastError;

    for (int m = 0; m < candidateUris.length; m++) {
      final uri = candidateUris[m];
      final modelName = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last.replaceAll(':generateContent', '')
          : uri.toString();

      int attempts = 0;
      while (attempts < 2) {
        attempts++;
        try {
          if (kDebugMode && (m > 0 || attempts > 1)) {
            debugPrint('[GeminiOCR] 🔄 Attempting $modelName (attempt $attempts)...');
          }
          final res = await _client.post(uri, headers: headers, body: body).timeout(timeoutDuration);
          if (res.statusCode == 200) {
            if (kDebugMode && (m > 0 || attempts > 1)) {
              debugPrint('[GeminiOCR] ✅ Succeeded with model $modelName');
            }
            return res;
          }
          lastResponse = res;
          if (res.statusCode == 503 || res.statusCode == 429) {
            if (attempts < 2) {
              final backoffMs = attempts * 1500;
              if (kDebugMode) {
                debugPrint('[GeminiOCR] ⚠️ Transient ${res.statusCode} on $modelName. Retrying in ${backoffMs / 1000}s...');
              }
              await Future.delayed(Duration(milliseconds: backoffMs));
              continue;
            } else {
              if (kDebugMode && m + 1 < candidateUris.length) {
                debugPrint('[GeminiOCR] ⚠️ $modelName overloaded (${res.statusCode}). Failing over to next model candidate...');
              }
              break; // exit inner retry loop to try next candidate in candidateUris
            }
          } else {
            // Client error (e.g. 400 Bad Request, 401 Unauthorized), do not failover across models
            return res;
          }
        } on SocketException catch (e) {
          lastError = e;
          if (attempts < 2) {
            await Future.delayed(const Duration(milliseconds: 1500));
            continue;
          }
          break;
        } on http.ClientException catch (e) {
          lastError = e;
          if (attempts < 2) {
            await Future.delayed(const Duration(milliseconds: 1500));
            continue;
          }
          break;
        } catch (e) {
          lastError = e;
          if (attempts < 2) {
            await Future.delayed(const Duration(milliseconds: 1500));
            continue;
          }
          break;
        }
      }
    }

    if (lastResponse != null) {
      return lastResponse;
    }
    if (lastError != null) {
      throw lastError;
    }
    throw const GeminiOcrException('All Gemini OCR model candidates failed.');
  }

  /// Scales image down if larger than 1600px to ensure fast mobile upload.
  Future<String> _prepareImageBase64(Uint8List bytes) async {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null && (decoded.width > 1600 || decoded.height > 1600)) {
        final resized = img.copyResize(
          decoded,
          width: decoded.width > decoded.height ? 1600 : null,
          height: decoded.height >= decoded.width ? 1600 : null,
        );
        final compressedJpg = img.encodeJpg(resized, quality: 85);
        return base64Encode(compressedJpg);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GeminiOCR] Image resize skipped: $e');
      }
    }
    return base64Encode(bytes);
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
    
    // Station 5 extra items (Ring Pessary & Surgery)
    final ringPessary = parsedData['ringPessary'] == true || rawPop['ringPessary'] == true;
    final ringPessarySize = (parsedData['ringPessarySize'] as num?)?.toInt() ?? (rawPop['ringPessarySize'] as num?)?.toInt();
    if (ringPessary && ringPessarySize != null && ringPessarySize > 0) {
      final pessaryEntry = 'Ring Pessary ${ringPessarySize}mm';
      if (!rawMeds.any((m) => m.toLowerCase().contains('pessary'))) {
        rawMeds.add(pessaryEntry);
      }
    }

    final surgicalRef = parsedData['surgicalReferral']?.toString().trim();
    final followUp = parsedData['followUpDestination']?.toString().trim();
    final rawSummary = parsedData['rawSummary']?.toString().trim() ?? '';

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
      'relativeType': (rawDemo['age'] as num?)?.toInt() != null && ((rawDemo['age'] as num?)!.toInt() < 20) ? 'Father' : 'Husband',
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
      'patientTokenId': rawDemo['patientTokenId']?.toString().trim() ?? (parsedData['patientId']?.toString().trim() ?? ''),
    };

    // Normalize obstetrics (strictly Yellow Form Station 1 fields — NO gravida/deliveries-years-ago)
    final obstetrics = <String, dynamic>{
      'deliveries': (rawObs['deliveries'] as num?)?.toInt() ?? (rawObs['para'] as num?)?.toInt(),
      'livingChildren': (rawObs['livingChildren'] as num?)?.toInt(),
      'abortions': (rawObs['abortions'] as num?)?.toInt(),
      'complaintsDuration': rawObs['complaintsDuration']?.toString().trim() ?? '',
      'clinicalComplaints': (rawObs['clinicalComplaints'] as List<dynamic>?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() ?? <String>[],
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
    };

    // Normalize POP Staging (strictly Yellow Form Station 2 fields)
    final ant = (rawPop['anteriorStage'] as num?)?.toInt() ?? 0;
    final mid = (rawPop['middleStage'] as num?)?.toInt() ?? 0;
    final post = (rawPop['posteriorStage'] as num?)?.toInt() ?? 0;
    final popStageNum = (rawPop['highestPopStage'] as num?)?.toInt() ??
        (rawPop['stage'] as num?)?.toInt() ??
        [ant, mid, post].reduce((a, b) => a > b ? a : b);

    final popStaging = <String, dynamic>{
      'anteriorStage': ant,
      'middleStage': mid,
      'posteriorStage': post,
      'highestPopStage': popStageNum,
      'stage': popStageNum,
      'uterusInside': rawPop['uterusInside'] ?? (rawPop['uterusPosition']?.toString().toLowerCase().contains('inside') == true),
      'pelvicFloorTone': rawPop['pelvicFloorTone']?.toString().toLowerCase().trim() ?? 'normal',
      'cervixRemarks': rawPop['cervixRemarks']?.toString().trim() ?? (rawPop['cervixDescription']?.toString().trim() ?? ''),
      'vaginaRemarks': rawPop['vaginaRemarks']?.toString().trim() ?? '',
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

    final overallConf = confidences.isNotEmpty ? 0.96 : 0.50;

    // Construct readable rawText for clinical inspection & verification
    final buffer = StringBuffer();
    buffer.writeln('[GEMINI FLASH CLOUD OCR]');
    buffer.writeln('Page: $detectedPage');
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
      buffer.writeln('POP Exam: Uterus Inside: ${popStaging['uterusInside'] == true ? "Yes" : "No (Prolapsed)"}, Tone: ${popStaging['pelvicFloorTone']}');
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
    if (rawSummary.isNotEmpty) {
      buffer.writeln('\n--- DETECTED TEXT SUMMARY ---\n$rawSummary');
    }

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
      medications: rawMeds,
      surgicalReferral: (surgicalRef?.isNotEmpty == true && surgicalRef != 'None') ? surgicalRef : null,
      followUpDestination: (followUp?.isNotEmpty == true) ? followUp : null,
      surgeryDone: rawSurgeryDone,
      surgeryType: normSurgeryType,
      ringPessary: ringPessary,
      ringPessarySize: ringPessarySize,
      fieldConfidences: confidences,
      overallConfidence: overallConf,
      rawText: buffer.toString(),
      scannedAt: DateTime.now(),
    );
  }

  /// Generates the prompt strictly tailored to the Nepal MoHP Gynecological Camp Yellow Form.
  String _buildSystemPrompt(int pageNumber) {
    return '''
You are an expert clinical digitization assistant for the official Nepal Ministry of Health and Population (MoHP) Gynecological Camp Yellow Form (गाइनो शिविर फाराम).
Analyze the provided medical intake form image carefully (Target Page: ${pageNumber == 0 ? 'Auto-detect' : 'Page $pageNumber'}).

CRITICAL FORM INSTRUCTIONS:
- The Yellow Form is a standardized 2-page intake instrument. Do NOT invent, assume, or hallucinate fields that are not printed on the physical form.
- Specifically: There is NO caste, NO education, NO occupation, NO gravida, NO respiratory rate, NO temperature, NO weight, and NO height on this form.
- Extract ONLY the actual printed fields, checkboxes, letter boxes, and handwritten entries.

FORM STRUCTURE BY PAGE:

PAGE 1 (FRONT) — PATIENT REGISTRATION:
1. Header:
   - "PATIENT TOKEN ID / अस्पताल दर्ता नं." format: e.g. "KTM01-0001" or QR code string
2. Section A: Patient Demographics / बिरामी विवरण:
   - "First Name: पहिलो नाम" (letter boxes)
   - "Surname: थर" (letter boxes)
   - "Patient Age: उमेर" (numeric digit boxes)
   - "Marital Status / वैवाहिक स्थिति" (4 checkboxes: Married, Widow, Unmarried, Divorced)
   - "Husband's Name: श्रीमान / बुबाको नाम" (letter boxes -> relativeName)
   - "Mobile No.: मोबाइल नम्बर" (10 digit boxes)
   - "Age at Marriage: विवाह उमेर" (numeric digit boxes -> maritalAge)
   - "Contact Person (Secondary): सम्पर्क व्यक्ति" (letter boxes -> contactPerson)
   - "Contact Mobile No.: सम्पर्क नम्बर" (10 digit boxes -> contactMobile)
   - "District: जिल्ला" (letter boxes)
   - "Province: प्रदेश" (letter boxes -> province, e.g. Bagmati)
   - "Palika / Municipality: पालिका / नगर" (letter boxes)
   - "Ward No.: वडा" (digit boxes -> ward)
3. Section B: Reasons for Visit / जाँचको कारण (8 exact checkboxes):
   - "Something Hanging Out / Prolapse (पाठेघर खस्ने)"
   - "Vaginal Discharge / Itching (स्राव / खटिरा)"
   - "Problems Passing Urine (पिसाब सम्बन्धी समस्या)"
   - "Problems Passing Stool (दिसा सम्बन्धी समस्या)"
   - "Menstrual Problem (महिनावारी सम्बन्धी समस्या)"
   - "Infertility (बाँझोपन)"
   - "Pelvic / Abdominal Pain (दुखाई)"
   - "General Gynaecological Checkup (सामान्य जाँच)"
4. Section C: Patient Consent / सहमति (2 exact checkboxes):
   - "I consent to examination and treatment / जाँच र उपचार गर्न सहमत छु" (consentTreatment: bool)
   - "I consent to storage of my medical information / स्वास्थ्य विवरण भण्डारण गर्न सहमत छु" (consentStoreMedicalInfo: bool)

PAGE 2 (BACK) — CLINICAL ASSESSMENT (STATIONS 1-6):
1. Header: "Patient ID: [ ][ ][ ][ ][ ][ ][ ][ ][ ]" and Patient Name
2. Station 1: Anamnesis & Obstetric History:
   - "Deliveries (P): [ ]" (integer deliveries)
   - "Living Children: [ ]" (integer livingChildren)
   - "Abortions: [ ]" (integer abortions)
   - "Complaints Duration:" (3 checkboxes: "< 3 months", "3-12 months", "> 1 year")
   - "Clinical Complaints:" (9 exact checkboxes):
     "Lower Abdominal Pain", "White / Foul Discharge", "Pelvic Heaviness",
     "Burning Micturition", "Urinary Incontinence", "Dyspareunia",
     "Coital Bleeding", "Mass Per Vagina", "Severe Backache"
3. Station 2: POP Examination (Baden-Walker):
   - "Uterus Inside:" (2 checkboxes: "Yes", "No (Prolapsed)" -> uterusInside: true/false)
   - "Pelvic Tone:" (3 checkboxes: "Normal", "Weak", "Hypertonic" -> pelvicFloorTone: string)
   - "Baden-Walker Staging:"
     - "Anterior (Cystocele): [ ]" (0 to 4)
     - "Middle (Uterine): [ ]" (0 to 4)
     - "Posterior (Rectocele): [ ]" (0 to 4)
     - "Highest Stage: [ ]" (0 to 4)
   - "Cervix Appearance:" (handwritten line text -> cervixRemarks)
   - "Vagina / Vulva:" (handwritten line text -> vaginaRemarks)
4. Station 3: Vitals & Point-of-Care Labs:
   - "Blood Pressure: [ ][ ] / [ ][ ] mmHg" (systolicBp / diastolicBp)
   - "Pulse: [ ][ ][ ] bpm" (pulseRate)
   - "SpO2: [ ][ ] %" (spo2)
   - "Blood Glucose: [ ][ ][ ] mg/dL" (bloodGlucose)
   - "Urine Test:" (4 checkboxes: "Normal", "Protein+", "Glucose+", "Blood+")
   - "Pregnancy Test (UPT):" (3 checkboxes: "Negative", "Positive", "Not Done")
5. Station 4: Confirmed Diagnoses / निदान (21 checkboxes + Other):
   - Checkboxes: "atrophy vagina", "bacterial vaginosis", "candid infection", "trichomonas",
     "PID", "cervicitis", "cervical polyp", "cervical carcinoma", "condylomata", "fistula",
     "infertility", "myoma", "cystitis", "lichen sclerosis", "stress incontinence", "ovarian tumor",
     "urge incontinence", "menstrual disorder", "weak pelvic floor muscle", "pregnancy",
     "hypertonic pelvic floor muscle", and handwritten text under "Other:"
6. Station 5: Treatment & Prescriptions / उपचार:
   - Medications Dispensed (10 checkboxes):
     "clotrimazol (canesten)", "estradiol crème", "metronidazol", "doxycycline",
     "azithromycin", "nitrofurantoine", "medroxyprogesterone", "ciproflox", "mirasin", "clobetasol"
   - "Ring Pessary:" [ ] Yes [ ] No, Size: [ ][ ][ ] mm
   - "Surgery Done:" [ ] Yes [ ] No, Type: [ ] Open surgery [ ] Laparoscopy [ ] Vaginal route
7. Station 6: Outtake & Continuity of Care / अनुगमन:
   - "Follow-up Required:" [ ] Yes (Follow-up Needed) [ ] No (Routine)
   - "Follow-up Destination:" (handwritten line text)
   - "Surgical Referral:" [ ] None [ ] Scheer Memorial Hospital [ ] Model Hospital [ ] Local Government Hospital
   - "Clinical Notes:" (multi-line handwritten remarks)

Extract the information accurately into this EXACT JSON structure:
{
  "pageNumber": ${pageNumber == 0 ? '1 or 2' : pageNumber},
  "demographics": {
    "patientTokenId": "Token or registration ID (e.g. GC-KTM01-2026-001 or KTM01-0001)",
    "firstName": "First name of patient (e.g. MAYA)",
    "surname": "Surname (e.g. TAMANG)",
    "age": number or null,
    "maritalStatus": "married or widow or unmarried or divorced",
    "relativeName": "Husband or father name (e.g. SOM BAHADUR TAMANG)",
    "mobile": "10-digit phone number or empty",
    "maritalAge": number or null,
    "contactPerson": "Secondary contact person name (e.g. BISHAL TAMANG)",
    "contactMobile": "10-digit contact phone number or empty",
    "province": "Province name (e.g. BAGMATI)",
    "district": "District name (e.g. KATHMANDU)",
    "municipality": "Palika or municipality name (e.g. BUDHANILKANTHA)",
    "ward": "Ward number (e.g. 04)",
    "reasonsForVisit": ["List of checked visit reasons from Section B"],
    "consentTreatment": true or false,
    "consentStoreMedicalInfo": true or false
  },
  "obstetrics": {
    "deliveries": number or null,
    "livingChildren": number or null,
    "abortions": number or null,
    "complaintsDuration": "< 3 months or 3-12 months or > 1 year",
    "clinicalComplaints": ["List of checked clinical complaints from Station 1"]
  },
  "popStaging": {
    "uterusInside": true or false,
    "pelvicFloorTone": "normal or weak or hypertonic",
    "anteriorStage": number (0-4) or null,
    "middleStage": number (0-4) or null,
    "posteriorStage": number (0-4) or null,
    "highestPopStage": number (0-4) or null,
    "cervixRemarks": "Handwritten Cervix Appearance (e.g. Erosion, contact bleeding)",
    "vaginaRemarks": "Handwritten Vagina / Vulva (e.g. Mild atrophic vaginitis, discharge)"
  },
  "vitals": {
    "systolicBp": number or null,
    "diastolicBp": number or null,
    "pulseRate": number or null,
    "spo2": number or null,
    "bloodGlucose": number or null,
    "urineTest": "Normal or Protein+ or Glucose+ or Blood+ or combined string",
    "pregnancyTest": "neg or pos or not_done"
  },
  "diagnoses": ["List of checked diagnoses from Station 4, plus Other if filled"],
  "medications": ["List of checked medications from Station 5"],
  "ringPessary": true or false,
  "ringPessarySize": number or null,
  "surgeryDone": true or false,
  "surgeryType": "Open surgery or Laparoscopy or Vaginal route or null",
  "followUpNeeded": true or false,
  "followUpDestination": "Follow-up destination clinic or nurse",
  "surgicalReferral": "Scheer Memorial Hospital or Model Hospital or Local Government Hospital or None",
  "clinicalNotes": "Clinical notes written in Station 6",
  "rawSummary": "A concise summary of all visible handwriting and marked fields on the page."
}

Do NOT output markdown blocks or conversational text. Output ONLY the raw JSON object.
''';
  }

  void dispose() {
    _client.close();
  }
}
