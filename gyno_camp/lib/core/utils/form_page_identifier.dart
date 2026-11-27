import '../../models/ocr_scan_result_model.dart';
import '../../models/patient_model.dart';

/// Parsed Form/Token Number + Page Identity (Page 1 Front vs Page 2 Back)
/// from QR payloads (`00101|P1`, `BLANK|P2`), printed header tags (`00101 • P1`,
/// `00101-P2`), filenames, or OCR text.
class FormPageIdentity {
  /// Normalized Patient / Form Token ID (e.g. `'00101'` or `'GC-KTM01-2026-00101'`),
  /// or `null` if un-numbered / blank.
  final String? formNumber;

  /// `1` for Page 1 (Front), `2` for Page 2 (Back), or `null` when unknown.
  final int? pageNumber;

  const FormPageIdentity({
    this.formNumber,
    this.pageNumber,
  });

  bool get hasFormNumber => formNumber != null && formNumber!.trim().isNotEmpty;
  bool get hasPageNumber => pageNumber == 1 || pageNumber == 2;

  /// Canonical combined code (e.g. `'00101-P1'`, `'P2'`, `'00101'`, or `''`).
  String get formattedCode {
    if (hasFormNumber && hasPageNumber) {
      return '$formNumber-P$pageNumber';
    }
    if (hasFormNumber) return formNumber!;
    if (hasPageNumber) return 'P$pageNumber';
    return '';
  }

  /// Builds the QR payload printed on Yellow Form Page [page] (`1` or `2`).
  /// Uses `<token>|P1` / `<token>|P2` for numbered forms, and `BLANK|P1` / `BLANK|P2`
  /// for un-numbered blank forms so `|` splitting stays backward-compatible with
  /// existing QR token scanners.
  static String buildQrPayload({
    String? tokenId,
    required int pageNumber,
  }) {
    final safePage = pageNumber == 2 ? 2 : 1;
    final cleanToken = (tokenId ?? '').trim();
    if (cleanToken.isEmpty) {
      return 'BLANK|P$safePage';
    }
    return '$cleanToken|P$safePage';
  }

  /// Parses a QR string, `formPageCode`, token string, or header snippet into
  /// a normalized [FormPageIdentity].
  static FormPageIdentity parse(
    String? raw, {
    String campCode = '',
    int? year,
  }) {
    if (raw == null || raw.trim().isEmpty) {
      return const FormPageIdentity();
    }

    var text = _devanagariToAscii(raw).trim();
    if (text.toLowerCase() == 'null') {
      return const FormPageIdentity();
    }

    int? detectedPage;
    String tokenCandidate = text;

    // 1. Pipe-delimited QR payloads: "00101|P1", "BLANK|P2", "00101|2026-11-27|P1"
    if (text.contains('|')) {
      final parts = text.split('|').map((s) => s.trim()).toList();
      tokenCandidate = parts.first;
      for (final seg in parts.skip(1)) {
        final pMatch = RegExp(
          r'^(?:PAGE\s*|P\s*)?([12])$',
          caseSensitive: false,
        ).firstMatch(seg);
        if (pMatch != null) {
          detectedPage = int.tryParse(pMatch.group(1)!);
          break;
        }
      }
    }

    // 2. Suffix / prefix page markers in combined codes:
    //    "00101-P1", "00101 • P2", "00101 / P1", "00101 (Page 2)", "P1-00101", "BLANK-P2"
    final suffixPageMatch = RegExp(
      r'^(.*?)[\s•·\-_:/\(]+(?:PAGE\s*|PG\s*|P\s*)([12])(?:\s*(?:OF\s*2|/2))?\)?\s*$',
      caseSensitive: false,
    ).firstMatch(tokenCandidate);
    if (suffixPageMatch != null) {
      detectedPage ??= int.tryParse(suffixPageMatch.group(2)!);
      tokenCandidate = suffixPageMatch.group(1)!.trim();
    } else {
      final prefixPageMatch = RegExp(
        r'^(?:PAGE\s*|PG\s*|P\s*)([12])[\s•·\-_:]+(.+)$',
        caseSensitive: false,
      ).firstMatch(tokenCandidate);
      if (prefixPageMatch != null) {
        detectedPage ??= int.tryParse(prefixPageMatch.group(1)!);
        tokenCandidate = prefixPageMatch.group(2)!.trim();
      } else if (RegExp(
        r'^(?:BLANK[\s\-_|•]*)?(?:PAGE\s*|PG\s*|P\s*)([12])$',
        caseSensitive: false,
      ).hasMatch(tokenCandidate)) {
        final onlyPage = RegExp(
          r'([12])$',
        ).firstMatch(tokenCandidate);
        detectedPage ??= int.tryParse(onlyPage?.group(1) ?? '');
        tokenCandidate = '';
      }
    }

    // Treat explicit BLANK placeholder as un-numbered
    if (tokenCandidate.trim().toUpperCase() == 'BLANK') {
      tokenCandidate = '';
    }

    final normalizedForm = tokenCandidate.isEmpty
        ? ''
        : PatientModel.normalizePatientId(
            rawInput: tokenCandidate,
            campCode: campCode,
            year: year,
          );

    return FormPageIdentity(
      formNumber: normalizedForm.isNotEmpty ? normalizedForm : null,
      pageNumber: detectedPage,
    );
  }

