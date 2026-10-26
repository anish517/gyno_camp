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
        'responseMimeType': 'application/json',
      },
    });

    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': apiKey,
    };

    final response = await _sendWithRetryAndFailover(headers, payload);
    if (response.statusCode != 200) {
      // Log status AND upstream body for debugging.
      print('! [ocr] Gemini upstream status ${response.statusCode}');
      final errBody = response.body.length > 500 ? response.body.substring(0, 500) : response.body;
      print('! [ocr] Upstream body: $errBody');
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
          if (res.statusCode == 503 || res.statusCode == 429 || res.statusCode == 404) {
            if (attempts < 2) {
              await Future<void>.delayed(retryDelay(attempts));
              continue;
            }
            break; // fail over to next model
          }
          print('! [ocr] Model $model returned ${res.statusCode} — not retryable');
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

CRITICAL RULES:
- The Yellow Form is a standardized 2-page intake instrument. Do NOT invent, assume, or hallucinate fields that are not printed on the physical form.
- Specifically: There is NO caste, NO education, NO occupation, NO gravida, NO respiratory rate, NO temperature, NO weight, and NO height on this form.
- Extract ONLY the actual printed fields, checkboxes, letter boxes, and handwritten entries.
- If a tick-box or value is blank, unreadable, or not filled in, return null for that field. NEVER guess or invent values.
- For integer fields: return null (NOT 0) if the field is blank or unreadable.
- For string fields: return null (NOT empty string) if the field is blank or unreadable.
- For boolean fields: return null if the checkbox area is blank or ambiguous.
- DATE RECOGNITION RULES (NEPALI BIKRAM SAMBAT BS):
  * Date fields across both pages have segmented digit boxes: "Date / मिति: [YYYY] - [MM] - [DD] BS".
  * The 4-digit Year is in Bikram Sambat (typically 2083, or between 2080-2085 BS).
  * The 2-digit Month ranges from 01 (Baisakh) to 12 (Chaitra).
  * CRITICAL: Distinguishing digit 7 vs digit 1 in month boxes:
    - Look carefully at the second box in the month pair [0][X].
    - In handwritten Nepali dates, digit '7' has a distinct horizontal top bar extending across to the right before descending down at an angle. If there is a horizontal top stroke spanning across the box, it is digit '7' (Month 07 = Kartik / कार्तिक, the primary autumn camp season), NEVER '1'!
    - Digit '1' is a single vertical or slightly slanted stroke without a horizontal top bar.
  * CROSS-STATION ENCOUNTER CONSISTENCY:
    - On a single patient Yellow Form encounter, all stations occur on the SAME camp date!
    - Page 1 "Date / मिति" (intakeDate) and Page 2 dates ("Examination Date", "Lab test Date", "Conclusion Date", "Treatment Date", "Outtake Date") share the exact same date (e.g. 2083-07-06).
    - If multiple station dates agree on a month (e.g., month 07), ensure all station dates reflect this confirmed month.

FORM STRUCTURE BY PAGE:

PAGE 1 (FRONT) — PATIENT REGISTRATION & ANAMNESIS:
1. Header:
   - "PATIENT TOKEN ID / बिरामी टोकन नं." (or Token: G C - 1 1 - 2 0 2 6 - 0 0 0 1 7) -> patientTokenId
   - "Date / मिति" -> intakeDate (format YYYY-MM-DD, e.g. 2083-07-06; inspect individual boxes [YYYY] - [MM] - [DD] BS carefully)
   - "Level of Treatment / उपचारको तह" (2 checkboxes: [ ] Council level / काउन्सिलिङ तह, [ ] Full check up / पूर्ण जाँच) -> treatmentLevel: "counseling" or "gyno_checkup"
2. Section A: Patient Demographics / बिरामी विवरण:
   - "First Name: पहिलो नाम" (letter boxes)
   - "Surname: थर" (letter boxes)
   - "Patient Age: उमेर" (numeric digit boxes)
   - "Marital Status / वैवाहिक स्थिति" (4 checkboxes: Married, Unmarried, Widow, Divorced)
   - "Relative Name: आपन्तको नाम" (letter boxes -> relativeName, e.g. BHIM BAHADUR)
   - "Relative Surname: थर" (letter boxes directly to the right of Relative Name -> relativeSurname, e.g. THAPA)
   - "Relation: नाता" -> relationType: "Husband" or "Father" (from checked checkbox)
   - "Mobile W.: महिलाको मोबाइल" (10 digit boxes -> mobile)
   - "Age at Marriage / विवाह उमेर" (numeric digit boxes -> maritalAge)
   - "Contact Person / सम्पर्क व्यक्ति" (letter boxes -> contactPerson)
   - "Contact Mobile / सम्पर्क मोबाइल" (10 digit boxes -> contactMobile)
   - "District / जिल्ला" (letter boxes)
   - "Province / प्रदेश" (letter boxes)
   - "Palika / गाउँ / न.पा." (letter boxes -> municipality)
   - "Ward / वडा" (digit boxes -> ward)
3. Section B: Reasons for Visit & Consent / शिविरमा आउनुको कारण तथा सहमति:
   - Reasons for visit (8 exact checkboxes):
     - "Something Hanging Out / Prolapse (पाठेघर खस्ने)"
     - "Vaginal Discharge / Itching (योनी स्राव / चिलाउने)"
     - "Problems Passing Urine (पिसाब सम्बन्धी समस्या)"
     - "Problems Passing Stool (दिसा सम्बन्धी समस्या)"
     - "Menstrual Problem (महिनावारी सम्बन्धी समस्या)"
     - "Infertility (बाँझोपन)"
     - "Pelvic / Abdominal Pain (तल्लो पेट / कम्मर दुखाई)"
     - "General Gynaecological Checkup (सामान्य जाँच)"
   - Patient Consent:
     - "Consent for Treatment / उपचारको लागि सहमति:" [ ] YES [ ] NO -> consentTreatment: bool
     - "Consent for Storage / स्वास्थ्य विवरण सहमति:" [ ] YES [ ] NO -> consentStoreMedicalInfo: bool
4. Station 1: Anamnesis & Obstetric History / पहिलो स्टेशन: विगत तथा प्रसूति विवरण (ON PAGE 1 FRONT):
   - "NR deliveries:" [ ] (deliveries)
   - "NR living children:" [ ] (livingChildren)
   - "NR abortion:" [ ] (abortions)
   - Clinical Complaints rows:
     - "something hanging out (पाठेघर खस्ने)": since when: [ ] < 1month [ ] < 1 year [ ] > 1 year [ ] > 5 years [ ] > 10 years, previous treatment: [ ] pessary [ ] surgery, remarks
     - "discharge / itching (पानी बग्ने / चिलाउने)": since when: [ ] < 1month [ ] < 1 year [ ] > 1 year [ ] > 5 years [ ] > 10 years, colour: [ ] white [ ] yellow [ ] green [ ] grey [ ] smelly, remarks
     - "problems passing urine (पिसाब समस्या)": since when: [ ] < 1month [ ] < 1 year [ ] > 1 year [ ] > 5 years [ ] > 10 years, type incontinence: [ ] stress [ ] urge [ ] continuous flow, remarks
     - "problems passing stool (दिसा समस्या)": since when, remarks
     - "menstrual problem (महिनावारी समस्या)": [ ] dysmenorrhoea [ ] metrorrhagia [ ] menorrhagia [ ] postmenopausal bleeding, remarks
     - "infertility (निःसन्तान समस्या)": since when: [ ] > 1 year [ ] > 5 years [ ] > 10 years, remarks
     - "lower abdomen pain (तल्लो पेट दुख्ने)": since when: [ ] < 1month [ ] < 1 year [ ] > 1 year [ ] > 5 years [ ] > 10 years, remarks
     - "lower back pain (कम्मर / ढाड दुख्ने)": since when: [ ] < 1month [ ] < 1 year [ ] > 1 year [ ] > 5 years [ ] > 10 years, remarks
     - "checkup (सामान्य जाँच)": [ ] routine screening, remarks

PAGE 2 (BACK) — CLINICAL ASSESSMENT & EXAMINATION (STATIONS 2-6):
1. Station 2: POP & Physical Examination / शारीरिक जाँच तथा पाठेघर खस्ने अवस्था:
   - "Examination Date:" -> examDate (format YYYY-MM-DD from boxes [YYYY]-[MM]-[DD] BS, e.g. 2083-07-06)
   - "uterus inside:" (2 checkboxes: [ ] yes  [ ] no -> uterusInside: true if yes is ticked, false if no)
   - "pelvic floor muscle:" (3 checkboxes: [ ] normal  [ ] weak  [ ] hypertonic -> pelvicFloorTone: string)
   - "vulva": [ ] normal checkbox OR handwritten text — report "normal" if normal checkbox is ticked, otherwise handwritten text
   - "vagina": [ ] normal checkbox OR handwritten text — report "normal" if normal checkbox is ticked, otherwise handwritten text
   - "cervix": [ ] normal checkbox OR handwritten text — report "normal" if normal checkbox is ticked, otherwise handwritten text
   - "uterus": [ ] normal checkbox OR handwritten text — report "normal" if normal checkbox is ticked, otherwise handwritten text
   - POP STAGING RULES (CRITICAL CHECKBOX & COLUMN ALIGNMENT):
     In Station 2 and Station 4, examine the horizontal checkbox rows and their vertical column alignment:
     Notice every checkbox is placed BEFORE its text label:
     * "POP anterior wall:": [ ] stage 0  [ ] stage 1  [ ] stage 2  [ ] stage 3 -> report which stage number (0-3) has the checkmark.
     * "POP middle part:": [ ] stage 0  [ ] stage 1  [ ] stage 2  [ ] stage 3  [ ] stage 4 -> report which stage number (0-4) has the checkmark. Look carefully at which box has the tick.
     * "POP posterior wall:": [ ] stage 0  [ ] stage 1  [ ] stage 2  [ ] stage 3 -> report which stage number (0-3) has the checkmark. Look carefully at which box has the tick.
     Verify the vertical column alignment between the rows:
     - Notice if "POP anterior wall" and "POP middle part" are both checked in the "stage 2" column, report 2 for both (anteriorStage: 2, middleStage: 2).
     - Notice if "POP posterior wall" is checked in the "stage 1" column (shifted to the left under stage 1), report 1 for posterior wall (posteriorStage: 1), NOT 2!
     - Report each wall's stage strictly according to its own row's checked box.
2. Station 3: Point-of-Care Labs, Vitals & ECG / प्रयोगशाला, सूचक तथा ईसीजी:
   - "Lab test Date:" -> labTestDate (format YYYY-MM-DD from boxes [YYYY]-[MM]-[DD] BS, e.g. 2083-07-06)
   - "urine test:" (Checkboxes: [ ] normal  [ ] pos)
   - "pregnancy test:" (Checkboxes: [ ] neg  [ ] pos)
   - "blood pressure:" [ systolic ] / [ diastolic ] mmHg
   - "pulse:" [ ] bpm, "SpO2:" [ ] %, "blood glucose:" [ ] mg/dL
   - "ECG:" (Checkboxes: [ ] Normal Sinus  [ ] Abnormal  [ ] Not Done, and handwritten "ECG Notes")
3. Station 4: Confirmed Diagnoses / निदान:
   - "Conclusion Date:" -> conclusionDate (format YYYY-MM-DD from boxes [YYYY]-[MM]-[DD] BS, e.g. 2083-07-06)
   - "highest POP stage:" in Station 4: [ ] stage 0  [ ] stage 1  [ ] stage 2  [ ] stage 3  [ ] stage 4 -> report which stage number (0-4) has the checkmark (e.g. 2).
   - Checkboxes: "atrophy vagina", "bacterial vaginosis", "candid infection", "trichomonas",
     "PID", "cervicitis", "cervical polyp", "cervical carcinoma", "condylomata", "fistula",
     "infertility", "myoma", "cystitis", "lichen sclerosis", "stress incontinence", "ovarian tumor",
     "urge incontinence", "menstrual disorder", "weak pelvic floor muscle", "pregnancy",
     "hypertonic pelvic floor muscle", and handwritten text under "Other:"
4. Station 5: Treatment & Prescriptions / उपचार तथा औषधि:
   - "Treatment Date:" -> treatmentDate (format YYYY-MM-DD from boxes [YYYY]-[MM]-[DD] BS, e.g. 2083-07-06)
   - "spec counseling" (5 checkboxes): "weak pelvic floor", "POP", "stress incontinence", "urge incontinence", "abdominal pain"
   - "pessary" (3 checkboxes): "ring", "ring with support", "ring with knob", "size: [   ]" mm
   - IMPORTANT: Pessary is a DEVICE fitting, NOT a dispensed medication. Do NOT include pessary in the medications list.
   - "referral surgery" (3 checkboxes): "Scheer Memorial", "Model Hosp", "loc government"
   - "medication" (10 checkboxes): "clotrimazol (canesten)", "estradiol crème", "metronidazol", "doxycycline", "azithromycin", "nitrofurantoine", "medroxyprogesterone", "ciproflox", "mirasin", "clobetasol", and handwritten text under "other medication:"
5. Station 6: Discharge & Continuity of Care / अनुगमन तथा डिस्चार्ज:
   - "Outtake Date:" -> outtakeDate (format YYYY-MM-DD from boxes [YYYY]-[MM]-[DD] BS, e.g. 2083-07-06)
   - "follow up:" (checkboxes: "Health Post", "GynaeSupport Nurse", "Hospital", "no follow up needed")
   - Clinical Notes / Outtake Remarks -> clinicalNotes
6. Page 2 Footer / Examining Clinician Sign-off:
   - "Attending Nurse (Tick on Paper):" checked box or handwritten nurse name
   - "Examining Doctor (Tick on Paper):" checked box or handwritten doctor name
   - IMPORTANT: The follow-up destination "GynaeSupport Nurse" is NOT an attending nurse. Never put it into examiningNurse or attendingNurses.

Extract the information accurately into this EXACT JSON structure:
{
  "pageNumber": ${pageNumber == 0 ? '1 or 2' : pageNumber},
  "treatmentLevel": "counseling or gyno_checkup or null (from Level of Treatment checkbox on Page 1)",
  "intakeDate": "Date from Page 1 header in YYYY-MM-DD format or null",
  "examDate": "Examination Date from Page 2 header in YYYY-MM-DD format or null",
  "labTestDate": "Lab/Station 3 date in YYYY-MM-DD format or null",
  "conclusionDate": "Conclusion/Station 4 date in YYYY-MM-DD format or null",
  "treatmentDate": "Treatment/Station 5 date in YYYY-MM-DD format or null",
  "outtakeDate": "Outtake/Station 6 date in YYYY-MM-DD format or null",
  "demographics": {
    "patientTokenId": "Token or registration ID (e.g. GC-KTM01-2026-001 or KTM01-0001) or null",
    "firstName": "First name of patient (e.g. MAYA) or null",
    "surname": "Surname (e.g. TAMANG) or null",
    "age": number or null,
    "maritalStatus": "married or widow or unmarried or divorced or null",
    "relativeName": "Relative first name from 'Relative Name: आपन्तको नाम' letter boxes (e.g. BHIM BAHADUR) or null",
    "relativeSurname": "Relative surname from 'Relative Surname: थर' letter boxes directly adjacent (e.g. THAPA) or null",
    "relationType": "Husband or Father or null (from checked 'Relation: नाता' checkbox)",
    "mobile": "10-digit phone number or null",
    "maritalAge": number or null,
    "contactPerson": "Secondary contact person name or null",
    "contactMobile": "10-digit contact phone number or null",
    "province": "Province name (e.g. BAGMATI) or null",
    "district": "District name (e.g. KATHMANDU) or null",
    "municipality": "Palika or municipality name (e.g. BUDHANILKANTHA) or null",
    "ward": "Ward number (e.g. 04) or null",
    "reasonsForVisit": ["List of checked visit reasons from Section B, use EXACT keys: something hanging out, discharge and or itching, problems passing urine, problems passing stool, menstrual problem, infertility, pain, checkup"],
    "consentTreatment": true or false or null,
    "consentStoreMedicalInfo": true or false or null
  },
  "obstetrics": {
    "deliveries": number or null,
    "livingChildren": number or null,
    "abortions": number or null,
    "complaintsDuration": "< 1month or < 1 year or > 1 year or > 5 years or > 10 years or null",
    "clinicalComplaints": ["Checked complaints from Station 1 using EXACT keys: prolapse, discharge, urine, stool, menstrual, infertility, lower_abdomen_pain, lower_back_pain, checkup"],
    "complaintDetails": [
      {
        "complaint": "EXACT key from clinicalComplaints (e.g. prolapse, discharge, etc.)",
        "subOptions": ["checked sub-option values for this complaint"],
        "duration": "duration if applicable (e.g. > 1 year) or null",
        "remarks": "handwritten remarks for this complaint or null"
      }
    ]
  },
  "popStaging": {
    "uterusInside": true or false or null,
    "pelvicFloorTone": "normal or weak or hypertonic or null",
    "anteriorStage": number (0-3) or null,
    "middleStage": number (0-4) or null,
    "posteriorStage": number (0-3) or null,
    "highestPopStage": number (0-4) or null,
    "vulvaRemarks": "normal (if checkbox ticked) or handwritten text or null",
    "cervixRemarks": "normal (if checkbox ticked) or handwritten text or null",
    "vaginaRemarks": "normal (if checkbox ticked) or handwritten text or null",
    "uterusRemarks": "normal (if checkbox ticked) or handwritten text or null"
  },
  "vitals": {
    "systolicBp": number or null,
    "diastolicBp": number or null,
    "pulseRate": number or null,
    "spo2": number or null,
    "bloodGlucose": number or null,
    "urineTest": "normal or pos or null",
    "pregnancyTest": "neg or pos or null",
    "ecg": "Normal Sinus or Abnormal or Not Done or null",
    "ecgNotes": "ECG remarks / handwritten notes or null"
  },
  "diagnoses": ["List of checked diagnoses from Station 4, plus Other text if filled. Empty list if none checked."],
  "counseling": ["List of checked spec counseling options from Station 5. Empty list if none checked."],
  "medications": ["List of checked medications ONLY from Station 5 medication section, plus Other text if filled. Do NOT include standalone dosage instructions (e.g. '1 TAB DAILY', 'OD', 'BD'). Do NOT include pessary here. Empty list if none checked."],
  "ringPessary": true or false,
  "pessaryType": "ring or ring with support or ring with knob or null",
  "ringPessarySize": number or null,
  "followUpNeeded": true or false or null,
  "followUpDestination": "Health Post or GynaeSupport Nurse or null",
  "surgicalReferral": "Scheer Memorial or Model Hosp or loc government or null",
  "examiningDoctor": "Examining doctor name or checked doctor checkbox on Page 2 or null",
  "attendingDoctors": ["All checked or written doctor names on Page 2, empty list if none"],
  "examiningNurse": "Main attending nurse name (checked checkbox or handwritten) on Page 2 or null",
  "attendingNurses": ["All checked or written attending nurse names on Page 2, empty list if none"],
  "clinicalNotes": "Clinical notes / remarks written in Station 6 outtake section or null",
  "rawSummary": "A concise summary of all visible handwriting and marked fields on the page."
}

Do NOT output markdown blocks or conversational text. Output ONLY the raw JSON object.
''';
  }

  void dispose() => _client.close();
}
