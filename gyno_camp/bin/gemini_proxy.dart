// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

/// Error raised by [GeminiProxy] carrying the HTTP status that the GynoCamp
/// server should return to its own client. Messages are deliberately generic:
/// upstream response bodies and API keys are never surfaced to callers.
class GeminiProxyException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const GeminiProxyException(this.statusCode, this.code, this.message);

  @override
  String toString() => 'GeminiProxyException($statusCode, $code): $message';
}

/// Sliding-window rate limiter (per key) with a short window and a daily cap.
///
/// Used both to cap OCR calls per approved device and to throttle repeated
/// failed authentication attempts per remote address.
class OcrRateLimiter {
  final int maxPerWindow;
  final Duration window;
  final int maxPerDay;
  final Map<String, List<DateTime>> _hits = {};

  OcrRateLimiter({
    this.maxPerWindow = 20,
    this.window = const Duration(minutes: 10),
    this.maxPerDay = 300,
  });

  /// Returns `null` when [key] may proceed, otherwise how long to wait.
  Duration? check(String key, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final hits = _prune(key, t);
    if (hits.isEmpty) return null;

    if (hits.length >= maxPerDay) {
      final retry = hits.first.add(const Duration(hours: 24)).difference(t);
      return retry.isNegative ? const Duration(seconds: 1) : retry;
    }

    final inWindow = hits.where((h) => t.difference(h) < window).toList();
    if (inWindow.length >= maxPerWindow) {
      final retry = inWindow.first.add(window).difference(t);
      return retry.isNegative ? const Duration(seconds: 1) : retry;
    }
    return null;
  }

  void record(String key, {DateTime? now}) {
    final t = now ?? DateTime.now();
    _prune(key, t).add(t);
  }

  /// Atomically checks and records a hit. Returns `null` when allowed.
  Duration? tryAcquire(String key, {DateTime? now}) {
    final wait = check(key, now: now);
    if (wait != null) return wait;
    record(key, now: now);
    return null;
  }

  List<DateTime> _prune(String key, DateTime now) {
    final hits = _hits.putIfAbsent(key, () => <DateTime>[]);
    hits.removeWhere((h) => now.difference(h) >= const Duration(hours: 24));
    return hits;
  }
}

/// Server-side Gemini client for Yellow Form OCR.
///
/// The Gemini API key exists ONLY here (read from the server environment). The
/// Flutter app never sees it. The prompt is also owned by the server so that
/// authenticated devices cannot use the endpoint as a general Gemini relay.
class GeminiProxy {
  final http.Client _client;
  final String? Function() _apiKeyProvider;
  final List<String> models;
  final Duration requestTimeout;
  final Duration Function(int attempt) retryDelay;

  static const Set<String> allowedMimeTypes = {'image/jpeg', 'image/png'};

  /// Hard cap for the base64 image payload (~6 MB of binary image data).
  static const int maxImageBase64Chars = 8 * 1024 * 1024;

  static const List<String> defaultModels = [
    'gemini-flash-lite-latest',
    'gemini-3-flash-preview',
    'gemini-flash-latest',
  ];

  GeminiProxy({
    http.Client? client,
    String? Function()? apiKeyProvider,
    List<String>? models,
    this.requestTimeout = const Duration(seconds: 30),
    Duration Function(int attempt)? retryDelay,
  })  : _client = client ?? http.Client(),
        _apiKeyProvider = apiKeyProvider ?? _readApiKeyFromEnvironment,
        models = models ?? defaultModels,
        retryDelay = retryDelay ?? ((attempt) => Duration(milliseconds: attempt * 1500));

  static String? _readApiKeyFromEnvironment() => Platform.environment['GEMINI_API_KEY'];