  /// Parses filename conventions (e.g. `00101_page2.jpg`, `form_00101_p1.png`,
  /// `yellow_form_sample_page2.jpg`, `front.jpg`, `back.jpg`) as a lightweight
  /// offline hint when available.
  static FormPageIdentity parseFromFilePath(String? path) {
    if (path == null || path.trim().isEmpty) {
      return const FormPageIdentity();
    }
    // Strip directory and extension
    final baseName = path
        .split(RegExp(r'[/\\]'))
        .last
        .replaceFirst(RegExp(r'\.[A-Za-z0-9]{2,5}$'), '');
    final lower = baseName.toLowerCase();

    int? page;
    if (RegExp(r'(?:^|[_\-\s\.])(?:page\s*1|pg\s*1|p1|front)(?:$|[_\-\s\.])')
        .hasMatch(lower)) {
      page = 1;
    } else if (RegExp(
      r'(?:^|[_\-\s\.])(?:page\s*2|pg\s*2|p2|back)(?:$|[_\-\s\.])',
    ).hasMatch(lower)) {
      page = 2;
    }

    String? formNumber;
    // Only extract explicit 5-digit form tokens (00001..99999) or GC-... tokens from filenames,
    // avoiding generic camera timestamps like IMG_20261127_120000 or random UUIDs.
    final gcMatch = RegExp(
      r'(GC-[A-Za-z0-9]+-\d{4}-\d{5})',
      caseSensitive: false,
    ).firstMatch(baseName);
    if (gcMatch != null) {
      final norm = PatientModel.normalizePatientId(rawInput: gcMatch.group(1)!);
      if (norm.isNotEmpty) formNumber = norm;
    } else {
      final fiveDigitMatches = RegExp(
        r'(?:^|[_\-\s])(\d{5})(?:$|[_\-\s])',
      ).allMatches(baseName).toList();
      if (fiveDigitMatches.length == 1) {
        final candidate = fiveDigitMatches.first.group(1)!;
        final norm = PatientModel.normalizePatientId(rawInput: candidate);
        if (norm.isNotEmpty) formNumber = norm;
      }
    }

    return FormPageIdentity(formNumber: formNumber, pageNumber: page);
  }

