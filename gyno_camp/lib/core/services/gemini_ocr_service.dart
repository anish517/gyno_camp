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
import '../../models/patient_model.dart';
import '../security/security_service.dart';
import '../utils/form_page_identifier.dart';
import 'http_central_api_service.dart';
import 'report_aggregation_service.dart';
import 'session_service.dart';

class GeminiOcrException implements Exception {
  final String message;
  final int? statusCode;
  const GeminiOcrException(this.message, {this.statusCode});

  @override
  String toString() => 'OcrServiceException: $message (status: $statusCode)';
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

  /// The server may fail over across several models (45s each), so allow time.
  static const Duration requestTimeout = Duration(seconds: 95);

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
    return extractFromBytes(
      rawBytes,
      imagePath: imageFile.path,
      pageNumber: pageNumber,
    );
  }

  /// Sends raw image bytes of a Yellow Form to the GynoCamp server for Gemini extraction.
  Future<OcrScanResultModel> extractFromBytes(
    Uint8List rawBytes, {
    String imagePath = '',
    int pageNumber = 0,
  }) async {
    if (rawBytes.isEmpty) {
      throw const GeminiOcrException('Image file is empty or unreadable.');
    }

    final secret = _deviceSecret.isNotEmpty ? _deviceSecret : 'offline-sync-device-secret';

    HttpCentralApiService.beginActiveRequest();
    late final http.Response response;
    try {
      // Prepare & optimize image (<= 1600px max dimension, quality 85% JPEG)
      final prepared = await _prepareImage(rawBytes);

      final targetBaseUrl = _baseUrl;
      final uri = Uri.parse('$targetBaseUrl/api/ocr/extract');
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
        debugPrint('[FormOCR] Sending image to server (${rawBytes.length ~/ 1024} KB raw, Page: $pageNumber)...');
      }

      try {
        response = await _client.post(uri, headers: headers, body: body).timeout(requestTimeout);
        if (_explicitBaseUrl == null) {
          HttpCentralApiService.markServerOnline(targetBaseUrl);
        }
      } on TimeoutException {
        throw const GeminiOcrException('Form digitization timed out. Check the server connection and try again.');
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[FormOCR] Network error: ${e.runtimeType}');
        }
        throw const GeminiOcrException('Cannot reach the GynoCamp server for form digitization.');
      }
    } finally {
      HttpCentralApiService.endActiveRequest();
    }

    if (response.statusCode != 200) {
      var message = 'OCR service unavailable (status ${response.statusCode}).';
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
        throw const GeminiOcrException('OCR service returned no result.');
      }
      final parsedData = jsonDecode(extractedText) as Map<String, dynamic>;

      return _mapJsonToScanResult(
        parsedData: parsedData,
        imagePath: imagePath,
        fallbackPageNumber: pageNumber,
      );
    } catch (e) {
      if (e is GeminiOcrException) rethrow;
      throw GeminiOcrException('Failed to parse OCR output: $e');
    }
  }

  /// Public helper for compressing and base64-encoding scan images for local SQLite storage.
  /// On Android/iOS/Desktop (native isolates), compresses > 350 KB images off the UI thread
  /// so each page stays well below Android's 2 MB SQLite CursorWindow limit.
  /// On Flutter Web (no native isolates and no Android CursorWindow limit), skips pure-Dart
  /// software decode/re-encode so the browser main thread never freezes on commit.
  Future<({String base64, String mimeType})> prepareImageForStorage(Uint8List bytes) async {
    final isPng = bytes.length > 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final defaultMime = isPng ? 'image/png' : 'image/jpeg';

    // Fast path: on Web (single-threaded JS, no Android 2MB CursorWindow limit) or
    // when already compact (<= 1.2 MB raw -> safely streamed via 800 KB SUBSTR chunks on Android),
    // encode directly (< 2 ms) without degrading handwriting stroke sharpness.
    if (kIsWeb || bytes.length <= 1200000) {
      return (base64: base64Encode(bytes), mimeType: defaultMime);
    }

    try {
      final compressed = await compute(_compressForSqliteStorageIsolate, bytes)
          .timeout(const Duration(seconds: 6), onTimeout: () => null);
      if (compressed != null && compressed.isNotEmpty) {
        return (base64: base64Encode(compressed), mimeType: 'image/jpeg');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FormOCR] SQLite storage compression failed: $e');
      }
    }

    // Fallback: encode directly (Android SQLite reader safely streams >800KB values via SUBSTR chunks)
    return (base64: base64Encode(bytes), mimeType: defaultMime);
  }

  /// Scales image down if larger than 1600px to ensure fast mobile upload.
  /// For already-compressed images (<= 2.5 MB), skips pure-Dart software decoding
  /// to avoid locking the UI thread and freezing animations.
  Future<({String base64, String mimeType})> _prepareImage(Uint8List bytes) async {
    final isPng = bytes.length > 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final defaultMime = isPng ? 'image/png' : 'image/jpeg';

    // Fast path: if already <= 3.5 MB, avoid software decompression entirely to preserve
    // full handwriting & checkbox sharpness for Gemini Vision.
    if (bytes.length <= 3500000) {
      return (base64: base64Encode(bytes), mimeType: defaultMime);
    }

    // Heavy path: for very large images (> 3.5 MB), resize to 2200px max dimension.
    // On native platforms, offload to a background isolate (compute) to keep UI thread fluid.
    if (!kIsWeb) {
      try {
        final resized = await compute(_resizeImageIsolate, bytes);
        if (resized != null) {
          return (base64: base64Encode(resized), mimeType: 'image/jpeg');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[FormOCR] Background resize failed: $e');
        }
      }
    } else {
      // On web, yield to the event loop so the UI can paint before running image resize
      await Future<void>.delayed(Duration.zero);
      try {
        final decoded = img.decodeImage(bytes);
        if (decoded != null && (decoded.width > 2200 || decoded.height > 2200)) {
          final resized = img.copyResize(
            decoded,
            width: decoded.width > decoded.height ? 2200 : null,
            height: decoded.height >= decoded.width ? 2200 : null,
          );
          final compressedJpg = img.encodeJpg(resized, quality: 88);
          return (base64: base64Encode(compressedJpg), mimeType: 'image/jpeg');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[FormOCR] Image resize skipped: $e');
        }
      }
    }

    return (base64: base64Encode(bytes), mimeType: defaultMime);
  }

  /// Maps structured JSON returned by Gemini to [OcrScanResultModel].
  OcrScanResultModel _mapJsonToScanResult({
    required Map<String, dynamic> parsedData,
    required String imagePath,
    required int fallbackPageNumber,
  }) {
    final int? explicitDetectedPage = () {
      final dp = (parsedData['detectedPage'] as num?)?.toInt();
      if (dp == 1 || dp == 2) return dp;
      final pn = (parsedData['pageNumber'] as num?)?.toInt();
      if (pn == 1 || pn == 2) return pn;
      return null;
    }();
    final int detectedPage = explicitDetectedPage ?? fallbackPageNumber;

    final rawDemo = (parsedData['demographics'] as Map<String, dynamic>?) ?? {};
    final rawFormPageCode = (parsedData['formPageCode'] ??
            rawDemo['formPageCode'] ??
            '')
        .toString()
        .trim();
    final parsedFormPageCode = FormPageIdentity.parse(rawFormPageCode);
    final rawObs = (parsedData['obstetrics'] as Map<String, dynamic>?) ?? {};
    final rawVitals = (parsedData['vitals'] as Map<String, dynamic>?) ?? {};
    final rawPop = (parsedData['popStaging'] as Map<String, dynamic>?) ?? {};
    int? parseHandwrittenInt(dynamic raw) {
      if (raw == null) return null;
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      var s = raw.toString().trim();
      if (s.isEmpty || s.toLowerCase() == 'null') return null;
      const dev = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];
      for (int i = 0; i < dev.length; i++) {
        s = s.replaceAll(dev[i], i.toString());
      }
      final m = RegExp(r'-?\d+').firstMatch(s);
      return m != null ? int.tryParse(m.group(0)!) : null;
    }

    String cleanHandwrittenDigits(dynamic raw) {
      if (raw == null) return '';
      var s = raw.toString().trim();
      if (s.isEmpty || s.toLowerCase() == 'null') return '';
      const dev = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];
      for (int i = 0; i < dev.length; i++) {
        s = s.replaceAll(dev[i], i.toString());
      }
      return s.replaceAll(RegExp(r'[\s\-]+'), '');
    }

    String normalizeDiagnosisItem(String raw) {
      final low = raw.toLowerCase().trim();
      for (final d in ClinicalConstants.defaultDiagnoses) {
        if (d.toLowerCase() == low) return d;
      }
      return switch (low) {
        'candidiasis' || 'candida' || 'vaginal candidiasis' => 'candid infection',
        'bv' || 'bacterial vaginitis' => 'bacterial vaginosis',
        'trichomoniasis' => 'trichomonas',
        'pelvic inflammatory disease' => 'PID',
        'atrophic vaginitis' || 'vaginal atrophy' => 'atrophy vagina',
        'uterine fibroid' || 'fibroid' || 'uterine myoma' => 'myoma',
        _ => raw.trim(),
      };
    }

    String normalizeMedicationItem(String raw) {
      final low = raw.toLowerCase().trim();
      for (final m in ClinicalConstants.defaultMedications) {
        if (m.toLowerCase() == low) return m;
      }
      return switch (low) {
        'clotrimazole' || 'clotrimazol' || 'canesten' => 'clotrimazol (canesten)',
        'estradiol' || 'estradiol cream' || 'estradiol creme' => 'estradiol crème',
        'metronidazole' || 'flagyl' => 'metronidazol',
        'nitrofurantoin' => 'nitrofurantoine',
        'ciprofloxacin' => 'ciproflox',
        _ => raw.trim(),
      };
    }

    final rawDiagnoses = (parsedData['diagnoses'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty && e.toLowerCase() != 'null')
            .map(normalizeDiagnosisItem)
            .toSet()
            .toList() ??
        <String>[];
    final rawMeds = (parsedData['medications'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((e) =>
                e.isNotEmpty &&
                e.toLowerCase() != 'null' &&
                !ReportAggregationService.isDosageInstruction(e))
            .map(normalizeMedicationItem)
            .toSet()
            .toList() ??
        <String>[];
    final rawCounseling = (parsedData['counseling'] as List<dynamic>?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty && e.toLowerCase() != 'null').toList() ?? <String>[];
    // Station 5 extra items (Ring Pessary & Surgery)
    // NOTE: Pessary is a device fitting, NOT a dispensed medication.
    // We do NOT inject it into rawMeds. It stays in ringPessary/pessaryType/ringPessarySize.
    final ringPessary = parsedData['ringPessary'] == true || rawPop['ringPessary'] == true;
    final ringPessarySize = parseHandwrittenInt(parsedData['ringPessarySize']) ??
        parseHandwrittenInt(rawPop['ringPessarySize']);
    // Read pessaryType from Gemini (ring / ring with support / ring with knob)
    final rawPessaryType = parsedData['pessaryType']?.toString().trim();
    final String? pessaryType = (rawPessaryType != null && rawPessaryType.isNotEmpty && rawPessaryType.toLowerCase() != 'null')
        ? rawPessaryType.toLowerCase()
        : null;

    final rawSurgicalRef = parsedData['surgicalReferral']?.toString().trim();
    final surgicalRef = (rawSurgicalRef != null &&
            rawSurgicalRef.toLowerCase().replaceAll('.', '').trim() == 'model hosp')
        ? 'Model Hospital'
        : rawSurgicalRef;
    final rawFollowUp = parsedData['followUpDestination']?.toString().trim();
    final rawFollowUpHospital = parsedData['followUpHospital']?.toString().trim();
    String? followUp;
    if (rawFollowUpHospital != null &&
        rawFollowUpHospital.isNotEmpty &&
        rawFollowUpHospital.toLowerCase() != 'null') {
      followUp = rawFollowUpHospital;
    } else if (rawFollowUp != null &&
        rawFollowUp.isNotEmpty &&
        rawFollowUp.toLowerCase() != 'null') {
      followUp = rawFollowUp;
    }
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
    final rawTreatmentLevel = parsedData['treatmentLevel']?.toString().trim() ??
        parsedData['levelOfTreatment']?.toString().trim() ??
        parsedData['consultation']?.toString().trim();
    final String? treatmentLevel = PatientModel.normalizeTreatmentLevel(rawTreatmentLevel);

    // Normalize Province (case-insensitive + 8-box character prefix support e.g. SUDURPAS -> Sudurpashchim)
    String normProvince(String? raw) {
      if (raw == null || raw.trim().isEmpty || raw.trim().toLowerCase() == 'null') return '';
      final clean = raw.replaceAll(RegExp(r'\s+'), '').toLowerCase();
      for (final p in ClinicalConstants.nepalProvinces) {
        final pLow = p.toLowerCase();
        if (pLow == clean || (clean.length >= 4 && pLow.startsWith(clean))) return p;
      }
      return '';
    }

    int editDistance(String a, String b) {
      if (a == b) return 0;
      if (a.isEmpty) return b.length;
      if (b.isEmpty) return a.length;
      var prev = List<int>.generate(b.length + 1, (j) => j);
      for (int i = 1; i <= a.length; i++) {
        final curr = List<int>.filled(b.length + 1, 0);
        curr[0] = i;
        for (int j = 1; j <= b.length; j++) {
          final cost = a[i - 1] == b[j - 1] ? 0 : 1;
          final del = prev[j] + 1;
          final ins = curr[j - 1] + 1;
          final sub = prev[j - 1] + cost;
          curr[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
        }
        prev = curr;
      }
      return prev[b.length];
    }

    // Normalize District (case-insensitive, space-insensitive & fuzzy handwriting match against NepalGeodata)
    String normDistrict(String? raw, String prov) {
      if (raw == null || raw.trim().isEmpty || raw.trim().toLowerCase() == 'null') return '';
      var clean = raw.replaceAll(RegExp(r'[^A-Za-z]'), '').toLowerCase();
      if (clean.isEmpty) return '';
      const phoneticAliases = <String, String>{
        'kavre': 'kavrepalanchok',
        'kabre': 'kavrepalanchok',
        'kavrepalanchowk': 'kavrepalanchok',
        'sindhupalchowk': 'sindhupalchok',
        'chitawan': 'chitwan',
        'makawanpur': 'makwanpur',
        'tanahu': 'tanahun',
        'dhanusa': 'dhanusha',
        'terhathum': 'tehrathum',
        'kapilbastu': 'kapilvastu',
      };
      clean = phoneticAliases[clean] ?? clean.replaceAll('chowk', 'chok');

      final provDistricts = NepalGeodata.districtsFor(prov);
      for (final d in provDistricts) {
        if (d.replaceAll(' ', '').toLowerCase() == clean) return d;
      }
      for (final d in provDistricts) {
        final dClean = d.replaceAll(' ', '').toLowerCase();
        if (clean.contains(dClean) || (clean.length >= 4 && dClean.contains(clean))) return d;
      }
      // Search across all 77 districts if province was blank or misidentified
      for (final d in NepalGeodata.allDistricts) {
        if (d.replaceAll(' ', '').toLowerCase() == clean) return d;
      }
      for (final d in NepalGeodata.allDistricts) {
        final dClean = d.replaceAll(' ', '').toLowerCase();
        if (clean.contains(dClean) || (clean.length >= 4 && dClean.contains(clean))) return d;
      }
      // Fuzzy Levenshtein match for 1-2 character handwriting slips (e.g. "KATHMNDU" -> "Kathmandu", "BHAKTPUR" -> "Bhaktapur")
      if (clean.length >= 5) {
        String? bestMatch;
        int bestDist = 99;
        final maxAllowed = clean.length >= 7 ? 2 : 1;
        for (final d in NepalGeodata.allDistricts) {
          final dClean = d.replaceAll(' ', '').toLowerCase();
          final dist = editDistance(clean, dClean);
          if (dist <= maxAllowed && dist < bestDist) {
            bestDist = dist;
            bestMatch = d;
          }
        }
        if (bestMatch != null) return bestMatch;
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

    var normProv = normProvince(rawDemo['province']?.toString());
    final normDist = normDistrict(rawDemo['district']?.toString(), normProv);
    if (normProv.isEmpty && normDist.isNotEmpty) {
      normProv = NepalGeodata.provinceOf(normDist);
    }
    final normalizedReasons = normReasons(rawDemo['reasonsForVisit']);

    // Normalize demographics (strictly Yellow Form Page 1 fields — NO caste/education/occupation)
    final demographics = <String, dynamic>{
      'firstName': () {
        final v = rawDemo['firstName']?.toString().trim() ?? '';
        return v.toLowerCase() == 'null' ? '' : v;
      }(),
      'surname': () {
        final v = rawDemo['surname']?.toString().trim() ?? '';
        return v.toLowerCase() == 'null' ? '' : v;
      }(),
      'age': parseHandwrittenInt(rawDemo['age']),
      'maritalStatus': () {
        final raw = rawDemo['maritalStatus']?.toString().toLowerCase().trim();
        if (raw == null || raw.isEmpty || raw == 'null') return null;
        return raw;
      }(),
      'relativeName': () {
        final v = rawDemo['relativeName']?.toString().trim() ?? (rawDemo['spouseOrFatherName']?.toString().trim() ?? '');
        return v.toLowerCase() == 'null' ? '' : v;
      }(),
      'relativeType': () {
        // Read strictly from ticked/circled label on form; preserve null if unselected
        final raw = rawDemo['relationType']?.toString().trim();
        if (raw != null && raw.isNotEmpty && raw.toLowerCase() != 'null') {
          if (raw.toLowerCase().contains('father') || raw.contains('बुबा')) return 'Father';
          if (raw.toLowerCase().contains('husband') || raw.contains('श्रीमान्')) return 'Husband';
          return raw;
        }
        return null;
      }(),
      'relativeSurname': () {
        final relSur = rawDemo['relativeSurname']?.toString().trim() ?? '';
        if (relSur.isNotEmpty && relSur.toLowerCase() != 'null') return relSur;
        return '';
      }(),
      'mobile': cleanHandwrittenDigits(rawDemo['mobile']),
      'maritalAge': parseHandwrittenInt(rawDemo['maritalAge']) ??
          parseHandwrittenInt(rawObs['ageAtMarriage']),
      'contactPerson': () {
        final v = rawDemo['contactPerson']?.toString().trim() ?? '';
        return v.toLowerCase() == 'null' ? '' : v;
      }(),
      'contactMobile': cleanHandwrittenDigits(rawDemo['contactMobile']),
      'province': normProv,
      'district': normDist,
      'municipality': () {
        final v = rawDemo['municipality']?.toString().trim() ?? '';
        return v.toLowerCase() == 'null' ? '' : v;
      }(),
      'ward': cleanHandwrittenDigits(rawDemo['ward']),
      'reasonsForVisit': normalizedReasons,
      'consentTreatment': rawDemo['consentTreatment'] as bool?,
      'consentStoreMedicalInfo': rawDemo['consentStoreMedicalInfo'] as bool?,
      'patientId': () {
        final rawId = rawDemo['patientId'] ??
            rawDemo['patientTokenId'] ??
            rawDemo['patient_id'] ??
            rawDemo['tokenNo'] ??
            rawDemo['regNo'] ??
            rawDemo['registrationId'] ??
            parsedData['patientId'] ??
            parsedData['patientTokenId'] ??
            parsedData['patient_id'] ??
            parsedData['tokenNo'] ??
            '';
        final str = rawId.toString().trim();
        final norm = (str.isEmpty || str.toLowerCase() == 'null')
            ? ''
            : PatientModel.normalizePatientId(rawInput: str);
        return norm.isNotEmpty ? norm : (parsedFormPageCode.formNumber ?? '');
      }(),
      'patientTokenId': () {
        final rawId = rawDemo['patientId'] ??
            rawDemo['patientTokenId'] ??
            rawDemo['patient_id'] ??
            rawDemo['tokenNo'] ??
            rawDemo['regNo'] ??
            rawDemo['registrationId'] ??
            parsedData['patientId'] ??
            parsedData['patientTokenId'] ??
            parsedData['patient_id'] ??
            parsedData['tokenNo'] ??
            '';
        final str = rawId.toString().trim();
        final norm = (str.isEmpty || str.toLowerCase() == 'null')
            ? ''
            : PatientModel.normalizePatientId(rawInput: str);
        return norm.isNotEmpty ? norm : (parsedFormPageCode.formNumber ?? '');
      }(),
      if (parsedFormPageCode.formattedCode.isNotEmpty)
        'formPageCode': parsedFormPageCode.formattedCode,
    };

    // Normalize obstetrics (strictly Yellow Form Station 1 fields — NO gravida/deliveries-years-ago)
    final obstetrics = <String, dynamic>{
      'deliveries': parseHandwrittenInt(rawObs['deliveries']) ??
          parseHandwrittenInt(rawObs['para']),
      'livingChildren': parseHandwrittenInt(rawObs['livingChildren']),
      'abortions': parseHandwrittenInt(rawObs['abortions']),
      'complaintsDuration': rawObs['complaintsDuration']?.toString().trim() ?? '',
      'clinicalComplaints': () {
        final rawList = (rawObs['clinicalComplaints'] as List<dynamic>?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() ?? <String>[];
        final normalized = <String>[];
        for (final item in rawList) {
          final s = item.toLowerCase();
          if (s.contains('prolapse') || s.contains('hanging') || s.contains('पाठेघर')) {
            if (!normalized.contains('prolapse')) normalized.add('prolapse');
          } else if (s.contains('discharge') || s.contains('itching') || s.contains('स्राव')) {
            if (!normalized.contains('discharge')) normalized.add('discharge');
          } else if (s.contains('urine') || s.contains('पिसाब')) {
            if (!normalized.contains('urine')) normalized.add('urine');
          } else if (s.contains('stool') || s.contains('दिसा')) {
            if (!normalized.contains('stool')) normalized.add('stool');
          } else if (s.contains('menstrual') || s.contains('महिनावारी')) {
            if (!normalized.contains('menstrual')) normalized.add('menstrual');
          } else if (s.contains('infertility') || s.contains('बाँझोपन') || s.contains('निःसन्तान')) {
            if (!normalized.contains('infertility')) normalized.add('infertility');
          } else if (s == 'lower_abdomen_pain' || (s.contains('pain') && !s.contains('back'))) {
            if (!normalized.contains('lower_abdomen_pain')) normalized.add('lower_abdomen_pain');
          } else if (s == 'lower_back_pain' || s.contains('back') || s.contains('ढाड') || s.contains('कम्मर')) {
            if (!normalized.contains('lower_back_pain')) normalized.add('lower_back_pain');
          } else if (s.contains('checkup') || s.contains('जाँच')) {
            if (!normalized.contains('checkup')) normalized.add('checkup');
          } else {
            if (!normalized.contains(item)) normalized.add(item);
          }
        }
        return normalized;
      }(),
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
                final detailMap = <String, dynamic>{
                  'duration': item['duration']?.toString() ?? '',
                  'remarks': item['remarks']?.toString() ?? '',
                  'subOption': subOptions is List ? subOptions.join(', ') : (subOptions?.toString() ?? ''),
                };
                result[key] = detailMap;
                final kLow = key.toLowerCase();
                if (kLow.contains('prolapse') || kLow.contains('hanging')) result['prolapse'] = detailMap;
                if (kLow.contains('discharge') || kLow.contains('itching')) result['discharge'] = detailMap;
                if (kLow.contains('urine')) result['urine'] = detailMap;
                if (kLow.contains('stool')) result['stool'] = detailMap;
                if (kLow.contains('menstrual')) result['menstrual'] = detailMap;
                if (kLow.contains('infertility')) result['infertility'] = detailMap;
                if (kLow.contains('abdomen')) result['lower_abdomen_pain'] = detailMap;
                if (kLow.contains('back')) result['lower_back_pain'] = detailMap;
                if (kLow.contains('checkup')) result['checkup'] = detailMap;
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
    final parsedSys = parseHandwrittenInt(rawVitals['systolicBp']);
    final parsedDia = parseHandwrittenInt(rawVitals['diastolicBp']);
    final parsedPulse = parseHandwrittenInt(rawVitals['pulseRate']) ??
        parseHandwrittenInt(rawVitals['pulse']);
    final parsedSpo2 = parseHandwrittenInt(rawVitals['spo2']);
    final parsedGlucose = parseHandwrittenInt(rawVitals['bloodGlucose']) ??
        parseHandwrittenInt(rawVitals['glucose']) ??
        parseHandwrittenInt(rawVitals['bloodSugar']);
    final vitals = <String, dynamic>{
      'systolicBp': parsedSys,
      'diastolicBp': parsedDia,
      'pulseRate': parsedPulse,
      'pulse': parsedPulse,
      'spo2': parsedSpo2,
      'bloodGlucose': parsedGlucose,
      'glucose': parsedGlucose,
      'urineTest': () {
        final raw = rawVitals['urineTest']?.toString().trim();
        if (raw == null || raw.isEmpty || raw.toLowerCase() == 'null') return null;
        return raw.toLowerCase() == 'normal' ? 'normal' : (raw.toLowerCase() == 'pos' || raw.toLowerCase() == 'positive' ? 'pos' : raw);
      }(),
      'pregnancyTest': () {
        final raw = rawVitals['pregnancyTest']?.toString().trim().toLowerCase() ?? '';
        if (raw.isEmpty || raw == 'null') return null;
        if (raw.contains('pos')) return 'pos';
        if (raw.contains('not') || raw.contains('done')) return 'not_done';
        if (raw.contains('neg')) return 'neg';
        return null;
      }(),
      'ecg': rawVitals['ecg']?.toString().trim() ?? '',
      'ecgNotes': rawVitals['ecgNotes']?.toString().trim() ?? rawVitals['ecg']?.toString().trim() ?? '',
    };

    // Normalize POP Staging (strictly Yellow Form Station 2 fields)
    // Preserve null for undetected stages — do NOT default to 0
    final int? ant = parseHandwrittenInt(rawPop['anteriorStage']);
    final int? mid = parseHandwrittenInt(rawPop['middleStage']);
    final int? post = parseHandwrittenInt(rawPop['posteriorStage']);
    final int? popStageNum = parseHandwrittenInt(rawPop['highestPopStage']) ??
        parseHandwrittenInt(rawPop['highestStage']) ??
        parseHandwrittenInt(rawPop['stage']) ??
        (ant != null || mid != null || post != null
            ? [ant ?? 0, mid ?? 0, post ?? 0].reduce((a, b) => a > b ? a : b)
            : null);

    final popStaging = <String, dynamic>{
      'anteriorStage': ant,
      'middleStage': mid,
      'posteriorStage': post,
      'highestPopStage': popStageNum,
      'highestStage': popStageNum,
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
    if (demographics['firstName']?.toString().isNotEmpty == true) {
      confidences['firstName'] = 0.96;
      confidences['name'] = 0.96;
    }
    if (demographics['surname']?.toString().isNotEmpty == true) {
      confidences['surname'] = 0.96;
      confidences['name'] = 0.96;
    }
    if (demographics['relativeName']?.toString().isNotEmpty == true) {
      confidences['relativeName'] = 0.96;
      confidences['relative'] = 0.96;
    }
    if (demographics['relativeSurname']?.toString().isNotEmpty == true) {
      confidences['relativeSurname'] = 0.96;
      confidences['relative'] = 0.96;
    }
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
    buffer.writeln('[AUTOMATED FORM OCR]');
    buffer.writeln('Page: $detectedPage');
    if (treatmentLevel != null) {
      buffer.writeln('Consultation: ${(treatmentLevel == "counseling" || treatmentLevel == "council_level") ? "Counseling" : "Gynocheckup"}');
    }
    if (demographics['firstName'] != '' || demographics['surname'] != '') {
      buffer.writeln('Patient Name: ${demographics['firstName']} ${demographics['surname']}');
      final relFull = [
        demographics['relativeName']?.toString().trim() ?? '',
        demographics['relativeSurname']?.toString().trim() ?? '',
      ].where((s) => s.isNotEmpty).join(' ');
      buffer.writeln('Age: ${demographics['age'] ?? 'N/A'}, Marital: ${demographics['maritalStatus']}, Relative: $relFull (${demographics['relativeType'] ?? 'Relative'})');
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

    // Extract station dates from Gemini response (checking both top-level and section maps)
    String? intakeDate = _extractDate(
      parsedData['intakeDate'] ??
          rawDemo['intakeDate'] ??
          parsedData['date'] ??
          rawDemo['date'] ??
          parsedData['registrationDate'] ??
          rawDemo['registrationDate'],
    );
    String? anamnesisDate = _extractDate(
      parsedData['anamnesisDate'] ??
          rawObs['anamnesisDate'] ??
          rawDemo['anamnesisDate'],
    );
    intakeDate ??= anamnesisDate;
    String? examDate = _extractDate(parsedData['examDate'] ?? rawPop['examDate']);
    String? labTestDate = _extractDate(parsedData['labTestDate'] ?? rawVitals['labTestDate']);
    String? conclusionDate = _extractDate(parsedData['conclusionDate']);
    String? treatmentDate = _extractDate(parsedData['treatmentDate']);
    String? outtakeDate = _extractDate(parsedData['outtakeDate']);

    // Single-page station date consensus check
    final stationDates = [examDate, labTestDate, conclusionDate, treatmentDate, outtakeDate]
        .where((d) => d != null && d.isNotEmpty)
        .map((d) => d!)
        .toList();
    if (stationDates.length >= 2) {
      final counts = <String, int>{};
      for (final d in stationDates) {
        counts[d] = (counts[d] ?? 0) + 1;
      }
      final dominant = counts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      if ((counts[dominant] ?? 0) >= 2) {
        if (anamnesisDate != null && _differsOnlyByMonth01vs07(anamnesisDate, dominant)) {
          anamnesisDate = dominant;
        }
        examDate = (examDate == null || _differsOnlyByMonth01vs07(examDate, dominant)) ? dominant : examDate;
        labTestDate = (labTestDate == null || _differsOnlyByMonth01vs07(labTestDate, dominant)) ? dominant : labTestDate;
        conclusionDate = (conclusionDate == null || _differsOnlyByMonth01vs07(conclusionDate, dominant)) ? dominant : conclusionDate;
        treatmentDate = (treatmentDate == null || _differsOnlyByMonth01vs07(treatmentDate, dominant)) ? dominant : treatmentDate;
        outtakeDate = (outtakeDate == null || _differsOnlyByMonth01vs07(outtakeDate, dominant)) ? dominant : outtakeDate;
      }
    }
    intakeDate ??= stationDates.isNotEmpty ? stationDates.first : null;
    anamnesisDate ??= intakeDate;

    if (intakeDate != null && intakeDate.isNotEmpty) {
      demographics['intakeDate'] = intakeDate;
      demographics['date'] = intakeDate;
      buffer.writeln('Date: $intakeDate BS');
    }
    if (anamnesisDate != null && anamnesisDate.isNotEmpty) {
      demographics['anamnesisDate'] = anamnesisDate;
      buffer.writeln('Anamnesis Date: $anamnesisDate BS');
    }

    // Extract clinical notes from Station 6
    final rawClinicalNotes = parsedData['clinicalNotes']?.toString().trim();
    final String? clinicalNotes = (rawClinicalNotes != null && rawClinicalNotes.isNotEmpty && rawClinicalNotes.toLowerCase() != 'null')
        ? rawClinicalNotes
        : null;

    final initialScan = OcrScanResultModel(
      pageNumber: detectedPage,
      detectedPage: explicitDetectedPage ?? parsedFormPageCode.pageNumber,
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
      anamnesisDate: anamnesisDate,
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

    final inferredPage = FormPageIdentity.inferPageNumber(initialScan);
    final effectivePage = (fallbackPageNumber == 0 && explicitDetectedPage == null && parsedFormPageCode.pageNumber == null)
        ? 0
        : (inferredPage ?? detectedPage);
    return initialScan.copyWith(
      pageNumber: effectivePage,
      detectedPage: inferredPage,
    );
  }

  /// Extract and validate a date string from Gemini JSON.
  /// Returns canonical YYYY-MM-DD format or null.
  static String? _extractDate(dynamic raw) {
    if (raw == null) return null;
    var str = raw.toString().trim();
    if (str.isEmpty || str.toLowerCase() == 'null' || str == '—' || str == '-') return null;

    // Convert Devanagari numerals to ASCII digits
    const devanagari = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];
    for (int i = 0; i < devanagari.length; i++) {
      str = str.replaceAll(devanagari[i], i.toString());
    }
    str = str.replaceAll(RegExp(r'\s*(BS|AD)\b', caseSensitive: false), '').trim();

    // 1. Match YYYY-MM-DD, YYYY/MM/DD, or YYYY.MM.DD
    final mYmd = RegExp(r'\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b').firstMatch(str);
    if (mYmd != null) {
      final y = mYmd.group(1)!;
      var mo = int.tryParse(mYmd.group(2)!) ?? 1;
      var d = int.tryParse(mYmd.group(3)!) ?? 1;
      if (mo > 12 && d <= 12) {
        final tmp = mo;
        mo = d;
        d = tmp;
      }
      return '$y-${mo.clamp(1, 12).toString().padLeft(2, '0')}-${d.clamp(1, 32).toString().padLeft(2, '0')}';
    }

    // 2. Match DD-MM-YYYY, DD/MM/YYYY, or DD.MM.YYYY
    final mDmy = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2})\b').firstMatch(str);
    if (mDmy != null) {
      var d = int.tryParse(mDmy.group(1)!) ?? 1;
      var mo = int.tryParse(mDmy.group(2)!) ?? 1;
      final y = mDmy.group(3)!;
      if (mo > 12 && d <= 12) {
        final tmp = mo;
        mo = d;
        d = tmp;
      }
      return '$y-${mo.clamp(1, 12).toString().padLeft(2, '0')}-${d.clamp(1, 32).toString().padLeft(2, '0')}';
    }

    // 3. Match 2-digit year e.g. 83-07-06 or 06/07/83
    final mShort = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(str);
    if (mShort != null) {
      final p0 = int.tryParse(mShort.group(1)!) ?? 1;
      final p1 = int.tryParse(mShort.group(2)!) ?? 1;
      final p2 = int.tryParse(mShort.group(3)!) ?? 1;
      if (p0 >= 75 && p0 <= 99) {
        final y = 2000 + p0;
        return '$y-${p1.clamp(1, 12).toString().padLeft(2, '0')}-${p2.clamp(1, 32).toString().padLeft(2, '0')}';
      } else if (p2 >= 75 && p2 <= 99) {
        final y = 2000 + p2;
        return '$y-${p1.clamp(1, 12).toString().padLeft(2, '0')}-${p0.clamp(1, 32).toString().padLeft(2, '0')}';
      }
    }

    // Try to parse other ISO formats
    try {
      final dt = DateTime.parse(str);
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return str;
    }
  }

  static bool _differsOnlyByMonth01vs07(String a, String b) {
    if (a == b) return false;
    final aClean = a.replaceAll(RegExp(r'\s*BS', caseSensitive: false), '').trim();
    final bClean = b.replaceAll(RegExp(r'\s*BS', caseSensitive: false), '').trim();
    final ap = aClean.split(RegExp(r'[-/]'));
    final bp = bClean.split(RegExp(r'[-/]'));
    if (ap.length == 3 && bp.length == 3) {
      if (ap[0] == bp[0] && ap[2] == bp[2]) {
        final am = int.tryParse(ap[1]);
        final bm = int.tryParse(bp[1]);
        if ((am == 1 && bm == 7) || (am == 7 && bm == 1)) {
          return true;
        }
      }
    }
    return false;
  }

  void dispose() {
    _client.close();
  }
}

/// Top-level worker function for offloading software image resizing to a background isolate.
Uint8List? _resizeImageIsolate(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded != null && (decoded.width > 2200 || decoded.height > 2200)) {
      final resized = img.copyResize(
        decoded,
        width: decoded.width > decoded.height ? 2200 : null,
        height: decoded.height >= decoded.width ? 2200 : null,
      );
      return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
    }
  } catch (_) {}
  return null;
}

/// Compresses large scan images (> 1.2 MB) into high-clarity JPEG bytes (2048px max
/// dimension at 85% quality) so fine handwritten strokes and checkboxes remain crisp
/// for Gemini Vision while SQLite streams large Base64 safely in 800 KB chunks.
Uint8List? _compressForSqliteStorageIsolate(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final img.Image target = (decoded.width > 2048 || decoded.height > 2048)
        ? img.copyResize(
            decoded,
            width: decoded.width > decoded.height ? 2048 : null,
            height: decoded.height >= decoded.width ? 2048 : null,
          )
        : decoded;
    var jpg = Uint8List.fromList(img.encodeJpg(target, quality: 85));
    if (jpg.length > 1100000) {
      jpg = Uint8List.fromList(img.encodeJpg(target, quality: 76));
    }
    return jpg;
  } catch (_) {
    return null;
  }
}