  String? get _apiKey {
    final key = _apiKeyProvider();
    if (key == null) return null;
    final trimmed = key.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool get isConfigured => _apiKey != null;

  /// Calls Gemini and returns the raw model text (a JSON string).
  Future<String> extractText({
    required String imageBase64,
    required String mimeType,
    required int pageNumber,
  }) async {
    final apiKey = _apiKey;
    if (apiKey == null) {
      throw const GeminiProxyException(
        503,
        'OCR_NOT_CONFIGURED',
        'Cloud OCR is not configured on the server.',
      );
    }
    if (!allowedMimeTypes.contains(mimeType)) {
      throw const GeminiProxyException(400, 'BAD_MIME', 'Unsupported image type.');
    }
    if (pageNumber < 0 || pageNumber > 2) {
      throw const GeminiProxyException(400, 'BAD_PAGE', 'pageNumber must be 0, 1 or 2.');
    }
    if (imageBase64.isEmpty || imageBase64.length > maxImageBase64Chars) {
      throw const GeminiProxyException(413, 'BAD_IMAGE', 'Image is missing or too large.');
    }

    final payload = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': buildPrompt(pageNumber)},
            {
              'inline_data': {'mime_type': mimeType, 'data': imageBase64},
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.1,
        'response_mime_type': 'application/json',
      },
    });

    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': apiKey,
    };

    final response = await _sendWithRetryAndFailover(headers, payload);
    if (response.statusCode != 200) {
      // Log status only. Never forward the upstream body to the caller.
      print('! [ocr] Gemini upstream status ${response.statusCode}');
      if (response.statusCode == 429 || response.statusCode == 503) {
        throw const GeminiProxyException(503, 'OCR_BUSY', 'Cloud OCR is busy. Please retry shortly.');
      }
      throw const GeminiProxyException(502, 'OCR_UPSTREAM', 'Cloud OCR provider error.');
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = json['candidates'] as List<dynamic>?;
      final content = (candidates != null && candidates.isNotEmpty)
          ? (candidates[0] as Map<String, dynamic>)['content'] as Map<String, dynamic>?
          : null;
      final parts = content?['parts'] as List<dynamic>?;
      final text = (parts != null && parts.isNotEmpty)
          ? (parts[0] as Map<String, dynamic>)['text'] as String?
          : null;
      if (text == null || text.trim().isEmpty) {
        throw const GeminiProxyException(502, 'OCR_EMPTY', 'Cloud OCR returned no result.');
      }
      return text;
    } on GeminiProxyException {
      rethrow;
    } catch (_) {
      throw const GeminiProxyException(502, 'OCR_PARSE', 'Cloud OCR returned an unreadable result.');
    }
  }

  Future<http.Response> _sendWithRetryAndFailover(
    Map<String, String> headers,
    String body,
  ) async {
    http.Response? lastResponse;
    Object? lastError;

    for (final model in models) {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
      );
      var attempts = 0;
      while (attempts < 2) {
        attempts++;
        try {
          final res = await _client.post(uri, headers: headers, body: body).timeout(requestTimeout);
          if (res.statusCode == 200) return res;
          lastResponse = res;
          if (res.statusCode == 503 || res.statusCode == 429) {
            if (attempts < 2) {
              await Future<void>.delayed(retryDelay(attempts));
              continue;
            }
            break; // fail over to next model
          }
          return res; // other 4xx/5xx: do not fail over
        } catch (e) {
          lastError = e;
          if (attempts < 2) {
            await Future<void>.delayed(retryDelay(attempts));
            continue;
          }
          break;
        }
      }
    }

    if (lastResponse != null) return lastResponse;
    print('! [ocr] Gemini network failure: ${lastError.runtimeType}');
    throw const GeminiProxyException(502, 'OCR_NETWORK', 'Cloud OCR provider is unreachable.');
  }

  /// Prompt tailored to the Nepal MoHP Gynecological Camp Yellow Form.
  String buildPrompt(int pageNumber) {
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
   - "PATIENT TOKEN ID / बिरामी टोकन नं." (or अस्पताल दर्ता नं.) format: e.g. "KTM01-0001" or QR code string
2. Section A: Patient Demographics / बिरामी विवरण:
   - "First Name: पहिलो नाम" (letter boxes)
   - "Surname: थर" (letter boxes)
   - "Patient Age: उमेर" (numeric digit boxes)
   - "Marital Status / वैवाहिक स्थिति" (4 checkboxes: Married, Widow, Unmarried, Divorced)
   - "Husband's / Father's Name: श्रीमान् / बुबाको नाम" (letter boxes -> relativeName)
   - "Mobile No.: मोबाइल नम्बर" (10 digit boxes)
   - "Age at Marriage: विवाह भएको उमेर" (numeric digit boxes -> maritalAge)
   - "Contact Person (Secondary): सम्पर्क व्यक्ति" (letter boxes -> contactPerson)
   - "Contact Mobile No.: सम्पर्क मोबाइल नम्बर" (10 digit boxes -> contactMobile)
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
     - "Highest Stage: [ ]" (0 to 4, or auto-derived from max of Anterior, Middle, Posterior)
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
7. Station 6: Discharge & Continuity of Care / अनुगमन तथा निरन्तर हेरचाह:
   - "Follow-up Required:" [ ] Yes (Follow-up Needed) [ ] No (Routine)
   - "Follow-up Destination:" (handwritten line text)
   - "Surgical Referral:" [ ] None [ ] Scheer Memorial Hospital [ ] Model Hospital [ ] Local Government Hospital
   - "Clinical Notes:" (multi-line handwritten remarks)
8. Page 2 Footer / Examining Clinician Sign-off:
   - Look for the Examining Doctor section / checkboxes: e.g. "[ ] Dr. Sita [ ] Dr. Gita" or signed doctor name under "Medical Officer / Gynecologist"
   - Extract the identified/checked doctor name into "examiningDoctor" (e.g. "Dr. Sita Karki").

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
  "examiningDoctor": "Examining doctor name or checked doctor checkbox on Page 2 or null",
  "clinicalNotes": "Clinical notes written in Station 6",
  "rawSummary": "A concise summary of all visible handwriting and marked fields on the page."
}

Do NOT output markdown blocks or conversational text. Output ONLY the raw JSON object.
''';
  }

  void dispose() => _client.close();
}