  /// Infers whether an [OcrScanResultModel] represents Page 1 (Front) or Page 2 (Back)
  /// using explicit `detectedPage` / `formPageCode` metadata combined with
  /// unmistakable Page-1-exclusive vs Page-2-exclusive clinical field signatures.
  static int? inferPageNumber(OcrScanResultModel scan) {
    int p1Score = 0;
    int p2Score = 0;

    final demo = scan.demographics;
    final obs = scan.obstetrics;
    final vitals = scan.vitals;
    final pop = scan.popStaging;

    bool hasStr(dynamic v) {
      final s = v?.toString().trim() ?? '';
      return s.isNotEmpty && s.toLowerCase() != 'null';
    }

    // ── Page 1 (Front) exclusive signals ──
    if (hasStr(demo['firstName'])) p1Score += 3;
    if (hasStr(demo['surname'])) p1Score += 3;
    if (demo['age'] is int && (demo['age'] as int) > 0) p1Score += 2;
    if (hasStr(demo['mobile'])) p1Score += 2;
    if (hasStr(demo['municipality']) || hasStr(demo['district'])) p1Score += 2;
    if (hasStr(demo['relativeName']) || hasStr(demo['maritalStatus'])) {
      p1Score += 2;
    }
    if (demo['reasonsForVisit'] is List &&
        (demo['reasonsForVisit'] as List).isNotEmpty) {
      p1Score += 3;
    }
    if (hasStr(scan.treatmentLevel)) p1Score += 2;
    if (obs['deliveries'] != null ||
        obs['livingChildren'] != null ||
        obs['abortions'] != null) {
      p1Score += 3;
    }
    if (obs['clinicalComplaints'] is List &&
        (obs['clinicalComplaints'] as List).isNotEmpty) {
      p1Score += 3;
    }
    if (hasStr(scan.anamnesisDate)) p1Score += 2;

    final rawUpper = scan.rawText.toUpperCase();
    if (rawUpper.contains('PAGE 1 (FRONT)') ||
        rawUpper.contains('PATIENT REGISTRATION & ANAMNESIS') ||
        rawUpper.contains('SECTION A: PATIENT DEMOGRAPHICS')) {
      p1Score += 4;
    }

    // ── Page 2 (Back) exclusive signals ──
    if (vitals['systolicBp'] != null || vitals['diastolicBp'] != null) {
      p2Score += 3;
    }
    if (vitals['pulseRate'] != null ||
        vitals['pulse'] != null ||
        vitals['spo2'] != null ||
        vitals['bloodGlucose'] != null ||
        vitals['glucose'] != null) {
      p2Score += 2;
    }
    if (hasStr(vitals['urineTest']) ||
        hasStr(vitals['pregnancyTest']) ||
        hasStr(vitals['ecg'])) {
      p2Score += 2;
    }
    if (pop['uterusInside'] != null || hasStr(pop['pelvicFloorTone'])) {
      p2Score += 3;
    }
    if (pop['anteriorStage'] != null ||
        pop['middleStage'] != null ||
        pop['posteriorStage'] != null ||
        pop['highestPopStage'] != null) {
      p2Score += 4;
    }
    if (scan.diagnoses.isNotEmpty) p2Score += 4;
    if (scan.medications.isNotEmpty) p2Score += 4;
    if (scan.counseling.isNotEmpty) p2Score += 2;
    if (scan.ringPessary ||
        hasStr(scan.pessaryType) ||
        scan.ringPessarySize != null) {
      p2Score += 3;
    }
    if (hasStr(scan.surgicalReferral) || hasStr(scan.followUpDestination)) {
      p2Score += 2;
    }
    if (hasStr(scan.examiningDoctor) ||
        scan.attendingDoctors.isNotEmpty ||
        hasStr(scan.examiningNurse) ||
        scan.attendingNurses.isNotEmpty) {
      p2Score += 2;
    }
    if (hasStr(scan.examDate) ||
        hasStr(scan.labTestDate) ||
        hasStr(scan.conclusionDate) ||
        hasStr(scan.treatmentDate) ||
        hasStr(scan.outtakeDate)) {
      p2Score += 2;
    }
    if (rawUpper.contains('PAGE 2 (BACK)') ||
        rawUpper.contains('CLINICAL ASSESSMENT & EXAMINATION') ||
        rawUpper.contains('POP ANTERIOR') ||
        rawUpper.contains('CONFIRMED DIAGNOSES')) {
      p2Score += 4;
    }

    // Check explicit detectedPage / formPageCode first
    int? explicit = scan.detectedPage;
    if (explicit != 1 && explicit != 2) {
      final codeIdentity = parse(demo['formPageCode']?.toString());
      explicit = codeIdentity.pageNumber;
    }

    if (explicit == 1) {
      // Only override explicit=1 if Page 2 clinical signals overwhelmingly dominate and Page 1 has zero
      if (p2Score >= 4 && p1Score == 0) return 2;
      return 1;
    }
    if (explicit == 2) {
      if (p1Score >= 4 && p2Score == 0) return 1;
      return 2;
    }

    if (p1Score > 0 && p2Score == 0) return 1;
    if (p2Score > 0 && p1Score == 0) return 2;
    if (p1Score >= p2Score + 3) return 1;
    if (p2Score >= p1Score + 3) return 2;

    if (scan.pageNumber == 1 || scan.pageNumber == 2) {
      return scan.pageNumber;
    }
    return null;
  }

  /// Extracts the normalized Form / Token Number from an [OcrScanResultModel]
  /// if present on the page (returns `null` when blank/unfilled).
  static String? extractFormNumber(
    OcrScanResultModel scan, {
    String campCode = '',
  }) {
    final demo = scan.demographics;
    final rawCandidates = <String?>[
      demo['formPageCode']?.toString(),
      demo['patientTokenId']?.toString(),
      demo['patientId']?.toString(),
    ];
    for (final c in rawCandidates) {
      if (c == null || c.trim().isEmpty) continue;
      final parsed = parse(c, campCode: campCode);
      if (parsed.hasFormNumber) return parsed.formNumber;
    }
    return null;
  }

  static String _devanagariToAscii(String input) {
    const dev = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];
    var out = input;
    for (int i = 0; i < dev.length; i++) {
      out = out.replaceAll(dev[i], i.toString());
    }
    return out;
  }
}
