import 'dart:io';
import 'dart:math';
import '../constants/clinical_constants.dart';
import '../constants/nepal_geodata.dart';
import '../../models/nurse_profile.dart';
import '../../models/ocr_scan_result_model.dart';
import '../../models/patient_model.dart';
import 'omr_service.dart';

class OcrFormService {
  const OcrFormService();

  /// Parses raw text extracted from a photographed Yellow Form into structured models.
  ///
  /// This parser is designed to handle MESSY real-world OCR output from handwritten
  /// medical forms, including:
  /// - Broken words across lines
  /// - Extra whitespace and inconsistent separators
  /// - OCR character substitutions (O→0, l→1, etc.)
  /// - Mixed English/Nepali text
  /// - Missing or misspelled labels
  OcrScanResultModel parseFormText(String rawText, {int pageNumber = 0, String? imagePath}) {
    final rawLayoutLines = rawText
        .split(RegExp(r'[\r\n]+'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final text = normalizeOcrText(rawText);
    final confidences = <String, double>{};

    final lines = text.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final lowerText = text.toLowerCase();

    final bool isPage1Only = pageNumber == 1;
    final bool isPage2Only = pageNumber == 2;

    // Optical Mark Recognition (OMR) on image file if available
    Map<String, OmrResult>? page1OmrReasons;
    Map<String, OmrResult>? page1OmrMarital;
    Map<String, OmrResult>? page1OmrTreatmentLevel;
    Map<String, OmrResult>? page2OmrPop;
    Map<String, OmrResult>? page2OmrPopHighest;
    Map<String, OmrResult>? page2OmrDiagnoses;

    if (imagePath != null) {
      try {
        final imgFile = File(imagePath);
        if (imgFile.existsSync()) {
          final bytes = imgFile.readAsBytesSync();
          const omr = OmrService();
          if (!isPage2Only) {
            page1OmrReasons = omr.evaluateImageBytes(bytes, OmrService.page1VisitReasonsBoxes);
            page1OmrMarital = omr.evaluateImageBytes(bytes, OmrService.page1MaritalStatusBoxes);
            page1OmrTreatmentLevel = omr.evaluateImageBytes(bytes, OmrService.page1TreatmentLevelBoxes);
          }
          if (!isPage1Only) {
            page2OmrPop = omr.evaluateImageBytes(bytes, OmrService.page2PopStagingBoxes);
            page2OmrPopHighest = omr.evaluateImageBytes(bytes, OmrService.page2PopHighestBoxes);
            page2OmrDiagnoses = omr.evaluateImageBytes(bytes, OmrService.page2DiagnosesBoxes);
          }
        }
      } catch (_) {
        // Fall back gracefully to OCR text parsing
      }
    }

    int? parseOcrInt(String? raw) {
      if (raw == null) return null;
      final clean = raw
          .replaceAll(RegExp(r'[Oo]'), '0')
          .replaceAll(RegExp(r'[LlI|]'), '1')
          .replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(clean);
    }

    bool isNoiseOrSeparator(String s) {
      final clean = s.replaceAll(RegExp(r'[/\\|:_\-I\s\(\)]'), '');
      if (clean.isEmpty) return true;
      if (RegExp(r'^\(?(?:secondary|optional|required)\)?[:\s]*$', caseSensitive: false).hasMatch(s.trim())) {
        return true;
      }
      return false;
    }

    /// Searches for a value associated with a label across lines.
    String? findValueForLabel(List<String> labels, {bool multiLine = true}) {
      const knownLabelStems = [
        'first name', 'surname', 'last name', 'given name', 'family name',
        'ward', 'age', 'mobile', 'phone', 'contact', 'relative', 'relation',
        'marital', 'palika', 'district', 'province', 'patient name', 'name',
        'deliveries', 'living', 'abortion', 'since', 'duration', 'appearance',
        'cervix', 'vulva', 'vagina', 'uterus', 'notes', 'remarks', 'date',
        'ecg', 'pessary', 'referral', 'follow', 'doctor', 'nurse',
      ];

      int findValidLabelIndex(String lowerLine, String labelLower) {
        int searchFrom = 0;
        while (searchFrom < lowerLine.length) {
          final idx = lowerLine.indexOf(labelLower, searchFrom);
          if (idx == -1) return -1;
          searchFrom = idx + 1;
          if (idx > 0 &&
              RegExp(r'^[a-z0-9]').hasMatch(labelLower) &&
              RegExp(r'[a-z0-9]').hasMatch(lowerLine[idx - 1])) {
            continue;
          }
          final before = lowerLine.substring(0, idx).trimRight();
          if (labelLower == 'surname' && before.endsWith('relative')) continue;
          if (labelLower == 'mobile' && before.endsWith('contact')) continue;
          if (labelLower == 'age' && before.endsWith('marital')) continue;
          return idx;
        }
        return -1;
      }

      final headerStemRegex = RegExp(
        r'\b(?:' + knownLabelStems.map(RegExp.escape).join('|') + r')\b[:\s_]',
        caseSensitive: false,
      );

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final lowerLine = line.toLowerCase();
        for (final label in labels) {
          final labelLower = label.toLowerCase();
          final labelIdx = findValidLabelIndex(lowerLine, labelLower);
          if (labelIdx != -1) {
            final rawGapAfterLabel = line.substring(labelIdx + label.length);
            // If text on the same line is separated by 12+ spaces, it belongs to a neighboring column
            if (multiLine && RegExp(r'^[/:=\-]*[ \t]{12,}').hasMatch(rawGapAfterLabel)) {
              continue;
            }
            final afterLabel = rawGapAfterLabel.trim();
            var afterVal = afterLabel;
            if (afterVal.startsWith('/') && afterVal.contains(':')) {
              afterVal = afterVal.substring(afterVal.indexOf(':') + 1).trim();
            }

            var value = afterVal.replaceFirst(RegExp(r'^[/:=\s\\-]+'), '').trim();
            // Cut off at the next header label on the same line if multiple labels are present
            final nextLabelMatch = headerStemRegex.firstMatch(value);
            if (nextLabelMatch != null) {
              value = value.substring(0, nextLabelMatch.start).trim();
            }

            if (value.isNotEmpty && !_isLabel(value) && !isNoiseOrSeparator(value)) {
              return value;
            }
          }
        }
      }

      // Multi-line 2D layout lookup on pre-collapse rawLayoutLines so character-box column X coordinates stay 100% aligned
      if (multiLine) {
        for (int r = 0; r + 1 < rawLayoutLines.length; r++) {
          final rawLine = rawLayoutLines[r];
          final rawLower = rawLine.toLowerCase();
          for (final label in labels) {
            final labelLower = label.toLowerCase();
            final rawIdx = findValidLabelIndex(rawLower, labelLower);
            if (rawIdx == -1) continue;

            // Check if there was already a non-label inline value on rawLine (within the same column, <12 spaces away)
            final rawAfterGap = rawLine.substring(rawIdx + label.length);
            if (!RegExp(r'^[/:=\-]*[ \t]{12,}').hasMatch(rawAfterGap)) {
              var rawAfter = rawAfterGap.trim();
              if (rawAfter.startsWith('/') && rawAfter.contains(':')) {
                rawAfter = rawAfter.substring(rawAfter.indexOf(':') + 1).trim();
              }
              var inlineVal = rawAfter.replaceFirst(RegExp(r'^[/:=\s\\-]+'), '').trim();
              final inlineNext = headerStemRegex.firstMatch(inlineVal);
              if (inlineNext != null) {
                inlineVal = inlineVal.substring(0, inlineNext.start).trim();
              }
              final normInline = normalizeOcrText(inlineVal).trim();
              if (normInline.isNotEmpty && !_isLabel(normInline) && !isNoiseOrSeparator(normInline)) {
                return normInline;
              }
            }

            final rawNext = rawLayoutLines[r + 1];
            final normNextFull = normalizeOcrText(rawNext).trim();
            if (normNextFull.isEmpty || _isLabel(normNextFull) || isNoiseOrSeparator(normNextFull)) {
              continue;
            }

            final beforeCurrent = rawLine.substring(0, rawIdx);
            final lineAfterCurrent = rawLine.substring(rawIdx + label.length);
            final hasPrevCol = headerStemRegex.hasMatch(beforeCurrent);
            final nextHeaderCol = headerStemRegex.firstMatch(lineAfterCurrent);

            if (hasPrevCol || nextHeaderCol != null) {
              if (rawNext.length <= max(0, rawIdx - 4)) {
                continue;
              }
              final colStart = max(0, rawIdx - 4).clamp(0, rawNext.length);
              final colEnd = nextHeaderCol != null
                  ? (rawIdx + label.length + nextHeaderCol.start - 1).clamp(colStart, rawNext.length)
                  : rawNext.length;
              final rawSlice = rawNext.substring(colStart, colEnd);
              final normCol = normalizeOcrText(rawSlice).trim();
              final colVal = normCol.split(RegExp(r'\s{3,}')).first.trim();
              if (colVal.isNotEmpty && !isNoiseOrSeparator(colVal) && !_isLabel(colVal)) {
                return colVal;
              }
              // Column box is blank on this multi-column row; do NOT return neighboring columns!
              continue;
            } else {
              return normNextFull;
            }
          }
        }
      }
      return null;
    }

    List<String>? sliceLinesBetween(
      List<String> startMarkers,
      List<String> endMarkers, {
      bool includeStartLine = true,
    }) {
      int startIdx = -1;
      for (int i = 0; i < lines.length; i++) {
        final low = lines[i].toLowerCase();
        if (startMarkers.any((m) => low.contains(m.toLowerCase()))) {
          startIdx = includeStartLine ? i : i + 1;
          break;
        }
      }
      if (startIdx == -1 || startIdx >= lines.length) return null;
      int endIdx = lines.length;
      for (int i = startIdx + 1; i < lines.length; i++) {
        final low = lines[i].toLowerCase();
        if (endMarkers.any((m) => low.contains(m.toLowerCase()))) {
          endIdx = i;
          break;
        }
      }
      return lines.sublist(startIdx, endIdx);
    }

    bool isOptionSelectedIn(List<String> targetLines, List<String> keywords) {
      for (int lineIdx = 0; lineIdx < targetLines.length; lineIdx++) {
        final line = targetLines[lineIdx];
        final lower = line.toLowerCase();
        for (final k in keywords) {
          final kw = k.toLowerCase();
          int idx = -1;
          if (RegExp(r'^[a-zA-Z0-9]{1,4}$').hasMatch(kw)) {
            final match = RegExp(r'\b' + RegExp.escape(kw) + r'\b', caseSensitive: false).firstMatch(lower);
            if (match == null) continue;
            idx = match.start;
          } else {
            idx = lower.indexOf(kw);
            if (idx == -1) continue;
          }

          final start = max(0, idx - 70);
          final end = min(line.length, idx + kw.length + 70);
          final snippet = line.substring(start, end);

          final checkedNear = RegExp(
            r'\[\s*[xX✓✔•*+\#1\-]\s*\][^\r\n\[\]()]{0,35}?' + RegExp.escape(kw) +
            r'|\(\s*[xX✓✔•*+\#1\-]\s*\)[^\r\n\[\]()]{0,35}?' + RegExp.escape(kw) +
            r'|[☑☒✓✔•][^\r\n\[\]()]{0,35}?' + RegExp.escape(kw) +
            r'|(?:\b|[^\w])[xX✓✔]\s{0,5}' + RegExp.escape(kw) +
            r'|' + RegExp.escape(kw) + r'\s{0,3}\[\s*[xX✓✔•*+\#1\-]\s*\]' +
            r'|' + RegExp.escape(kw) + r'\s{0,3}\(\s*[xX✓✔•*+\#1\-]\s*\)' +
            r'|' + RegExp.escape(kw) + r'\s{0,3}[☑☒✓✔•]',
            caseSensitive: false,
          ).hasMatch(snippet);

          final uncheckedNear = RegExp(
            r'\[\s*\][^\r\n\[\]()]{0,35}?' + RegExp.escape(kw) +
            r'|\(\s*\)[^\r\n\[\]()]{0,35}?' + RegExp.escape(kw) +
            r'|[☐口Ü][^\r\n\[\]()]{0,35}?' + RegExp.escape(kw) +
            r'|' + RegExp.escape(kw) + r'\s{0,3}\[\s*\]' +
            r'|' + RegExp.escape(kw) + r'\s{0,3}\(\s*\)' +
            r'|' + RegExp.escape(kw) + r'\s{0,3}[☐口Ü]',
            caseSensitive: false,
          ).hasMatch(snippet);

          if (checkedNear) return true;
          if (uncheckedNear) return false;
        }
      }
      return false;
    }

    /// Checks if an option is checked on the form.
    /// Distinguishes between marked boxes ([x], [X], ☒, ☑, ✓, ✔, •, X)
    /// and unchecked boxes ([ ], ☐, 口, Ü, ( )).
    bool isOptionSelected(List<String> keywords) {
      for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
        final line = lines[lineIdx];
        final lower = line.toLowerCase();
        for (final k in keywords) {
          final kw = k.toLowerCase();
          int idx = -1;
          if (RegExp(r'^[a-zA-Z0-9]{1,4}$').hasMatch(kw)) {
            final match = RegExp(r'\b' + RegExp.escape(kw) + r'\b', caseSensitive: false).firstMatch(lower);
            if (match == null) continue;
            idx = match.start;
          } else {
            idx = lower.indexOf(kw);
            if (idx == -1) continue;
          }

          final start = max(0, idx - 70);
          final end = min(line.length, idx + kw.length + 70);
          final snippet = line.substring(start, end);

          final checkedNear = RegExp(
            r'\[\s*[xX✓✔•*+\#1\-]\s*\][^\r\n\[\]()]{0,35}?' + RegExp.escape(kw) +
            r'|\(\s*[xX✓✔•*+\#1\-]\s*\)[^\r\n\[\]()]{0,35}?' + RegExp.escape(kw) +
            r'|[☑☒✓✔•][^\r\n\[\]()]{0,35}?' + RegExp.escape(kw) +
            r'|(?:\b|[^\w])[xX✓✔]\s{0,5}' + RegExp.escape(kw) +
            r'|' + RegExp.escape(kw) + r'\s{0,3}\[\s*[xX✓✔•*+\#1\-]\s*\]' +
            r'|' + RegExp.escape(kw) + r'\s{0,3}\(\s*[xX✓✔•*+\#1\-]\s*\)' +
            r'|' + RegExp.escape(kw) + r'\s{0,3}[☑☒✓✔•]',
            caseSensitive: false,
          ).hasMatch(snippet);

          final uncheckedNear = RegExp(
            r'\[\s*\][^\r\n\[\]()]{0,35}?' + RegExp.escape(kw) +
            r'|\(\s*\)[^\r\n\[\]()]{0,35}?' + RegExp.escape(kw) +
            r'|[☐口Ü][^\r\n\[\]()]{0,35}?' + RegExp.escape(kw) +
            r'|' + RegExp.escape(kw) + r'\s{0,3}\[\s*\]' +
            r'|' + RegExp.escape(kw) + r'\s{0,3}\(\s*\)' +
            r'|' + RegExp.escape(kw) + r'\s{0,3}[☐口Ü]',
            caseSensitive: false,
          ).hasMatch(snippet);

          if (checkedNear) return true;
          if (uncheckedNear) return false;
        }
      }

      // If document has checkmarks/checkboxes elsewhere in the document, check if keyword appears in text without any explicit checkbox
      final allText = lines.join('\n');
      final hasAnyCheckmarks = RegExp(r'\[\s*[xX✓✔•*+\#1\-]?\s*\]|\(\s*[xX✓✔]?\s*\)|☒|☑|[✓✔√]|•|[☐口Ü]').hasMatch(allText);
      if (hasAnyCheckmarks) {
        return false;
      }

      // If document has NO checkbox characters at all (blank form), options are not selected
      return false;
    }

    // ==========================================
    // 1. Demographics Extraction (Page 1 / Front)
    // ==========================================
    final demographics = <String, dynamic>{};
    final obstetrics = <String, dynamic>{};

    // ── Patient Token ID / बिरामी टोकन नं (Page 1, Page 2 header, & Follow-Up Encounter Sheets) ──
    String? extractedTokenId;

    // 1. Regex check for full standard format: GC-[CODE]-[YEAR]-[SEQ]
    final fullTokenMatch = RegExp(
      r'\bGC-([A-Za-z0-9_-]+)-(\d{4})-(\d{1,6})\b',
      caseSensitive: false,
    ).firstMatch(text);

    if (fullTokenMatch != null) {
      final code = fullTokenMatch.group(1)!.toUpperCase();
      final yr = fullTokenMatch.group(2)!;
      final seq = fullTokenMatch.group(3)!.padLeft(5, '0');
      extractedTokenId = 'GC-$code-$yr-$seq';
    } else {
      // 2. Search for Token ID label followed by sequence digits or code
      final rawTokenVal = findValueForLabel([
        'encounter token id', 'patient token id', 'patient token', 'token id', 'token no', 'token number',
        'बिरामी टोकन नं', 'बिरामी टोकन', 'टोकन नं', 'टोकन', 'token',
      ], multiLine: false);

      if (rawTokenVal != null && rawTokenVal.isNotEmpty) {
        final compactToken = rawTokenVal.replaceAll(RegExp(r'\s+'), '');
        final isUnfilledPrefix = RegExp(
          r'^GC-[A-Za-z0-9_□]+-\d{4}-?$',
          caseSensitive: false,
        ).hasMatch(compactToken);
        if (!isUnfilledPrefix) {
          if (RegExp(r'GC-[A-Za-z0-9_-]+-\d{4}-\d{1,6}', caseSensitive: false).hasMatch(compactToken)) {
            final m = RegExp(r'GC-([A-Za-z0-9_-]+)-(\d{4})-(\d{1,6})', caseSensitive: false).firstMatch(compactToken);
            if (m != null) {
              extractedTokenId = 'GC-${m.group(1)!.toUpperCase()}-${m.group(2)}-${m.group(3)!.padLeft(5, "0")}';
            }
          } else if (!compactToken.toUpperCase().startsWith('GC-')) {
            final digits = rawTokenVal.replaceAll(RegExp(r'[^0-9]'), '');
            if (digits.isNotEmpty && digits.length <= 6) {
              extractedTokenId = digits.padLeft(5, '0');
            }
          }
        }
      }
    }

    if (extractedTokenId != null && extractedTokenId.isNotEmpty) {
      demographics['patientId'] = extractedTokenId;
      demographics['patientTokenId'] = extractedTokenId;
      confidences['patientId'] = 0.95;
    }

    if (!isPage2Only) {
      // ── First & Last Name ──
      // Check for distinct First Name / Surname fields first (from block-letter forms)
      final extractedFirstName = findValueForLabel(['first name', 'पहिलो नाम', 'given name']);
      final extractedSurname = findValueForLabel(['surname', 'last name', 'थर', 'family name']);

      if ((extractedFirstName != null && extractedFirstName.isNotEmpty) ||
          (extractedSurname != null && extractedSurname.isNotEmpty)) {
        if (extractedFirstName != null && extractedFirstName.isNotEmpty) {
          var cleanFirst = extractedFirstName.replaceAll(RegExp(r'\s*(surname|last name|थर|age|mobile|ward).*$', caseSensitive: false), '').trim();
          cleanFirst = cleanFirst.split(RegExp(r'\s{3,}')).first.trim();
          if (cleanFirst.isNotEmpty && !isNoiseOrSeparator(cleanFirst) && cleanFirst.replaceAll(RegExp(r'[_ \t-]'), '').isNotEmpty) {
            final collapsed = cleanFirst.replaceAll(RegExp(r'\s+'), '');
            demographics['firstName'] = _capitalizeFirst(collapsed);
          }
        }
        if (extractedSurname != null && extractedSurname.isNotEmpty) {
          var cleanSurname = extractedSurname.replaceAll(RegExp(r'\s*(age|mobile|district|ward|उमेर).*$', caseSensitive: false), '').trim();
          cleanSurname = cleanSurname.split(RegExp(r'\s{3,}')).first.trim();
          if (cleanSurname.isNotEmpty && !isNoiseOrSeparator(cleanSurname) && cleanSurname.replaceAll(RegExp(r'[_ \t-]'), '').isNotEmpty) {
            final collapsed = cleanSurname.replaceAll(RegExp(r'\s+'), '');
            demographics['surname'] = collapsed.length <= 2 ? collapsed.toUpperCase() : _capitalizeFirst(collapsed);
          }
        }
        confidences['name'] = (demographics['firstName'] != null && demographics['surname'] != null) ? 0.96 : 0.80;
      }

      String? rawName;
      if (demographics['firstName'] == null) {
        rawName = findValueForLabel([
          'patient name', 'Patient Name', 'बिरामीको नाम', 'नाम',
          'patient narne', 'patient nane',
        ]);

        if (rawName == null || rawName.isEmpty) {
          final nameMatch = RegExp(
            r'(?<!husband[^\n]{0,10})(?<!spouse[^\n]{0,10})(?<!father[^\n]{0,10})(?<!relative[^\n]{0,10})'
            r'(?:patient\s*name|बिरामीको नाम|नाम)[:\s]+(?!(?:registration|intake|form|demographics)\b)([A-Za-z\u0900-\u097F][A-Za-z\u0900-\u097F\s]{1,35})',
            caseSensitive: false,
          ).firstMatch(text);
          rawName = nameMatch?.group(1)?.trim().split(RegExp(r'[\r\n]+')).first.trim();
        }

        if (rawName != null && rawName.isNotEmpty) {
          rawName = rawName.replaceAll(RegExp(r'\s*(age|mobile|district|ward|उमेर|husband|spouse).*$', caseSensitive: false), '').trim();
          final parts = rawName.split(RegExp(r'\s+')).where((p) => p.trim().isNotEmpty).toList();
          if (parts.length >= 2) {
            demographics['firstName'] = _capitalizeFirst(parts.first);
            demographics['surname'] = parts.sublist(1).map(_capitalizeFirst).join(' ');
            confidences['name'] = 0.95;
          } else if (parts.isNotEmpty) {
            demographics['firstName'] = _capitalizeFirst(parts.first);
            demographics['surname'] = null;
            confidences['name'] = 0.70;
          }
        }
      }
      demographics.putIfAbsent('firstName', () => null);
      demographics.putIfAbsent('surname', () => null);
      confidences.putIfAbsent('name', () => 0.30);

      // ── Age ──
      // Search 'patient age' first to avoid matching 'Age at Marriage'
      int? parsedAge;
      // Priority 1: explicit 'Patient Age' label
      final patientAgeLine = lines.firstWhere(
        (l) => l.toLowerCase().contains('patient age'),
        orElse: () => '',
      );
      if (patientAgeLine.isNotEmpty) {
        final m = RegExp(r'patient\s*age[:\s]+(\d{1,3})', caseSensitive: false)
            .firstMatch(patientAgeLine);
        parsedAge = m != null ? int.tryParse(m.group(1)!) : null;
      }
      // Priority 2: 'Age:' label, checking inline or columnar nextLine, avoiding marital age
      if (parsedAge == null) {
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final lowerLine = line.toLowerCase();
          final mAge = RegExp(r'\bage\b', caseSensitive: false).firstMatch(lowerLine);
          if (mAge != null &&
              !lowerLine.contains('marriage') &&
              !lowerLine.contains('marital') &&
              !lowerLine.contains('at marriage') &&
              !lowerLine.contains('patient age') &&
              !lowerLine.contains('page')) {
            final m = RegExp(r'(?:^|\s)age[:\s]+(\d{1,3})', caseSensitive: false)
                .firstMatch(line);
            if (m != null) {
              parsedAge = int.tryParse(m.group(1)!);
              break;
            }
            // Check next line under 'age' column if available
            if (i + 1 < lines.length) {
              final ageCol = mAge.start;
              final colStart = (ageCol >= 6) ? ageCol - 6 : 0;
              final nextLine = lines[i + 1];
              if (nextLine.length > colStart) {
                final colSub = nextLine.substring(colStart).trim();
                final numMatch = RegExp(r'^(\d{1,3})').firstMatch(colSub.replaceAll(RegExp(r'\s+'), ''));
                if (numMatch != null) {
                  final candidate = int.tryParse(numMatch.group(1)!);
                  if (candidate != null && candidate >= 10 && candidate <= 110) {
                    parsedAge = candidate;
                    break;
                  }
                }
              }
            }
          }
        }
      }
      // Priority 3: regex fallback excluding 'age at marriage'
      if (parsedAge == null) {
        final ageMatch = RegExp(
          r'\bage(?!\s*at\s*marriage)[:\s]+(\d{1,3})\b',
          caseSensitive: false,
        ).firstMatch(text);
        parsedAge = ageMatch != null ? int.tryParse(ageMatch.group(1)!) : null;
      }
      // Also try उमेर (Nepali)
      if (parsedAge == null) {
        final nepaliAge = RegExp(r'उमेर[:\s]+(\d{1,3})').firstMatch(text);
        parsedAge = nepaliAge != null ? int.tryParse(nepaliAge.group(1)!) : null;
      }
      if (parsedAge != null && parsedAge >= 10 && parsedAge <= 110) {
        demographics['age'] = parsedAge;
        confidences['age'] = 0.95;
      } else {
        demographics['age'] = null;
        confidences['age'] = 0.10;
      }


      // ── Relative / Spouse / Father Name ──
      final relLabels = [
        "husband/spouse", "husband / spouse", "husband's name", "husband name", "husband:", "husbancl",
        "spouse name", "spouse:",
        "father's name", "father name", "father:",
        "relative name", "relative:", "guardian name", "guardian:",
        "आफन्तको नाम", "श्रीमानको नाम", "श्रीमान", "बुबाको नाम", "बुबा", "पति",
      ];
      final relValue = findValueForLabel(relLabels);
      final relSurnameVal = findValueForLabel(['relative surname', 'आफन्तको थर']);
      if (relValue != null && relValue.isNotEmpty) {
        var relName = relValue.replaceAll(RegExp(r'\s*\(.*?\)\s*$'), '').trim();
        relName = relName.replaceAll(RegExp(r'\s*(mobile|district|ward|age|उमेर|surname|थर).*$', caseSensitive: false), '').trim();
        if (relSurnameVal != null && relSurnameVal.isNotEmpty) {
          // Collapse intra-box single spaces while preserving 2+ space word boundaries
          relName = relName
              .split(RegExp(r'\s{2,}'))
              .map((part) => part.replaceAll(RegExp(r'\s+'), ''))
              .where((part) => part.isNotEmpty)
              .map(_capitalizeFirst)
              .join(' ');
        }
        demographics['relativeName'] = relName;
      }

      // Check Relative Surname box (Yellow Form Row 2)
      if (relSurnameVal != null && relSurnameVal.isNotEmpty) {
        final rawRelSur = relSurnameVal.replaceAll(RegExp(r'\s*(mobile|district|ward|age|उमेर|relation|नाता).*$', caseSensitive: false), '').trim();
        final surname = rawRelSur.replaceAll(RegExp(r'\s+'), '');
        if (surname.isNotEmpty && !_isLabel(surname) && !isNoiseOrSeparator(surname)) {
          final formattedSur = surname.length <= 2 ? surname.toUpperCase() : _capitalizeFirst(surname);
          demographics['relativeSurname'] = formattedSur;
          if (demographics['relativeName'] != null) {
            final cur = demographics['relativeName'].toString();
            if (!cur.toLowerCase().contains(formattedSur.toLowerCase())) {
              demographics['relativeName'] = '$cur $formattedSur'.trim();
            }
          } else {
            demographics['relativeName'] = formattedSur;
          }
        }
      }

      // Detect Relation checkbox (Husband / Father)
      if (isOptionSelected(['husband / श्रीमान्', 'husband', 'श्रीमान्', 'श्रीमान', 'पति'])) {
        demographics['relativeType'] = 'Husband';
      } else if (isOptionSelected(['father / बुबा', 'father', 'बुबा', 'बुवा'])) {
        demographics['relativeType'] = 'Father';
      } else if (isOptionSelected(['guardian', 'संरक्षक'])) {
        demographics['relativeType'] = 'Guardian';
      } else if (relValue != null && (relValue.toLowerCase().contains('father') || relValue.contains('बुबा'))) {
        demographics['relativeType'] = 'Father';
      } else {
        demographics['relativeType'] = (demographics['age'] as int? ?? 30) < 20 ? 'Father' : 'Husband';
      }
      confidences['relative'] = demographics['relativeName'] != null ? 0.90 : 0.50;

      // ── Mobile Number (Nepali standard 10 digits: 98... or 97...) ──
      String? extractedMobile;
      final rawMobileVal = findValueForLabel(['mobile', 'phone', 'contact', 'सम्पर्क', 'फोन', 'मोबाइल']);
      if (rawMobileVal != null && rawMobileVal.isNotEmpty) {
        var cleanMobile = rawMobileVal
            .replaceAllMapped(RegExp(r'^[qgQG]([78])'), (m) => '9${m.group(1)}')
            .replaceAll(RegExp(r'[^0-9]'), '');
        if (cleanMobile.length >= 10) {
          cleanMobile = cleanMobile.substring(0, 10);
        }
        if (cleanMobile.length == 10 && cleanMobile.startsWith('9')) {
          extractedMobile = cleanMobile;
        }
      }

      if (extractedMobile == null) {
        final normalizedTextForMobile = text
            .replaceAllMapped(RegExp(r'\b[qgQG]([78]\d{8})\b'), (m) => '9${m.group(1)}');
        final mobileMatch = RegExp(r'\b(9[78]\d{8})\b').firstMatch(normalizedTextForMobile);
        if (mobileMatch != null) {
          extractedMobile = mobileMatch.group(1);
        } else {
          final anyMobileMatch = RegExp(r'\b(9\d{9})\b').firstMatch(normalizedTextForMobile);
          extractedMobile = anyMobileMatch?.group(1);
        }
      }

      if (extractedMobile != null) {
        demographics['mobile'] = extractedMobile;
        confidences['mobile'] = 0.98;
      } else {
        demographics['mobile'] = '';
        confidences['mobile'] = 0.50;
      }

      // ── Contact Person (Secondary / Emergency Contact) ──
      final contactPersonValue = findValueForLabel([
        'contact person (secondary)', 'contact person', 'secondary contact', 'emergency contact',
        'सम्पर्क व्यक्ति', 'सम्पर्क',
      ]);
      if (contactPersonValue != null && contactPersonValue.isNotEmpty) {
        var cleanContact = contactPersonValue
            .replaceAll(RegExp(r'^\(?secondary\)?[:\s]*', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s*(mobile|phone|नम्बर|contact mobile).*$', caseSensitive: false), '')
            .trim();
        if (cleanContact.isNotEmpty && !cleanContact.contains(':')) {
          demographics['contactPerson'] = cleanContact;
          confidences['contactPerson'] = 0.85;
        }
      }

      // ── Contact Mobile (Secondary — second distinct 10-digit number in text) ──
      {
        final allMobileMatches = RegExp(r'\b(9\d{9})\b').allMatches(text).toList();
        if (allMobileMatches.length >= 2) {
          for (final match in allMobileMatches) {
            final candidate = match.group(1);
            if (candidate != null && candidate != extractedMobile) {
              demographics['contactMobile'] = candidate;
              confidences['contactMobile'] = 0.80;
              break;
            }
          }
        }
      }

      // ── Marriage Age / विवाह उमेर ──
      final maritalAgeValue = findValueForLabel([
        'marital age', 'age at marriage', 'marriage age', 'age of marriage',
        'विवाह उमेर', 'विवाह को उमेर',
      ]);
      if (maritalAgeValue != null) {
        final compactAge = maritalAgeValue.replaceAll(RegExp(r'(?<=\d)[ \t]+(?=\d)'), '');
        final ageDigits = RegExp(r'(\d{1,2})').firstMatch(compactAge);
        final parsedMaritalAge = ageDigits != null ? int.tryParse(ageDigits.group(1)!) : null;
        if (parsedMaritalAge != null && parsedMaritalAge >= 10 && parsedMaritalAge <= 60) {
          demographics['maritalAge'] = parsedMaritalAge;
          confidences['maritalAge'] = 0.88;
        }
      }

      // ── Ward Number ──
      final wardValue = findValueForLabel(['ward no', 'ward', 'वडा नं', 'वडा']);
      if (wardValue != null) {
        final compactWard = wardValue.replaceAll(RegExp(r'(?<=\d)[ \t]+(?=\d)'), '');
        final wardDigits = RegExp(r'(\d{1,2})').firstMatch(compactWard);
        if (wardDigits != null) {
          demographics['ward'] = wardDigits.group(1)!.padLeft(2, '0');
          confidences['ward'] = 0.95;
        }
      }
      if (!demographics.containsKey('ward')) {
        final wardMatch = RegExp(r'(?:ward|वडा)(?:\s*no\.?)?[:\s#]*(\d{1,2})', caseSensitive: false).firstMatch(text);
        if (wardMatch != null) {
          demographics['ward'] = wardMatch.group(1)!.padLeft(2, '0');
          confidences['ward'] = 0.90;
        } else {
          demographics['ward'] = '03';
          confidences['ward'] = 0.60;
        }
      }

      // ── Province, District & Municipality ──
      String normalizeProvinceName(String raw) {
        final compact = raw.replaceAll(RegExp(r'\s+'), '').toLowerCase();
        if (compact.isEmpty) return '';
        for (final p in ClinicalConstants.nepalProvinces) {
          final pLow = p.toLowerCase();
          if (pLow == compact || (compact.length >= 4 && pLow.startsWith(compact))) {
            return p;
          }
        }
        return raw.trim();
      }

      String normalizeDistrictName(String raw, String? provHint) {
        final compact = raw.replaceAll(RegExp(r'\s+'), '').toLowerCase();
        if (compact.isEmpty) return '';
        final pool = <String>[
          if (provHint != null && provHint.isNotEmpty) ...NepalGeodata.districtsFor(provHint),
          ...NepalGeodata.allDistricts,
        ];
        for (final d in pool) {
          if (d.replaceAll(' ', '').toLowerCase() == compact) return d;
        }
        if (compact.length >= 5) {
          for (final d in pool) {
            final dCompact = d.replaceAll(' ', '').toLowerCase();
            if (dCompact.startsWith(compact) || compact.startsWith(dCompact)) return d;
          }
        }
        return raw.trim();
      }

      final provinceValue = findValueForLabel(['province', 'प्रदेश']);
      final normalizedProvHint = (provinceValue != null && provinceValue.isNotEmpty)
          ? normalizeProvinceName(provinceValue)
          : null;

      final districtValue = findValueForLabel(['district', 'जिल्ला']);
      final rawDistrictClean = districtValue
              ?.replaceAll(RegExp(r'\s*(municipality|palika|province|ward|वडा|गाउँपालिका).*$', caseSensitive: false), '')
              .replaceAll('+', 't')
              .trim() ??
          '';
      demographics['district'] = normalizeDistrictName(rawDistrictClean, normalizedProvHint);

      final muniValue = findValueForLabel(['palika', 'municipality', 'vdc', 'ward center', 'गाउँ / न.पा.', 'न.पा.', 'गाउँपालिका', 'नगरपालिका', 'पालिका']);
      var rawMuniClean = muniValue
              ?.replaceAll(RegExp(r'\s*(ward\s*(?:no\.?)?[:\s#]*\d*|district|province|वडा नं).*$', caseSensitive: false), '')
              .replaceAll('+', 't')
              .trim() ??
          '';
      if (rawMuniClean.isNotEmpty && !rawMuniClean.contains('  ')) {
        // Collapse intra-box spaces in uppercase character-box Palika names
        if (rawMuniClean == rawMuniClean.toUpperCase()) {
          rawMuniClean = _capitalizeFirst(rawMuniClean.replaceAll(RegExp(r'\s+'), ''));
        }
      }
      demographics['municipality'] = rawMuniClean;

      if (normalizedProvHint != null && normalizedProvHint.isNotEmpty) {
        demographics['province'] = normalizedProvHint;
      } else if (demographics['district'] != null && (demographics['district'] as String).isNotEmpty) {
        demographics['province'] = NepalGeodata.provinceOf(demographics['district'] as String);
      } else {
        demographics['province'] = 'Bagmati';
      }
      confidences['location'] = (districtValue != null) ? 0.92 : 0.55;

      // ── Consents (Check explicit YES / NO checkboxes on Consent lines first, then legacy fallback) ──
      bool? parseConsentLine(List<String> lineKeywords) {
        final noRe = RegExp(
          r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔])\s*no\b|\bno\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•])',
          caseSensitive: false,
        );
        final yesRe = RegExp(
          r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔])\s*yes\b|\byes\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•])',
          caseSensitive: false,
        );
        for (int idx = 0; idx < lines.length; idx++) {
          final l = lines[idx];
          final low = l.toLowerCase();
          if (lineKeywords.any((kw) => low.contains(kw))) {
            if (noRe.hasMatch(l)) return false;
            if (yesRe.hasMatch(l)) return true;
            // If YES / NO wrapped onto 1-3 lines immediately below the label due to bilingual sub-caption height
            if (!RegExp(r'\byes\b', caseSensitive: false).hasMatch(l) &&
                !RegExp(r'\bno\b', caseSensitive: false).hasMatch(l)) {
              for (int sub = idx + 1; sub < min(lines.length, idx + 4); sub++) {
                final subLine = lines[sub];
                final subLow = subLine.toLowerCase();
                if (subLow.contains('consent for ') || subLow.contains('station 1')) break;
                if (RegExp(r'\byes\b', caseSensitive: false).hasMatch(subLine) &&
                    RegExp(r'\bno\b', caseSensitive: false).hasMatch(subLine)) {
                  if (noRe.hasMatch(subLine)) return false;
                  if (yesRe.hasMatch(subLine)) return true;
                  return false;
                }
              }
            }
            return false;
          }
        }
        return null;
      }

      final explicitTreatConsent = parseConsentLine(['consent for treatment', 'उपचारको लागि सहमति']);
      final explicitStoreConsent = parseConsentLine(['consent for storage', 'स्वास्थ्य विवरण सहमति']);
      final lowerFull = text.toLowerCase();
      demographics['consentTreatment'] = explicitTreatConsent ??
          (!lowerFull.contains('no consent') &&
              (lowerFull.contains('consent to examination') ||
                  lowerFull.contains('treatment informed consent') ||
                  lowerFull.contains('उपचार') ||
                  lowerFull.contains('सहमति')));
      demographics['consentStoreMedicalInfo'] = explicitStoreConsent ??
          (!lowerFull.contains('no consent') &&
              (lowerFull.contains('storage consent') ||
                  lowerFull.contains('भण्डारण') ||
                  lowerFull.contains('medical information') ||
                  lowerFull.contains('सहमति')));
      confidences['consent'] = 0.92;

      // ── Marital Status ──
      if (page1OmrMarital != null && page1OmrMarital.values.any((r) => r.isMarked)) {
        final marked = page1OmrMarital.values.firstWhere((r) => r.isMarked);
        demographics['maritalStatus'] = marked.id;
        confidences['maritalStatus'] = marked.confidence;
      } else {
        if (isOptionSelected(['unmarried', 'अविवाहित'])) {
          demographics['maritalStatus'] = 'unmarried';
        } else if (isOptionSelected(['widow', 'एकल'])) {
          demographics['maritalStatus'] = 'widow';
        } else if (isOptionSelected(['divorced', 'सम्बन्ध विच्छेद', 'पारपाचुके'])) {
          demographics['maritalStatus'] = 'divorced';
        } else if (isOptionSelected(['married', 'विवाहित'])) {
          demographics['maritalStatus'] = 'married';
        } else if (demographics['relativeType'] == 'Husband') {
          demographics['maritalStatus'] = 'married';
        } else {
          demographics['maritalStatus'] = 'married';
        }
        confidences['maritalStatus'] = 0.92;
      }

      // Reconcile relation with marital status
      if (demographics['maritalStatus'] == 'married') {
        demographics['relativeType'] ??= 'Husband';
      } else {
        // For unmarried, widow, divorced, default relation to Father unless explicitly set
        if (demographics['relativeType'] == null || demographics['relativeType'] == 'Husband') {
          demographics['relativeType'] = 'Father';
        }
      }

      // ── Reasons for visit — exact keys for PatientModel.reasonsForVisit ──
      final reasons = <String>[];
      if (page1OmrReasons != null && page1OmrReasons.values.any((r) => r.isMarked)) {
        for (final entry in page1OmrReasons.entries) {
          if (entry.value.isMarked) {
            reasons.add(entry.key);
          }
        }
        demographics['reasonsForVisit'] = reasons;
        confidences['reasonsForVisit'] = 0.96;
      } else {
        final sectionBLines = sliceLinesBetween(
              ['section b', 'reason for visit', 'reasons for visit'],
              ['station 1', 'anamnesis date:', 'obstetric history', 'for official use only'],
            ) ??
            lines;
        if (isOptionSelectedIn(sectionBLines, ['prolapse', 'something hanging', 'hanging out', 'पाठेघर खस्ने', 'pro1apse'])) {
          reasons.add('something hanging out');
        }
        if (isOptionSelectedIn(sectionBLines, ['discharge', 'itching', 'चिलाउने'])) {
          reasons.add('discharge and or itching');
        }
        if (isOptionSelectedIn(sectionBLines, ['problems passing urine', 'incontinence', 'पिसाब समस्या', 'पेसाब', 'ur1ne'])) {
          reasons.add('problems passing urine');
        }
        if (isOptionSelectedIn(sectionBLines, ['problems passing stool', 'stool', 'दिसा समस्या'])) {
          reasons.add('problems passing stool');
        }
        if (isOptionSelectedIn(sectionBLines, ['pain', 'lower abdominal pain', 'abdominal pain', 'back pain', 'abdominal / back pain', 'ढाड दुख्ने', 'pelvic pain', 'dhaad dukhne'])) {
          reasons.add('pain');
        }
        if (isOptionSelectedIn(sectionBLines, ['menstrual problem', 'mahina', 'महिनावारी'])) {
          reasons.add('menstrual problem');
        }
        if (isOptionSelectedIn(sectionBLines, ['infertility', 'बाँझोपन'])) {
          reasons.add('infertility');
        }
        if (isOptionSelectedIn(sectionBLines, ['general checkup', 'checkup', 'जाँच'])) {
          reasons.add('checkup');
        }
        demographics['reasonsForVisit'] = reasons;
        confidences['reasonsForVisit'] = reasons.isNotEmpty ? 0.88 : 0.40;
      }
    }

    // ==========================================
    // 2. Obstetric History & Station 1 Anamnesis
    // Present on Page 1 (Station 1) and legacy Page 2 sheets containing Station 1
    // ==========================================
    final deliveriesValue = findValueForLabel(['nr deliveries', 'deliveries', 'parity', 'para', 'सुत्केरी'], multiLine: false) ??
        findValueForLabel(['nr deliveries', 'deliveries', 'parity', 'para', 'सुत्केरी']);
    final livingValue = findValueForLabel(['nr living children', 'living children', 'living', 'जीवित'], multiLine: false) ??
        findValueForLabel(['nr living children', 'living children', 'living', 'जीवित']);
    final abortionsValue = findValueForLabel(['nr abortion', 'abortions', 'abortion', 'miscarriage', 'गर्भपतन'], multiLine: false);

    int? rawDeliveries;
    int? rawLiving;
    int? rawAbortions;

    if (deliveriesValue != null) {
      final compactDel = deliveriesValue.replaceAll(RegExp(r'(?<=\d)[ \t]+(?=\d)'), '');
      final dDigits = RegExp(r'(\d{1,2})').firstMatch(compactDel);
      rawDeliveries = dDigits != null ? int.tryParse(dDigits.group(1)!) : null;
    }
    if (livingValue != null) {
      final compactLiv = livingValue.replaceAll(RegExp(r'(?<=\d)[ \t]+(?=\d)'), '');
      final lDigits = RegExp(r'(\d{1,2})').firstMatch(compactLiv);
      rawLiving = lDigits != null ? int.tryParse(lDigits.group(1)!) : null;
    }
    if (abortionsValue != null) {
      final compactAb = abortionsValue.replaceAll(RegExp(r'(?<=\d)[ \t]+(?=\d)'), '');
      final aDigits = RegExp(r'([0-9OoIl|]{1,2})').firstMatch(compactAb);
      if (aDigits != null) {
        rawAbortions = parseOcrInt(aDigits.group(1));
      }
    }

    if (rawDeliveries == null) {
      final delMatch = RegExp(r'\b(?:nr\s*deliveries|deliveries|parity|para)\b[:\s_]*([0-9]{1,2})', caseSensitive: false).firstMatch(text);
      rawDeliveries = delMatch != null ? int.tryParse(delMatch.group(1)!) : null;
    }
    if (rawLiving == null) {
      final livingMatch = RegExp(r'\b(?:nr\s*living(?:\s*children)?|living(?:\s*children)?|alive)\b[:\s_]*([0-9]{1,2})', caseSensitive: false).firstMatch(text);
      rawLiving = livingMatch != null ? int.tryParse(livingMatch.group(1)!) : null;
    }
    if (rawAbortions == null) {
      final abortionLine = lines.firstWhere(
        (l) => l.toLowerCase().contains('abortion') || l.toLowerCase().contains('miscarriage'),
        orElse: () => '',
      );
      if (abortionLine.isNotEmpty) {
        final compactLine = abortionLine.replaceAll(RegExp(r'(?<=\d)[ \t]+(?=\d)'), '');
        final m = RegExp(r'abortions?[:\s_]*([0-9OoIl|]{1,2})', caseSensitive: false).firstMatch(compactLine);
        if (m != null) {
          rawAbortions = parseOcrInt(m.group(1));
        }
      }
    }

    final bool hasObstetricSectionOnPage = !isPage2Only ||
        rawDeliveries != null ||
        rawLiving != null ||
        rawAbortions != null ||
        lowerText.contains('station 1') ||
        lowerText.contains('anamnesis') ||
        lowerText.contains('obstetric history');

    if (hasObstetricSectionOnPage) {
      rawDeliveries ??= 3;
      if (rawDeliveries > 15) rawDeliveries = 3;

      rawLiving ??= min(rawDeliveries, 3);
      if (rawLiving > 15) rawLiving = min(rawDeliveries, 3);

      rawAbortions ??= max(0, rawDeliveries - rawLiving);
      if (rawAbortions > 15) rawAbortions = max(0, rawDeliveries - rawLiving);

      obstetrics['deliveries'] = rawDeliveries;
      obstetrics['livingChildren'] = min(rawLiving, rawDeliveries);
      obstetrics['abortions'] = rawAbortions;

      final clinicalComplaints = <String>[];
      final complaintDetails = <String, Map<String, dynamic>>{};
      String? firstTickedComplaintDuration;

      // Structured Station 1 block parser (extracts per-complaint duration, sub-options, and handwritten remarks)
      final station1Lines = sliceLinesBetween(
        ['station 1', 'anamnesis date:', 'nr deliveries:'],
        ['for official use only', 'station 2', 'examination date:'],
      );

      const complaintDefs = <({String key, String label, List<String> options})>[
        (key: 'prolapse', label: 'something hanging out', options: ['pessary', 'surgery']),
        (key: 'discharge', label: 'discharge / itching', options: ['white', 'yellow', 'green', 'grey', 'smelly']),
        (key: 'urine', label: 'problems passing urine', options: ['stress', 'urge', 'continuous flow']),
        (key: 'stool', label: 'problems passing stool', options: <String>[]),
        (key: 'menstrual', label: 'menstrual problem', options: ['dysmenorrhoea', 'metrorrhagia', 'menorrhagia', 'postmenopausal bleeding']),
        (key: 'infertility', label: 'infertility', options: <String>[]),
        (key: 'lower_abdomen_pain', label: 'lower abdomen pain', options: <String>[]),
        (key: 'lower_back_pain', label: 'lower back pain', options: <String>[]),
        (key: 'checkup', label: 'checkup', options: ['routine screening']),
      ];

      bool hasStructuredStation1Grid = false;
      if (station1Lines != null) {
        final anchorIndices = <int, ({String key, String label, List<String> options})>{};
        for (final def in complaintDefs) {
          for (int idx = 0; idx < station1Lines.length; idx++) {
            if (anchorIndices.containsKey(idx)) continue;
            final low = station1Lines[idx].toLowerCase();
            if (low.contains(def.label)) {
              anchorIndices[idx] = def;
              break;
            }
          }
        }
        if (anchorIndices.length >= 5) {
          hasStructuredStation1Grid = true;
          final sortedRows = anchorIndices.keys.toList()..sort();
          for (int k = 0; k < sortedRows.length; k++) {
            final rowStart = sortedRows[k];
            final rowEnd = (k + 1 < sortedRows.length) ? sortedRows[k + 1] : station1Lines.length;
            final blockLines = station1Lines.sublist(rowStart, rowEnd);
            final def = anchorIndices[rowStart]!;

            final isMainChecked = isOptionSelectedIn(blockLines, [def.label]);

            String? cDur;
            if (isOptionSelectedIn(blockLines, ['> 10 years', '>10 years'])) {
              cDur = '> 10 years';
            } else if (isOptionSelectedIn(blockLines, ['> 5 years', '>5 years'])) {
              cDur = '> 5 years';
            } else if (isOptionSelectedIn(blockLines, ['> 1 year', '>1 year'])) {
              cDur = '> 1 year';
            } else if (isOptionSelectedIn(blockLines, ['< 1 year', '<1 year'])) {
              cDur = '< 1 year';
            } else if (isOptionSelectedIn(blockLines, ['< 1month', '<1month', '< 1 month'])) {
              cDur = '< 1month';
            }

            final selectedOpts = <String>[];
            for (final opt in def.options) {
              final optKeywords = opt == 'dysmenorrhoea' ? ['dysmenorrhoea', 'dysmenorroea'] : [opt];
              if (isOptionSelectedIn(blockLines, optKeywords)) {
                selectedOpts.add(opt);
              }
            }

            String cRemarks = '';
            for (final bl in blockLines) {
              final rm = RegExp(r'remarks:[ \t]*([^\r\n]*)', caseSensitive: false).firstMatch(bl);
              if (rm != null) {
                final cand = rm.group(1)!.replaceAll(RegExp(r'^[_\s]+|[_\s]+$'), '').trim();
                if (cand.isNotEmpty && !isNoiseOrSeparator(cand)) {
                  cRemarks = cand;
                  break;
                }
              }
            }

            if (isMainChecked || cDur != null || selectedOpts.isNotEmpty || cRemarks.isNotEmpty) {
              if (!clinicalComplaints.contains(def.key)) {
                clinicalComplaints.add(def.key);
              }
              firstTickedComplaintDuration ??= cDur;
              complaintDetails[def.key] = {
                'present': true,
                'active': true,
                'duration': ?cDur,
                'options': selectedOpts,
                'subOptions': selectedOpts,
                'subOption': selectedOpts.join(', '),
                'remarks': cRemarks,
              };
            }
          }
        }
      }

      if (!hasStructuredStation1Grid) {
        final s1Fallback = station1Lines ??
            sliceLinesBetween(
              ['obstetric history', 'clinical complaints', 'station 1'],
              ['consent:', 'station 2'],
            ) ??
            lines;
        if (isOptionSelectedIn(s1Fallback, ['something hanging out', 'something hanging', 'hanging out', 'prolapse', 'पाठेघर खस्ने', 'mass per vagina', 'mass per vaginam', 'खस्ने', 'mpv'])) {
          clinicalComplaints.add('prolapse');
          if (isOptionSelectedIn(s1Fallback, ['mass per vagina'])) clinicalComplaints.add('Mass Per Vagina');
        }
        if (isOptionSelectedIn(s1Fallback, ['discharge and or itching', 'discharge / itching', 'white / foul discharge', 'discharge', 'itching', 'white discharge', 'foul discharge', 'पानी बग्ने', 'चिलाउने', 'सेतो पानी', 'स्राव'])) {
          clinicalComplaints.add('discharge');
          if (isOptionSelectedIn(s1Fallback, ['white / foul discharge'])) clinicalComplaints.add('White / Foul Discharge');
        }
        if (isOptionSelectedIn(s1Fallback, ['problems passing urine', 'urinary incontinence', 'incontinence', 'burning micturition', 'burning urine', 'urine problem', 'पिसाब सम्बन्धी', 'पिसाब पोल्ने', 'पिसाब चुहिने', 'पिसाब समस्या'])) {
          clinicalComplaints.add('urine');
        }
        if (isOptionSelectedIn(s1Fallback, ['problems passing stool', 'stool problem', 'दिसा सम्बन्धी', 'दिसा समस्या', 'दिसा'])) {
          clinicalComplaints.add('stool');
        }
        if (isOptionSelectedIn(s1Fallback, ['menstrual problem', 'dysmenorrhoea', 'menorrhagia', 'metrorrhagia', 'postmenopausal bleeding', 'महिनावारी', 'महिनावारी समस्या'])) {
          clinicalComplaints.add('menstrual');
        }
        if (isOptionSelectedIn(s1Fallback, ['infertility', 'infertile', 'conception difficulty', 'बाँझोपन', 'निःसन्तान'])) {
          clinicalComplaints.add('infertility');
        }
        if (isOptionSelectedIn(s1Fallback, ['lower abdominal pain', 'abdominal pain', 'lower abdomen pain', 'pelvic pain', 'pelvic heaviness', 'पेल्भिक भारी', 'तल्लो पेट दुख्ने', 'तल्लो पेट', 'dyspareunia'])) {
          clinicalComplaints.add('lower_abdomen_pain');
          if (isOptionSelectedIn(s1Fallback, ['pelvic heaviness'])) clinicalComplaints.add('Pelvic Heaviness');
        }
        if (isOptionSelectedIn(s1Fallback, ['lower back pain', 'back pain', 'backache', 'severe backache', 'ढाड दुख्ने', 'कम्मर दुख्ने', 'ढाड', 'कम्मर', 'coital bleeding'])) {
          clinicalComplaints.add('lower_back_pain');
        }
        if (isOptionSelectedIn(s1Fallback, ['checkup', 'general checkup', 'routine checkup', 'सामान्य जाँच', 'जाँच'])) {
          clinicalComplaints.add('checkup');
        }
      }

      // ── Complaints Duration ──
      String? duration = firstTickedComplaintDuration;
      if (duration == null) {
        final rawDuration = findValueForLabel([
          'complaints duration', 'complaint duration', 'duration', 'अवधि',
        ], multiLine: false);
        if (rawDuration != null) {
          final low = rawDuration.toLowerCase();
          if (low.contains('3-12')) {
            duration = '3-12 months';
          } else if (low.contains('10')) {
            duration = '> 10 years';
          } else if (low.contains('5')) {
            duration = '> 5 years';
          } else if (low.contains('> 1') || low.contains('>1') || low.contains('greater than 1')) {
            duration = '> 1 year';
          } else if (low.contains('< 1month') || low.contains('<1month') || low.contains('1 month') || low.contains('few week')) {
            duration = '< 1month';
          } else if (low.contains('< 1') || low.contains('<1') || low.contains('less than 1') || low.contains('month')) {
            duration = '< 1 year';
          } else if (low.contains('1 year') || low.contains('1year')) {
            duration = '> 1 year';
          } else {
            duration = rawDuration.trim();
          }
        }
      }
      if (duration == null) {
        if (isOptionSelected(['> 10 years', '>10 years', '> 10 yr', '>10 yr', '>10'])) {
          duration = '> 10 years';
        } else if (isOptionSelected(['> 5 years', '>5 years', '> 5 yr', '>5 yr', '>5'])) {
          duration = '> 5 years';
        } else if (isOptionSelected(['> 1 year', '>1 year', '> 1 yr', '>1 yr', '>1'])) {
          duration = '> 1 year';
        } else if (isOptionSelected(['< 1 year', '<1 year', '< 1 yr', '<1 yr', '<1'])) {
          duration = '< 1 year';
        } else if (isOptionSelected(['< 1month', '<1month', '< 1 month', 'few weeks', '<1m'])) {
          duration = '< 1month';
        } else {
          duration = '< 1 year';
        }
      }
      obstetrics['complaintsDuration'] = duration;

      // Correlate with Page 1 intake reasons if complaints list is sparse
      final reasons = (demographics['reasonsForVisit'] as List?)?.cast<String>() ?? [];
      if (reasons.any((r) => r.contains('hanging') || r.contains('prolapse')) && !clinicalComplaints.contains('prolapse')) {
        clinicalComplaints.add('prolapse');
      }
      if (reasons.any((r) => r.contains('discharge') || r.contains('itching')) && !clinicalComplaints.contains('discharge')) {
        clinicalComplaints.add('discharge');
      }
      if (reasons.any((r) => r.contains('urine')) && !clinicalComplaints.contains('urine')) {
        clinicalComplaints.add('urine');
      }
      if (reasons.any((r) => r.contains('stool')) && !clinicalComplaints.contains('stool')) {
        clinicalComplaints.add('stool');
      }
      if (reasons.any((r) => r.contains('menstrual') || r.contains('महिनावारी')) && !clinicalComplaints.contains('menstrual')) {
        clinicalComplaints.add('menstrual');
      }
      if (reasons.any((r) => r.contains('infertility')) && !clinicalComplaints.contains('infertility')) {
        clinicalComplaints.add('infertility');
      }
      if (reasons.any((r) => r.contains('pain') || r.contains('दुख्ने')) &&
          !clinicalComplaints.contains('lower_abdomen_pain') &&
          !clinicalComplaints.contains('lower_back_pain')) {
        clinicalComplaints.add('lower_abdomen_pain');
      }
      if (reasons.any((r) => r.contains('checkup')) && !clinicalComplaints.contains('checkup')) {
        clinicalComplaints.add('checkup');
      }

      obstetrics['clinicalComplaints'] = clinicalComplaints;
      if (complaintDetails.isNotEmpty) {
        obstetrics['complaintDetails'] = complaintDetails;
      }
      confidences['obstetrics'] = 0.92;
    }

    // ==========================================
    // 2. Clinical Assessment (Page 2 / Back)
    // ==========================================
    final vitals = <String, dynamic>{};
    final popStaging = <String, dynamic>{};
    final diagnoses = <String>[];
    final counseling = <String>[];
    final medications = <String>[];
    bool ringPessary = false;
    String? pessaryType;
    int? ringPessarySize;
    String? surgicalReferral;
    String? followUp;

    if (!isPage1Only) {
      // ── Blood Pressure (e.g. 140/90 or 130/85) ──
      int? systolic;
      int? diastolic;

      final bpValue = findValueForLabel(['blood pressure', 'bp', 'b.p', 'b/p', 'रक्तचाप']);
      if (bpValue != null) {
        final bpDigits = RegExp(r'(\d{2,3})\s*[/|\\:]\s*(\d{2,3})').firstMatch(bpValue);
        if (bpDigits != null) {
          systolic = int.tryParse(bpDigits.group(1)!);
          diastolic = int.tryParse(bpDigits.group(2)!);
        }
      }

      if (systolic == null) {
        final bpMatch = RegExp(r'\b(\d{2,3})\s*[/|\\:]\s*(\d{2,3})\s*(?:mmHg|mm\s*Hg)?', caseSensitive: false).firstMatch(text);
        if (bpMatch != null) {
          systolic = int.tryParse(bpMatch.group(1)!);
          diastolic = int.tryParse(bpMatch.group(2)!);
        }
      }

      vitals['systolicBp'] = (systolic != null && systolic >= 60 && systolic <= 260) ? systolic : null;
      vitals['diastolicBp'] = (diastolic != null && diastolic >= 40 && diastolic <= 160) ? diastolic : null;
      confidences['bp'] = (systolic != null) ? 0.95 : 0.0;

      // ── Pulse Rate ──
      int? parsedPulse;
      final pulseValue = findValueForLabel(['pulse rate', 'pulse', 'heart rate', 'मुटुको गति']);
      if (pulseValue != null) {
        final cleanPulse = pulseValue.replaceAll('_', '');
        parsedPulse = parseOcrInt(RegExp(r'(\d{2,3})').firstMatch(cleanPulse)?.group(1));
      }
      if (parsedPulse == null) {
        final cleanText = text.replaceAll('_', '');
        final pulseMatch = RegExp(
          r'\b(?:pulse(?:\s*rate)?|pr|hr)\b[:\s]*([0-9]{2,3})\b|([0-9]{2,3})\s*bpm',
          caseSensitive: false,
        ).firstMatch(cleanText);
        if (pulseMatch != null) {
          parsedPulse = int.tryParse(pulseMatch.group(1) ?? pulseMatch.group(2) ?? '');
        }
      }
      vitals['pulseRate'] = (parsedPulse != null && parsedPulse >= 35 && parsedPulse <= 220) ? parsedPulse : null;
      confidences['pulse'] = (parsedPulse != null) ? 0.95 : 0.0;

      // ── SpO2 ──
      int? parsedSpo2;
      final spo2Value = findValueForLabel(['spo2', 'sp02', 'saturation', 'o2 sat', 'oxygen']);
      if (spo2Value != null) {
        parsedSpo2 = int.tryParse(RegExp(r'(\d{2,3})').firstMatch(spo2Value)?.group(1) ?? '');
      }
      if (parsedSpo2 == null) {
        final spo2Match = RegExp(r'(?:spo2|sp02|saturation|o2)[:\s]*(\d{2,3})%?|\b([89]\d|100)\s*%', caseSensitive: false).firstMatch(text);
        if (spo2Match != null) {
          parsedSpo2 = int.tryParse(spo2Match.group(1) ?? spo2Match.group(2) ?? '');
        }
      }
      vitals['spo2'] = (parsedSpo2 != null && parsedSpo2 >= 50 && parsedSpo2 <= 100) ? parsedSpo2 : null;
      confidences['spo2'] = (parsedSpo2 != null) ? 0.95 : 0.0;

      // ── Blood Glucose ──
      int? parsedGlucose;
      final glucoseValue = findValueForLabel(['blood glucose', 'glucose', 'sugar', 'rbs', 'blood sugar']);
      if (glucoseValue != null) {
        parsedGlucose = int.tryParse(RegExp(r'(\d{2,3})').firstMatch(glucoseValue)?.group(1) ?? '');
      }
      if (parsedGlucose == null) {
        final glucoseMatch = RegExp(r'(?:glucose|sugar|rbs)[:\s]*(\d{2,3})|\b(\d{2,3})\s*(?:mg/d[l1]|rbs)', caseSensitive: false).firstMatch(text);
        if (glucoseMatch != null) {
          parsedGlucose = int.tryParse(glucoseMatch.group(1) ?? glucoseMatch.group(2) ?? '');
        }
      }
      vitals['bloodGlucose'] = (parsedGlucose != null && parsedGlucose >= 30 && parsedGlucose <= 600) ? parsedGlucose : null;
      confidences['glucose'] = (parsedGlucose != null) ? 0.92 : 0.0;

      // ── Rapid Tests ──
      // ── Rapid Tests (Station 3) ──
      // 1. Urine test (supports both Yellow Form "urine test: normal / pos" and multi-reagent "Urine Dipstick: [x] Protein+ ...")
      String? detectedUrineResult;
      for (final line in lines) {
        final low = line.toLowerCase();
        if (low.contains('urine dipstick')) {
          final reagents = <String>[];
          for (final rName in ['protein+', 'glucose+', 'blood+', 'leukocytes+', 'nitrite+']) {
            final esc = RegExp.escape(rName);
            if (RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|(?:^|\s)[xX✓✔])\s*' + esc, caseSensitive: false).hasMatch(line)) {
              reagents.add(rName);
            }
          }
          detectedUrineResult = reagents.isNotEmpty ? reagents.join(', ') : 'normal';
          break;
        }
        if (low.contains('urine test')) {
          final idx = low.indexOf('urine test');
          final after = line.substring(idx);
          final snippet = after.split(RegExp(r'pregnancy\s*test|blood\s*pressure', caseSensitive: false)).first;
          final markedPos = RegExp(
            r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*pos|pos\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)',
            caseSensitive: false,
          ).hasMatch(snippet);
          final markedNormal = RegExp(
            r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*normal|normal\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)',
            caseSensitive: false,
          ).hasMatch(snippet);
          if (markedPos) {
            detectedUrineResult = 'pos';
          } else if (markedNormal) {
            detectedUrineResult = 'normal';
          }
          break;
        }
      }
      if (detectedUrineResult != null) {
        vitals['urineTest'] = detectedUrineResult;
      } else {
        final rawUrine = findValueForLabel(['urine test', 'urine dipstick', 'urine', 'पिसाब जाँच']);
        final urineLineText = (rawUrine ?? '').toLowerCase();
        final hasUrineBoxes = rawUrine != null && RegExp(r'\[|\]|\(|\)|[☐口Ü☑☒]').hasMatch(rawUrine);
        final urinePos = isOptionSelected(['urine: pos', 'urine test: pos', 'पोजिटिभ']) ||
            isOptionSelected(['protein+', 'glucose+', 'blood+']) ||
            (!hasUrineBoxes && rawUrine != null && (urineLineText.contains('pos') || urineLineText.contains('+') || urineLineText.contains('protein') || urineLineText.contains('glucose') || urineLineText.contains('blood')));
        vitals['urineTest'] = urinePos ? 'pos' : 'normal';
      }

      // 2. Pregnancy test (supports neg / pos / Positive / Not Done)
      String? detectedPregResult;
      for (final line in lines) {
        final low = line.toLowerCase();
        if (low.contains('pregnancy test') || low.contains('pregnancy:')) {
          final idx = low.contains('pregnancy test') ? low.indexOf('pregnancy test') : low.indexOf('pregnancy:');
          final after = line.substring(idx);
          final snippet = after.split(RegExp(r'blood\s*pressure|pulse|\becg\b', caseSensitive: false)).first;
          final markedNotDone = RegExp(
            r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*not\s*done|not\s*done\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)',
            caseSensitive: false,
          ).hasMatch(snippet);
          final markedPos = RegExp(
            r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*pos(?:itive)?\b|\bpos(?:itive)?\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)',
            caseSensitive: false,
          ).hasMatch(snippet);
          final markedNeg = RegExp(
            r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*neg(?:ative)?\b|\bneg(?:ative)?\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)',
            caseSensitive: false,
          ).hasMatch(snippet);
          if (markedNotDone) {
            detectedPregResult = 'not_done';
          } else if (markedPos) {
            detectedPregResult = 'pos';
          } else if (markedNeg) {
            detectedPregResult = 'neg';
          }
          break;
        }
      }
      if (detectedPregResult != null) {
        vitals['pregnancyTest'] = detectedPregResult;
      } else {
        final rawPregnancy = findValueForLabel(['pregnancy test', 'pregnancy', 'upt', 'hcg', 'गर्भ जाँच']);
        final pregLower = (rawPregnancy ?? '').toLowerCase();
        final hasPregBoxes = rawPregnancy != null && RegExp(r'\[|\]|\(|\)|[☐口Ü☑☒]').hasMatch(rawPregnancy);
        if (!hasPregBoxes && pregLower.contains('not done')) {
          vitals['pregnancyTest'] = 'not_done';
        } else {
          final pregPos = isOptionSelected(['pregnancy: pos', 'pregnancy test: pos', 'upt: pos', 'upt: positive']) ||
              (!hasPregBoxes && pregLower.contains('pos') && !pregLower.contains('neg'));
          vitals['pregnancyTest'] = pregPos ? 'pos' : 'neg';
        }
      }

      // ── ECG Examination (Station 3) ──
      String? ecgLineSegment;
      for (final l in lines) {
        final low = l.toLowerCase();
        if (RegExp(r'\becg\s*:', caseSensitive: false).hasMatch(low)) {
          final ecgIdx = low.indexOf('ecg:');
          var seg = l.substring(ecgIdx + 4);
          final notesIdx = seg.toLowerCase().indexOf('ecg notes');
          if (notesIdx != -1) {
            seg = seg.substring(0, notesIdx);
          }
          ecgLineSegment = seg.trim();
          break;
        }
      }
      final rawEcg = ecgLineSegment ?? findValueForLabel(['ecg', 'electrocardiogram', 'ईसीजी']);
      final ecgLower = (rawEcg ?? '').toLowerCase();

      bool isMarkedInLine(String line, List<String> terms) {
        for (final t in terms) {
          final esc = RegExp.escape(t);
          if (RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☒☑✓✔•]|(?:^|\s)[xX✓✔])\s*' + esc, caseSensitive: false).hasMatch(line) ||
              RegExp(esc + r'\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☒☑✓✔•])', caseSensitive: false).hasMatch(line)) {
            return true;
          }
        }
        return false;
      }

      bool ecgNormal = false;
      bool ecgAbnormal = false;
      bool ecgNotDone = false;

      if (rawEcg != null && rawEcg.isNotEmpty) {
        ecgNormal = isMarkedInLine(rawEcg, ['normal sinus', 'normal', 'सामान्य']);
        ecgAbnormal = isMarkedInLine(rawEcg, ['abnormal', 'असामान्य']);
        ecgNotDone = isMarkedInLine(rawEcg, ['not done', 'जाँच नगरिएको']);
      }

      if (!ecgNormal && !ecgAbnormal && !ecgNotDone) {
        final hasMultipleUncheckedChoices =
            ecgLower.contains('normal') && ecgLower.contains('abnormal');
        final hasEcgBoxes = rawEcg != null && RegExp(r'\[|\]|\(|\)|[☐口Ü☑☒]').hasMatch(rawEcg);
        if (rawEcg != null && rawEcg.isNotEmpty && !hasMultipleUncheckedChoices && !hasEcgBoxes) {
          if (ecgLower.contains('abnormal')) {
            ecgAbnormal = true;
          } else if (ecgLower.contains('normal') || ecgLower.contains('sinus')) {
            ecgNormal = true;
          } else if (ecgLower.contains('not done') || ecgLower.contains('not_done')) {
            ecgNotDone = true;
          }
        }
      }

      if (ecgAbnormal) {
        vitals['ecg'] = 'Abnormal';
      } else if (ecgNormal) {
        vitals['ecg'] = 'Normal Sinus';
      } else if (ecgNotDone) {
        vitals['ecg'] = 'Not Done';
      }

      // ECG Notes
      final rawEcgNotes = findValueForLabel(['ecg notes', 'ecg note', 'ईसीजी कैफियत']);
      if (rawEcgNotes != null && rawEcgNotes.isNotEmpty && !isNoiseOrSeparator(rawEcgNotes)) {
        vitals['ecgNotes'] = rawEcgNotes.trim();
      } else if (vitals['ecg'] != null) {
        vitals['ecgNotes'] = vitals['ecg'];
      }

      confidences['labs'] = 0.88;

      // ── POP Examination & Staging (Station 2 & Station 4) ──
      int? ant, mid, post;

      int? parsePopStage(String? val) {
        if (val == null) return null;
        final clean = val.replaceAll(RegExp(r'\([^)]*\)'), ' ').trim();

        // 1. Look for checkbox before stage: e.g. "X stage 2", "[x] stage 3", "☒ stage 1", "[x] 2"
        final markedBefore = RegExp(
          r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*(?:stage\s*)?([0-4])',
          caseSensitive: false,
        ).firstMatch(clean);
        if (markedBefore != null) {
          final s = markedBefore.group(1);
          if (s != null) return int.tryParse(s);
        }

        // 2. Look for checkbox bracket immediately after stage: e.g. "stage 2 [x]", "stage 2 (x)"
        final markedAfter = RegExp(
          r'(?:stage\s*)?([0-4])\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|\(\s*[xX✓✔•*+\#1\-]\s*\)|[☑☒])',
          caseSensitive: false,
        ).firstMatch(clean);
        if (markedAfter != null) {
          final s = markedAfter.group(1);
          if (s != null) return int.tryParse(s);
        }

        // 3. If single isolated digit or "stage N" without other stage numbers
        final allStages = RegExp(r'(?:stage\s*)?([0-4])\b', caseSensitive: false).allMatches(clean).toList();
        if (allStages.length == 1) {
          return int.tryParse(allStages.first.group(1)!);
        }

        return null;
      }

      ant = parsePopStage(
        lines.firstWhere(
          (l) {
            final low = l.toLowerCase();
            return low.contains('pop anterior') || low.contains('anterior wall') || low.contains('anterior compartment');
          },
          orElse: () => lines.firstWhere(
            (l) => l.toLowerCase().contains('anterior') && !l.toLowerCase().contains('normal or'),
            orElse: () => '',
          ),
        ),
      );
      mid = parsePopStage(
        lines.firstWhere(
          (l) {
            final low = l.toLowerCase();
            return low.contains('pop middle') || low.contains('middle part') || low.contains('middle compartment');
          },
          orElse: () => lines.firstWhere(
            (l) => l.toLowerCase().contains('middle') && !l.toLowerCase().contains('normal or'),
            orElse: () => '',
          ),
        ),
      );
      post = parsePopStage(
        lines.firstWhere(
          (l) {
            final low = l.toLowerCase();
            return low.contains('pop posterior') || low.contains('posterior wall') || low.contains('posterior compartment');
          },
          orElse: () => lines.firstWhere(
            (l) => l.toLowerCase().contains('posterior') && !l.toLowerCase().contains('normal or'),
            orElse: () => '',
          ),
        ),
      );

      ant ??= parsePopStage(findValueForLabel(['anterior compartment', 'anterior', 'cystocele', 'ant wall', 'anterior wall']));
      mid ??= parsePopStage(findValueForLabel(['middle compartment', 'middle', 'uterine', 'cervical', 'mid part', 'middle part']));
      post ??= parsePopStage(findValueForLabel(['posterior compartment', 'posterior', 'rectocele', 'post wall', 'posterior wall']));

      // Multi-column Baden-Walker table fallback: when numbers appear on lines below headers
      if (ant == null || mid == null || post == null) {
        final bwIdx = lowerText.indexOf('baden-walker');
        if (bwIdx != -1) {
          final bwSnippet = text.substring(bwIdx, min(text.length, bwIdx + 500));
          final isolatedDigits = <int>[];
          for (final l in bwSnippet.split(RegExp(r'[\r\n]+'))) {
            final trimmed = l.trim();
            if (RegExp(r'^[0-4]$').hasMatch(trimmed)) {
              isolatedDigits.add(int.parse(trimmed));
            }
          }
          if (isolatedDigits.length >= 3) {
            ant ??= isolatedDigits[0];
            mid ??= isolatedDigits[1];
            post ??= isolatedDigits[2];
          }
        }
      }

      // OMR override for POP compartments if pixel analysis detected marked boxes
      if (page2OmrPop != null && page2OmrPop.values.any((r) => r.isMarked)) {
        for (final entry in page2OmrPop.entries) {
          if (entry.value.isMarked) {
            if (entry.key.startsWith('anterior_')) {
              ant = int.tryParse(entry.key.split('_')[1]);
            } else if (entry.key.startsWith('middle_')) {
              mid = int.tryParse(entry.key.split('_')[1]);
            } else if (entry.key.startsWith('posterior_')) {
              post = int.tryParse(entry.key.split('_')[1]);
            }
          }
        }
      }

      // Station 4: Highest POP Stage Checkbox & Text Detection
      int? station4HighestPop;
      if (page2OmrPopHighest != null && page2OmrPopHighest.values.any((r) => r.isMarked)) {
        final marked = page2OmrPopHighest.values.firstWhere((r) => r.isMarked);
        station4HighestPop = int.tryParse(marked.id.split('_').last);
      }
      if (station4HighestPop == null) {
        final highestLine = lines.firstWhere(
          (l) => l.toLowerCase().contains('highest pop'),
          orElse: () => '',
        );
        if (highestLine.isNotEmpty) {
          station4HighestPop = parsePopStage(highestLine);
        }
      }

      final a = ant ?? 0;
      final m = mid ?? (station4HighestPop != null && station4HighestPop > 0 ? station4HighestPop : 0);
      final p = post ?? 0;
      var highest = [a, m, p].reduce(max);
      if (station4HighestPop != null && station4HighestPop > highest) {
        highest = station4HighestPop;
      }

      popStaging['anteriorStage'] = a;
      popStaging['middleStage'] = m;
      popStaging['posteriorStage'] = p;
      popStaging['highestPopStage'] = highest;

      // Uterus Inside detection
      bool? detectedUterusInside;
      for (final line in lines) {
        final low = line.toLowerCase();
        if (low.contains('uterus inside')) {
          final idx = low.indexOf('uterus inside') + 'uterus inside'.length;
          final after = line.substring(idx).split(RegExp(r'pelvic|vulva', caseSensitive: false)).first;
          final yesMarked = RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*yes|yes\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)', caseSensitive: false).hasMatch(after);
          final noMarked = RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*no|no\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)', caseSensitive: false).hasMatch(after);
          if (noMarked) {
            detectedUterusInside = false;
          } else if (yesMarked) {
            detectedUterusInside = true;
          }
          break;
        }
      }
      if (detectedUterusInside != null) {
        popStaging['uterusInside'] = detectedUterusInside;
      } else {
        final uterusOutside = isOptionSelected(['no (prolapsed)', 'prolapsed outside', 'uterus inside: no', 'uterus inside no']) ||
            (highest >= 2 && !isOptionSelected(['uterus inside: yes', 'uterus inside yes', 'uterus inside: 0 yes']));
        popStaging['uterusInside'] = !uterusOutside;
      }

      // 1. Vulva Examination (Station 2)
      String? detectedVulva;
      for (final line in lines) {
        final low = line.toLowerCase();
        if (low.startsWith('vulva') || (low.contains('vulva') && !low.contains('vagina'))) {
          final isNormalChecked = RegExp(
            r'vulva[^\r\n]*?(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•])\s*normal|vulva[^\r\n]*?normal\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•])',
            caseSensitive: false,
          ).hasMatch(line);
          final afterOr = RegExp(r'\bor\b[:\s_]*(.+)$', caseSensitive: false).firstMatch(line);
          final remarkText = (afterOr?.group(1) ?? '')
              .replaceAll(RegExp(r'\s{2,}(?:[xX✓✔]\s+)?stage\s*[0-4].*$', caseSensitive: false), '')
              .replaceAll(RegExp(r'[/\\|:_]'), '')
              .trim();
          if (remarkText.isNotEmpty && !remarkText.toLowerCase().contains('normal') && !isNoiseOrSeparator(remarkText)) {
            detectedVulva = remarkText;
          } else if (isNormalChecked || low.contains('normal')) {
            detectedVulva = 'Normal';
          }
          break;
        }
      }
      if (detectedVulva == null) {
        final vulvaVal = findValueForLabel(['vulva appearance', 'vulva:', 'vulva', 'भल्भा']);
        if (vulvaVal != null && vulvaVal.isNotEmpty && !vulvaVal.toLowerCase().contains('normal') && !isNoiseOrSeparator(vulvaVal)) {
          detectedVulva = vulvaVal.trim();
        } else if (isOptionSelected(['condyloma', 'कन्डाइलोमा', 'wart', 'warts'])) {
          detectedVulva = 'Condyloma';
        } else if (isOptionSelected(['ulcer', 'घाउ'])) {
          detectedVulva = 'Ulcer';
        } else if (isOptionSelected(['lichen sclerosus', 'lichen sclerosis', 'lichen'])) {
          detectedVulva = 'Lichen Sclerosus';
        } else if (isOptionSelected(['erythema', 'redness'])) {
          detectedVulva = 'Erythema';
        } else {
          detectedVulva = 'Normal';
        }
      }
      popStaging['vulvaRemarks'] = detectedVulva;

      // 2. Vagina Examination (Station 2)
      String? detectedVagina;
      for (final line in lines) {
        final low = line.toLowerCase();
        if ((low.startsWith('vagina') || (low.contains('vagina') && low.contains('normal or'))) &&
            !low.contains('atrophy vagina') &&
            !low.contains('vaginosis')) {
          if (low.contains('normal or')) {
            final afterOr = RegExp(r'\bnormal\s+or\b[:\s_]*(.*)$', caseSensitive: false).firstMatch(line);
            final remarkText = (afterOr?.group(1) ?? '')
                .replaceAll(RegExp(r'\s{2,}(?:[xX✓✔]\s+)?stage\s*[0-4].*$', caseSensitive: false), '')
                .replaceAll(RegExp(r'^[/\\|:_\s]+|[/\\|:_\s]+$'), '')
                .trim();
            if (remarkText.isNotEmpty && !remarkText.toLowerCase().contains('normal') && !isNoiseOrSeparator(remarkText)) {
              detectedVagina = remarkText;
            } else {
              detectedVagina = 'Normal';
            }
            break;
          }
        }
      }
      if (detectedVagina == null) {
        final vaginaVal = findValueForLabel(['vagina / vulva', 'vagina appearance', 'vagina:', 'vagina', 'योनी']);
        if (vaginaVal != null && vaginaVal.isNotEmpty) {
          detectedVagina = vaginaVal.trim();
        } else if (isOptionSelected(['atrophy', 'atrophic', 'सुकेको'])) {
          detectedVagina = 'Atrophic';
        } else if (isOptionSelected(['mild discharge', 'vaginal discharge'])) {
          detectedVagina = 'Mild discharge';
        } else {
          detectedVagina = 'Normal';
        }
      }
      popStaging['vaginaRemarks'] = detectedVagina;

      // 3. Cervix Appearance (Station 2)
      String? detectedCervix;
      for (final line in lines) {
        final low = line.toLowerCase();
        if (low.startsWith('cervix') ||
            (low.contains('cervix') &&
                low.contains('normal or') &&
                !low.contains('cervicitis'))) {
          if (low.contains('normal or')) {
            final afterOr = RegExp(r'\bnormal\s+or\b[:\s_]*(.*)$', caseSensitive: false).firstMatch(line);
            final remarkText = (afterOr?.group(1) ?? '')
                .replaceAll(RegExp(r'\s{2,}(?:[xX✓✔]\s+)?stage\s*[0-4].*$', caseSensitive: false), '')
                .replaceAll(RegExp(r'^[/\\|:_\s]+|[/\\|:_\s]+$'), '')
                .trim();
            if (remarkText.isNotEmpty && !remarkText.toLowerCase().contains('normal') && !isNoiseOrSeparator(remarkText)) {
              detectedCervix = remarkText;
            } else {
              detectedCervix = 'Normal';
            }
            break;
          }
        }
      }
      if (detectedCervix == null) {
        final cervixVal = findValueForLabel(['cervix appearance', 'cervix:', 'cervix', 'पाठेघरको मुख']);
        if (cervixVal != null && cervixVal.isNotEmpty) {
          detectedCervix = cervixVal.trim();
        } else if (isOptionSelected(['erosion', 'इरोज़न'])) {
          detectedCervix = 'Erosion';
        } else if (isOptionSelected(['polyp', 'पोलिप'])) {
          detectedCervix = 'Polyp';
        } else if (isOptionSelected(['hypertrophy', 'hypertrophied'])) {
          detectedCervix = 'Hypertrophy';
        } else {
          detectedCervix = 'Normal';
        }
      }
      popStaging['cervixRemarks'] = detectedCervix;

      // 4. Uterus Examination (Station 2)
      String? detectedUterus;
      for (final line in lines) {
        final low = line.toLowerCase();
        if (low.startsWith('uterus') || (low.contains('uterus') && !low.contains('cervix') && !low.contains('vulva') && !low.contains('inside'))) {
          final isNormalChecked = RegExp(
            r'uterus[^\r\n]*?(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•])\s*normal|uterus[^\r\n]*?normal\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•])',
            caseSensitive: false,
          ).hasMatch(line);
          final afterOr = RegExp(r'\bor\b[:\s_]*(.+)$', caseSensitive: false).firstMatch(line);
          final remarkText = (afterOr?.group(1) ?? '')
              .replaceAll(RegExp(r'\s{2,}(?:[xX✓✔]\s+)?stage\s*[0-4].*$', caseSensitive: false), '')
              .replaceAll(RegExp(r'[/\\|:_]'), '')
              .trim();
          if (remarkText.isNotEmpty && !remarkText.toLowerCase().contains('normal') && !isNoiseOrSeparator(remarkText)) {
            detectedUterus = remarkText;
          } else if (isNormalChecked || low.contains('normal')) {
            detectedUterus = 'Normal size';
          }
          break;
        }
      }
      if (detectedUterus == null) {
        final uterusVal = findValueForLabel(['uterus examination', 'uterus remarks', 'uterus:', 'पाठेघर सम्बन्धी']);
        if (uterusVal != null && uterusVal.isNotEmpty && !uterusVal.toLowerCase().contains('normal') && !isNoiseOrSeparator(uterusVal)) {
          detectedUterus = uterusVal.trim();
        } else if (isOptionSelected(['bulky', 'ठूलो', 'enlarged'])) {
          detectedUterus = 'Bulky';
        } else if (isOptionSelected(['tender', 'दुख्ने', 'tenderness'])) {
          detectedUterus = 'Tender';
        } else if (isOptionSelected(['fibroid', 'myoma'])) {
          detectedUterus = 'Fibroid';
        } else if (isOptionSelected(['atrophic uterus', 'atrophic'])) {
          detectedUterus = 'Atrophic';
        } else {
          detectedUterus = 'Normal size';
        }
      }
      popStaging['uterusRemarks'] = detectedUterus;

      if (page2OmrPop != null && (page2OmrPop['tone_weak']?.isMarked == true || page2OmrPop['tone_torn']?.isMarked == true || page2OmrPop['tone_normal']?.isMarked == true)) {
        if (page2OmrPop['tone_torn']?.isMarked == true) {
          popStaging['pelvicFloorTone'] = 'hypertonic';
        } else if (page2OmrPop['tone_weak']?.isMarked == true) {
          popStaging['pelvicFloorTone'] = 'weak';
        } else {
          popStaging['pelvicFloorTone'] = 'normal';
        }
      } else {
        final toneLine = lines.firstWhere((l) => l.toLowerCase().contains('pelvic floor muscle'), orElse: () => '');
        if (toneLine.isNotEmpty) {
          final cleanTone = toneLine.toLowerCase();
          if (RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*hypertonic').hasMatch(cleanTone)) {
            popStaging['pelvicFloorTone'] = 'hypertonic';
          } else if (RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*weak').hasMatch(cleanTone)) {
            popStaging['pelvicFloorTone'] = 'weak';
          } else if (RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*normal').hasMatch(cleanTone)) {
            popStaging['pelvicFloorTone'] = 'normal';
          } else {
            popStaging['pelvicFloorTone'] = highest >= 2 ? 'weak' : 'normal';
          }
        } else {
          if (isOptionSelected(['hypertonic', 'कडा'])) {
            popStaging['pelvicFloorTone'] = 'hypertonic';
          } else if (isOptionSelected(['weak tone', 'कमजोर tone']) || highest >= 2) {
            popStaging['pelvicFloorTone'] = 'weak';
          } else {
            popStaging['pelvicFloorTone'] = 'normal';
          }
        }
      }
      confidences['popStaging'] = 0.94;

      // ── Diagnoses (Station 4) ──
      void addDiag(String name) {
        if (!diagnoses.contains(name)) diagnoses.add(name);
      }

      if (page2OmrDiagnoses != null && page2OmrDiagnoses.values.any((r) => r.isMarked)) {
        for (final entry in page2OmrDiagnoses.entries) {
          if (entry.value.isMarked) {
            addDiag(entry.key);
          }
        }
      }

      // Scope Station 4, Station 5, and Station 6 lines to eliminate cross-station checkbox leakage
      final s4Lines = sliceLinesBetween(
            ['station 4', 'conclusion date:', 'highest pop stage:', 'diagnoses:'],
            ['station 5', 'treatment date:', 'pessary:', 'spec counseling:'],
          ) ??
          lines;
      final s5Lines = sliceLinesBetween(
            ['station 5', 'treatment date:', 'pessary:', 'medications:'],
            ['station 6', 'outtake date:', 'follow up:', 'follow-up:'],
          ) ??
          lines;
      final s6Lines = sliceLinesBetween(
            ['station 6', 'outtake date:', 'follow up:', 'follow-up:'],
            ['data entry operator', 'nurse signature', 'doctor signature'],
          ) ??
          lines;

      // 21 Canonical Yellow Form Diagnoses Text Checking (Scoped to Station 4)
      if (highest >= 2 || isOptionSelectedIn(s4Lines, ['pop', 'pelvic organ prolapse', 'पाठेघर खसेको', 'prolapse'])) {
        addDiag('POP');
      }
      if (isOptionSelectedIn(s4Lines, ['atrophy vagina', 'atrophic vagina', 'vaginal atrophy', 'atrophy', 'सुकेको'])) {
        addDiag('atrophy vagina');
      }
      if (isOptionSelectedIn(s4Lines, ['bacterial vaginosis', 'bv'])) {
        addDiag('bacterial vaginosis');
      }
      if (isOptionSelectedIn(s4Lines, ['candid infection', 'candidiasis', 'candidal infection', 'candida'])) {
        addDiag('candid infection');
      }
      if (isOptionSelectedIn(s4Lines, ['trichomonas', 'trichomoniasis', 'trich'])) {
        addDiag('trichomonas');
      }
      if (isOptionSelectedIn(s4Lines, ['pid', 'pelvic inflammatory disease', 'pelvic inflammatory'])) {
        addDiag('PID');
      }
      if (isOptionSelectedIn(s4Lines, ['cervicitis'])) {
        addDiag('cervicitis');
      }
      if (isOptionSelectedIn(s4Lines, ['cervical polyp', 'polyp', 'पोलिप'])) {
        addDiag('cervical polyp');
      }
      if (isOptionSelectedIn(s4Lines, ['cervical carcinoma', 'cervical cancer', 'carcinoma'])) {
        addDiag('cervical carcinoma');
      }
      if (isOptionSelectedIn(s4Lines, ['condylomata', 'condyloma', 'warts', 'wart'])) {
        addDiag('condylomata');
      }
      if (isOptionSelectedIn(s4Lines, ['fistula', 'vvf', 'rvf'])) {
        addDiag('fistula');
      }
      if (isOptionSelectedIn(s4Lines, ['infertility', 'infertile', 'बाँझोपन', 'निःसन्तान'])) {
        addDiag('infertility');
      }
      if (isOptionSelectedIn(s4Lines, ['myoma', 'fibroid', 'uterine fibroid'])) {
        addDiag('myoma');
      }
      if (isOptionSelectedIn(s4Lines, ['cystitis', 'uti', 'urinary tract infection'])) {
        addDiag('cystitis');
      }
      if (isOptionSelectedIn(s4Lines, ['lichen sclerosis', 'lichen sclerosus', 'lichen'])) {
        addDiag('lichen sclerosis');
      }
      if (isOptionSelectedIn(s4Lines, ['stress incontinence', 'sui'])) {
        addDiag('stress incontinence');
      }
      if (isOptionSelectedIn(s4Lines, ['ovarian tumor', 'ovarian mass', 'ovarian cyst'])) {
        addDiag('ovarian tumor');
      }
      if (isOptionSelectedIn(s4Lines, ['urge incontinence', 'uui'])) {
        addDiag('urge incontinence');
      }
      if (isOptionSelectedIn(s4Lines, ['menstrual disorder', 'abnormal uterine bleeding', 'aub', 'dysmenorrhea'])) {
        addDiag('menstrual disorder');
      }
      if (isOptionSelectedIn(s4Lines, ['weak pelvic floor muscle', 'weak pelvic floor'])) {
        addDiag('weak pelvic floor muscle');
      }
      if (isOptionSelectedIn(s4Lines, ['pregnancy', 'pregnant', 'गर्भ'])) {
        addDiag('pregnancy');
      }
      if (isOptionSelectedIn(s4Lines, ['hypertonic pelvic floor muscle', 'hypertonic pelvic floor'])) {
        addDiag('hypertonic pelvic floor muscle');
      }
      if (isOptionSelectedIn(s4Lines, ['hypertension']) || (vitals['systolicBp'] as int? ?? 0) >= 140) {
        addDiag('hypertension');
      }
      if (isOptionSelectedIn(s4Lines, ['diabetes mellitus', 'diabetes']) || (vitals['bloodGlucose'] as int? ?? 0) >= 180) {
        addDiag('diabetes mellitus');
      }
      // Custom "Other:" diagnosis in Station 4
      for (final l in s4Lines) {
        final om = RegExp(r'^other:[ \t]*([^\r\n]+)', caseSensitive: false).firstMatch(l.trim());
        if (om != null) {
          var customDiag = om.group(1)!.replaceAll(RegExp(r'^[_\s]+|[_\s]+$'), '').trim();
          customDiag = customDiag.split(RegExp(r'\s{3,}|clinical\s+notes|station\s*5', caseSensitive: false)).first.trim();
          if (customDiag.isNotEmpty && !isNoiseOrSeparator(customDiag)) {
            addDiag(customDiag);
          }
        }
      }
      confidences['diagnoses'] = diagnoses.isNotEmpty ? 0.92 : 0.40;

      // ── Prescriptions & Medications (All 10 Yellow Form Medications + custom other medication:) ──
      if (isOptionSelectedIn(s5Lines, ['clotrimazol', 'clotrimazole', 'canesten'])) {
        medications.add('clotrimazol (canesten)');
      }
      if (isOptionSelectedIn(s5Lines, ['estradiol', 'crème', 'creme'])) {
        medications.add('estradiol crème');
      }
      if (isOptionSelectedIn(s5Lines, ['metronidazol', 'metronidazole', 'me+ronida', 'flagyl'])) {
        medications.add('metronidazol');
      }
      if (isOptionSelectedIn(s5Lines, ['doxycycline', 'doxy'])) {
        medications.add('doxycycline');
      }
      if (isOptionSelectedIn(s5Lines, ['azithromycin', 'azithro'])) {
        medications.add('azithromycin');
      }
      if (isOptionSelectedIn(s5Lines, ['nitrofurantoine', 'nitrofurantoin'])) {
        medications.add('nitrofurantoine');
      }
      if (isOptionSelectedIn(s5Lines, ['medroxyprogesterone', 'progesterone'])) {
        medications.add('medroxyprogesterone');
      }
      if (isOptionSelectedIn(s5Lines, ['ciproflox', 'ciprofloxacin', 'cipro'])) {
        medications.add('ciproflox');
      }
      if (isOptionSelectedIn(s5Lines, ['mirasin'])) {
        medications.add('mirasin');
      }
      if (isOptionSelectedIn(s5Lines, ['clobetasol'])) {
        medications.add('clobetasol');
      }
      if (isOptionSelectedIn(s5Lines, ['fluconazole'])) {
        medications.add('Fluconazole');
      }
      for (final l in s5Lines) {
        final omm = RegExp(r'other\s+medication:[ \t]*([^\r\n]+)', caseSensitive: false).firstMatch(l.trim());
        if (omm != null) {
          var customMed = omm.group(1)!.replaceAll(RegExp(r'^[_\s]+|[_\s]+$'), '').trim();
          customMed = customMed.split(RegExp(r'\s{3,}|clinical\s+notes|station\s*6', caseSensitive: false)).first.trim();
          if (customMed.isNotEmpty && !isNoiseOrSeparator(customMed) && !medications.contains(customMed)) {
            medications.add(customMed);
          }
        }
      }

      // ── Specialized Counseling (Station 5: spec counseling) ──
      final counselingLines = s5Lines.where((l) => l.toLowerCase().contains('counseling')).toList();
      final effectiveCounselingLines = counselingLines.isNotEmpty ? counselingLines : (lowerText.contains('spec counseling') ? <String>[] : s5Lines);
      if (isOptionSelectedIn(effectiveCounselingLines, ['weak pelvic floor', 'pelvic floor', 'pfmt', 'केगेल'])) {
        counseling.add('Weak pelvic floor');
      }
      if (isOptionSelectedIn(effectiveCounselingLines, ['pop counseling', 'pop', 'prolapse', 'पाठेघर खसेको'])) {
        counseling.add('POP (Pelvic organ prolapse)');
      }
      if (isOptionSelectedIn(effectiveCounselingLines, ['stress incontinence', 'stress incont', 'खोक्दा पिसाब'])) {
        counseling.add('Stress incontinence');
      }
      if (isOptionSelectedIn(effectiveCounselingLines, ['urge incontinence', 'urge incont', 'हतारिने पिसाब'])) {
        counseling.add('Urge incontinence');
      }
      if (isOptionSelectedIn(effectiveCounselingLines, ['abdominal pain', 'abdom pain', 'पेट दुख्ने'])) {
        counseling.add('Abdominal pain');
      }

      // ── Pessary Fitting (Station 5: pessary) ──
      final pessaryLine = s5Lines.firstWhere((l) => l.toLowerCase().contains('pessary:'), orElse: () => '');
      final pLower = pessaryLine.toLowerCase();
      final markSupport = pessaryLine.isNotEmpty &&
          RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|(?:^|\s)[xX✓✔])\s*ring with support').hasMatch(pLower);
      final markKnob = pessaryLine.isNotEmpty &&
          RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|(?:^|\s)[xX✓✔])\s*ring with knob').hasMatch(pLower);
      final markRingOnly = pessaryLine.isNotEmpty &&
          RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|(?:^|\s)[xX✓✔])\s*ring(?!\s+with)\b').hasMatch(pLower);
      final markRingPessary = pessaryLine.isNotEmpty &&
          RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|(?:^|\s)[xX✓✔])\s*ring\s+pessary').hasMatch(pLower);
      if (markSupport || markKnob || markRingOnly || markRingPessary ||
          (pessaryLine.isEmpty && isOptionSelectedIn(s5Lines, ['ring pessary', 'ring with support', 'ring with knob']))) {
        ringPessary = true;
        if (markSupport) {
          pessaryType = 'ring with support';
        } else if (markKnob) {
          pessaryType = 'ring with knob';
        } else {
          pessaryType = 'ring';
        }
        if (markRingPessary && !medications.any((m) => m.toLowerCase().contains('pessary'))) {
          medications.add('Ring Pessary');
        }

        final s5Text = s5Lines.join('\n');
        final sizeMatch = RegExp(r'(?:size|साइज|sz)[:\s]*(\d{2,3})', caseSensitive: false).firstMatch(s5Text);
        final mmMatch = RegExp(r'(\d{2,3})\s*(?:mm|मिमी)', caseSensitive: false).firstMatch(s5Text);
        if (sizeMatch != null) {
          ringPessarySize = int.tryParse(sizeMatch.group(1)!);
        } else if (mmMatch != null) {
          ringPessarySize = int.tryParse(mmMatch.group(1)!);
        } else {
          for (final sz in [55, 60, 65, 70, 75, 80, 85]) {
            if (s5Text.toLowerCase().contains('${sz}mm') || s5Text.toLowerCase().contains('$sz mm')) {
              ringPessarySize = sz;
              break;
            }
          }
        }
      }

      confidences['medications'] = medications.isNotEmpty ? 0.85 : 0.40;

      // ── Referrals (Exact Yellow Form Station 5 Referral Options + Legacy Surgical Referral: line) ──
      final refLines = [...s5Lines, ...s6Lines];
      if (isOptionSelectedIn(refLines, ['scheer memorial', 'scheer'])) {
        surgicalReferral = 'Scheer Memorial Hospital';
      } else if (isOptionSelectedIn(refLines, ['model hosp', 'model hospital', 'model'])) {
        surgicalReferral = 'Model Hospital';
      } else if (isOptionSelectedIn(refLines, ['loc government', 'local government', 'loc gov', 'local gov', 'सरकारी'])) {
        surgicalReferral = 'Local Government Hospital';
      } else {
        for (final rl in refLines) {
          final rm = RegExp(r'surgical\s+referral:[ \t]*([^\r\n]+)', caseSensitive: false).firstMatch(rl);
          if (rm != null && !isNoiseOrSeparator(rm.group(1)!)) {
            final v = rm.group(1)!.toLowerCase();
            if (v.contains('scheer')) {
              surgicalReferral = 'Scheer Memorial Hospital';
            } else if (v.contains('model')) {
              surgicalReferral = 'Model Hospital';
            } else if (v.contains('gov') || v.contains('local')) {
              surgicalReferral = 'Local Government Hospital';
            } else {
              surgicalReferral = rm.group(1)!.trim();
            }
            break;
          }
        }
      }

      // ── Outtake Follow-up (Station 6 Left Column: isolate from right-column Clinical Notes) ──
      int? notesRawCol;
      int notesRawRow = -1;
      for (int r = 0; r < rawLayoutLines.length; r++) {
        final idx = rawLayoutLines[r].toLowerCase().indexOf('clinical notes');
        if (idx != -1) {
          notesRawCol = idx;
          notesRawRow = r;
          break;
        }
      }

      final List<String> s6LeftLines;
      if (notesRawCol != null && notesRawCol > 15 && notesRawRow != -1) {
        final leftBuf = <String>[];
        final s6StartRow = max(0, notesRawRow - 2);
        for (int r = s6StartRow; r < rawLayoutLines.length; r++) {
          final rl = rawLayoutLines[r];
          final low = rl.toLowerCase();
          if (low.contains('data entry operator') ||
              low.contains('nurse signature') ||
              low.contains('doctor signature')) {
            break;
          }
          final cut = min(rl.length, max(0, notesRawCol - 2));
          final leftPart = normalizeOcrText(rl.substring(0, cut)).trim();
          if (leftPart.isNotEmpty) leftBuf.add(leftPart);
        }
        s6LeftLines = leftBuf.isNotEmpty ? leftBuf : s6Lines;
      } else {
        s6LeftLines = s6Lines;
      }

      if (isOptionSelectedIn(s6LeftLines, ['health post', 'स्वास्थ्य चौकी'])) {
        followUp = 'Health Post';
      } else if (isOptionSelectedIn(s6LeftLines, ['gynaesupport nurse', 'gynaesupport', 'गाइने नर्स'])) {
        followUp = 'GynaeSupport Nurse';
      } else if (isOptionSelectedIn(s6LeftLines, ['no follow up needed', 'no follow up', 'no followup', 'अनुगमन नचाहिने'])) {
        followUp = 'No follow up needed';
      } else {
        for (final fl in s6LeftLines) {
          final hospFollowUp = RegExp(r'hospital:[ \t]+([^\r\n]+)', caseSensitive: false).firstMatch(fl);
          if (hospFollowUp != null) {
            final cand = hospFollowUp.group(1)!.replaceAll(RegExp(r'^[_\s]+|[_\s]+$'), '').trim();
            if (cand.isNotEmpty && !isNoiseOrSeparator(cand) && !cand.toLowerCase().contains('no follow')) {
              followUp = cand;
              break;
            }
          }
          final plainFollowUp = RegExp(r'^follow-?up:[ \t]+([^\r\n]+)', caseSensitive: false).firstMatch(fl.trim());
          if (plainFollowUp != null) {
            final cand = plainFollowUp.group(1)!.trim();
            if (cand.isNotEmpty && !isNoiseOrSeparator(cand)) {
              followUp = cand;
              break;
            }
          }
        }
      }
    }

    // ==========================================
    // Examining Doctor & Attending Nurse (Page 2 Footer / Signatures)
    // ==========================================
    final List<String> attendingDoctors = [];
    String? examiningDoctor;
    String? examiningNurse;
    final List<String> attendingNurses = [];

    bool isValidStaffName(String name) {
      final low = name.toLowerCase().trim();
      if (low.length < 3 || low.length > 40) return false;
      const nonStaffWords = {
        'married', 'unmarried', 'divorced', 'widow', 'widowed',
        'something hanging out', 'discharge and or itching', 'discharge', 'itching',
        'problems passing urine', 'menstrual problem', 'lower abdominal pain',
        'burning urination', 'something coming down', 'foul smelling discharge',
        'dyspareunia', 'postcoital bleeding', 'mass per vagina', 'white discharge',
        'cystocele', 'rectocele', 'uterine prolapse', 'cervical erosion',
        'pelvic inflammatory disease', 'pid', 'bacterial vaginosis', 'bv',
        'trichomoniasis', 'vulvovaginal candidiasis', 'uti', 'infertility',
        'myoma', 'cystitis', 'lichen', 'sui', 'uui', 'hypertension', 'diabetes',
        'normal', 'abnormal', 'stage 0', 'stage 1', 'stage 2', 'stage 3', 'stage 4',
        'yes', 'no', 'male', 'female', 'other', 'none', 'husband', 'father', 'guardian',
        'health post', 'hospital', 'camp', 'date', 'signature', 'stamp', 'ward',
        'deliveries', 'living children', 'abortions', 'obstetric', 'history',
        'examining doctor', 'attending nurse', 'data entry operator',
        'examining doctor (tick on paper)', 'attending nurse (tick on paper)',
        'nurse signature', 'doctor signature', 'gynaesupport nurse',
      };
      if (nonStaffWords.contains(low)) return false;
      if (low.contains('tick on paper') ||
          low.contains('examining doctor') ||
          low.contains('attending nurse') ||
          low.contains('data entry') ||
          low.contains('signature')) {
        return false;
      }
      return true;
    }

    if (!isPage1Only) {
      // Isolate footer region when present so checklist regexes never scan clinical stations
      int footerStartIdx = 0;
      for (int i = 0; i < lines.length; i++) {
        final low = lines[i].toLowerCase();
        if (low.contains('data entry operator') ||
            low.contains('attending nurse') ||
            low.contains('examining doctor') ||
            low.contains('tick on paper')) {
          footerStartIdx = max(0, i - 2);
          break;
        }
      }
      final footerLines = lines
          .sublist(footerStartIdx)
          .where((l) => !l.toLowerCase().startsWith('camp:') && !l.toLowerCase().startsWith('camp /'))
          .toList();
      final footerText = footerLines.join('\n');

      // 1. Multi-Doctor Checklist (supports both [x] and bare pdftotext X, with or without NMC inside parens)
      final checkedDoctorMatches = RegExp(
        r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|(?:^|\s)[xX✓✔])[ \t]*(?:Dr\.?|Doctor)[ \t]+([A-Za-z][A-Za-z\s\.]+?)(?=\s*(?:\(|\bNMC\b|\s{2,}|[\r\n]|$))',
        caseSensitive: false,
      ).allMatches(footerText);

      for (final m in checkedDoctorMatches) {
        var candidate = (m.group(1) ?? '').split(RegExp(r'[\r\n]')).first.trim();
        candidate = candidate.replaceAll(RegExp(r'\s*(?:NMC|Date|Signature|Stamp).*$', caseSensitive: false), '').trim();
        if (isValidStaffName(candidate) && !_isLabel(candidate) && !isNoiseOrSeparator(candidate)) {
          final formatted = candidate.toLowerCase().startsWith('dr') ? candidate : 'Dr. $candidate';
          if (!attendingDoctors.contains(formatted)) {
            attendingDoctors.add(formatted);
          }
        }
      }

      // 2. Multi-Nurse Checklist (supports bare pdftotext X + Name (RegNo) as well as [x] Name under Attending Nurse)
      final nurseHdrIdx = footerText.toLowerCase().indexOf('attending nurse');
      final nurseSubText = nurseHdrIdx != -1 ? footerText.substring(nurseHdrIdx) : footerText;
      final docAfterNurseIdx = nurseSubText.toLowerCase().indexOf('examining doctor');
      final isolatedNurseChecklist = docAfterNurseIdx != -1 ? nurseSubText.substring(0, docAfterNurseIdx) : nurseSubText;

      final checkedNurseMatches = [
        ...RegExp(
          r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|(?:^|\s)[xX✓✔])[ \t]*(?!Dr\.?\b|Doctor\b)(?:(?:Staff\s+Nurse|Nurse|Sr\.?|Sister)[ \t]+)?([A-Za-z][A-Za-z\s\.]+?)\s*\(\s*(?:NNC[:\s\-]*)?[A-Za-z0-9/\-]+\s*\)',
          caseSensitive: false,
        ).allMatches(footerText),
        ...RegExp(
          r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•])[ \t]*(?!Dr\.?\b|Doctor\b|Other\b)(?:(?:Staff\s+Nurse|Nurse|Sr\.?|Sister)[ \t]+)?([A-Za-z][A-Za-z\s\.]+?)(?=\s*(?:\(|\bNNC\b|[\r\n]|$))',
          caseSensitive: false,
        ).allMatches(isolatedNurseChecklist),
      ];

      for (final m in checkedNurseMatches) {
        var candidate = (m.group(1) ?? '').split(RegExp(r'[\r\n]')).first.trim();
        candidate = candidate.replaceAll(RegExp(r'\s*(?:NNC|Date|Signature|Stamp).*$', caseSensitive: false), '').trim();
        candidate = candidate.replaceFirst(RegExp(r'^staff\s+nurse\s+', caseSensitive: false), '').trim();
        final cleanNurse = NurseProfile.stripPrefixes(candidate).trim();
        if (isValidStaffName(cleanNurse) &&
            !_isLabel(cleanNurse) &&
            !isNoiseOrSeparator(cleanNurse) &&
            !cleanNurse.toLowerCase().startsWith('dr.') &&
            !cleanNurse.toLowerCase().contains('doctor')) {
          if (!attendingNurses.contains(cleanNurse)) {
            attendingNurses.add(cleanNurse);
          }
        }
      }

      // 3. Single Pre-Printed 3-Column Signature Row: "Data Entry Operator   <Nurse Name>   Dr. <Doctor Name>"
      if (attendingDoctors.isEmpty || attendingNurses.isEmpty) {
        for (final fl in footerLines) {
          if (fl.toLowerCase().contains('data entry operator')) {
            final cols = fl
                .split(RegExp(r'\s{3,}'))
                .map((c) => c.trim())
                .where((c) => c.isNotEmpty)
                .toList();
            for (final col in cols) {
              final cLow = col.toLowerCase();
              if (cLow.contains('data entry')) continue;
              if (cLow.startsWith('dr.') || cLow.startsWith('dr ')) {
                if (attendingDoctors.isEmpty) {
                  final cleanDoc = col.replaceAll(RegExp(r'\s*\(.*$'), '').trim();
                  if (isValidStaffName(cleanDoc)) {
                    attendingDoctors.add(cleanDoc);
                  }
                }
              } else if (attendingNurses.isEmpty && !cLow.contains('doctor') && !cLow.contains('tick on paper')) {
                final cleanNurse = NurseProfile.stripPrefixes(col.replaceAll(RegExp(r'\s*\(.*$'), '').trim()).trim();
                if (isValidStaffName(cleanNurse) && !_isLabel(cleanNurse) && !isNoiseOrSeparator(cleanNurse)) {
                  attendingNurses.add(cleanNurse);
                }
              }
            }
          }
        }
      }

      // 4. Fallback line-by-line Dr. / Nurse prefix scan inside footerLines
      if (attendingDoctors.isEmpty) {
        for (final line in footerLines) {
          final m = RegExp(
            r'(?:(?:examining\s*doctor|doctor\s*signature(?:\s*&\s*nmc)?|doctor|clinician|gynecologist)[ \t]*[:\-]?[ \t]*)?(?:Dr\.?[ \t]+)([A-Za-z][A-Za-z\s\.]+?)(?=\s*(?:\(|\bNMC\b|[\r\n]|$))',
            caseSensitive: false,
          ).firstMatch(line);
          if (m != null) {
            final candidate = (m.group(1) ?? '').trim();
            if (isValidStaffName(candidate) && !_isLabel(candidate) && !isNoiseOrSeparator(candidate)) {
              attendingDoctors.add(candidate.toLowerCase().startsWith('dr') ? candidate : 'Dr. $candidate');
              break;
            }
          }
        }
      }

      if (attendingNurses.isEmpty) {
        for (final line in footerLines) {
          final m = RegExp(
            r'(?:(?:attending\s*nurse|staff\s*nurse|examining\s*nurse)[ \t]*:[ \t]*(?:(?:Staff\s+Nurse|Nurse|Sr\.?|Sister)[ \t]+)?([A-Za-z][A-Za-z\s\.]+?)(?=\s*(?:\(|\bNNC\b|\d|[\r\n]|$)))'
            r'|(?:(?:attending\s*nurse|staff\s*nurse|examining\s*nurse)[ \t]*[:\-]?[ \t]*)?(?:Staff\s+Nurse|Nurse|Sr\.?|Sister)[ \t]+([A-Za-z][A-Za-z\s\.]+?)(?=\s*(?:\(|\bNNC\b|\d|[\r\n]|$))',
            caseSensitive: false,
          ).firstMatch(line);
          if (m != null) {
            var rawCand = (m.group(1) ?? m.group(2) ?? '').trim();
            rawCand = rawCand.replaceFirst(RegExp(r'^staff\s+nurse\s+', caseSensitive: false), '').trim();
            final cleanNurse = NurseProfile.stripPrefixes(rawCand).trim();
            if (isValidStaffName(cleanNurse) && !_isLabel(cleanNurse) && !isNoiseOrSeparator(cleanNurse)) {
              attendingNurses.add(cleanNurse);
              break;
            }
          }
        }
      }

      if (attendingDoctors.isNotEmpty) {
        examiningDoctor = attendingDoctors.first;
      }
      if (attendingNurses.isNotEmpty) {
        examiningNurse = attendingNurses.first;
      }
    }

    // ── Consultation (परामर्श) ──
    String? treatmentLevel;
    if (page1OmrTreatmentLevel != null && page1OmrTreatmentLevel.values.any((r) => r.isMarked)) {
      final marked = page1OmrTreatmentLevel.values.firstWhere((r) => r.isMarked);
      treatmentLevel = (marked.id == 'council_level' || marked.id == 'counseling') ? 'counseling' : 'gyno_checkup';
      confidences['treatmentLevel'] = marked.confidence;
    } else if (isOptionSelected(['counseling', 'council level', 'काउन्सिलिङ तह', 'काउन्सिलिङ', 'counseling level', 'counsel level', 'council'])) {
      treatmentLevel = 'counseling';
      confidences['treatmentLevel'] = 0.90;
    } else if (isOptionSelected(['gynocheckup', 'gyno checkup', 'गाइनो जाँच', 'full check up', 'full checkup', 'पूर्ण जाँच', 'full check', 'पूर्ण'])) {
      treatmentLevel = 'gyno_checkup';
      confidences['treatmentLevel'] = 0.90;
    } else {
      final treatmentMatch = RegExp(
        r'(?:consultation|level\s*of\s*treatment|treatment\s*level|परामर्श|उपचारको\s*तह)[:\s]+(counsel[^\r\n]*|council[^\r\n]*|gyno[^\r\n]*|full[^\r\n]*|पूर्ण[^\r\n]*|काउन्सिलिङ[^\r\n]*|गाइनो[^\r\n]*)',
        caseSensitive: false,
      ).firstMatch(text);
      if (treatmentMatch != null) {
        final val = treatmentMatch.group(1)?.toLowerCase() ?? '';
        final hasCounsel = val.contains('counsel') || val.contains('council') || val.contains('काउन्सिलिङ');
        final hasGyno = val.contains('gyno') || val.contains('full') || val.contains('गाइनो') || val.contains('पूर्ण');
        // Ignore unmarked multi-option form header ("CONSULTATION: Counseling Gynocheckup")
        if (hasCounsel && !hasGyno) {
          treatmentLevel = 'counseling';
          confidences['treatmentLevel'] = 0.85;
        } else if (hasGyno && !hasCounsel) {
          treatmentLevel = 'gyno_checkup';
          confidences['treatmentLevel'] = 0.85;
        }
      }
    }

    // ── Station 6: Clinical Notes / Outtake Remarks (Multi-line Right Column Box) ──
    String? clinicalNotes;
    if (!isPage1Only) {
      int? notesCol;
      int notesRow = -1;
      for (int r = 0; r < rawLayoutLines.length; r++) {
        final idx = rawLayoutLines[r].toLowerCase().indexOf('clinical notes');
        if (idx != -1) {
          notesCol = idx;
          notesRow = r;
          break;
        }
      }
      if (notesCol != null && notesRow != -1) {
        final noteParts = <String>[];
        // Check inline text after "Clinical Notes / Outtake Remarks:" on header row if any
        final hdrSlice = rawLayoutLines[notesRow].substring(notesCol);
        final colonIdx = hdrSlice.indexOf(':');
        if (colonIdx != -1) {
          final inlineNote = hdrSlice.substring(colonIdx + 1).trim();
          if (inlineNote.isNotEmpty && !isNoiseOrSeparator(inlineNote)) {
            noteParts.add(inlineNote);
          }
        }
        // Collect wrapped lines inside the right-hand Clinical Notes box
        for (int r = notesRow + 1; r < rawLayoutLines.length; r++) {
          final rl = rawLayoutLines[r];
          final low = rl.toLowerCase();
          if (low.contains('data entry operator') ||
              low.contains('attending nurse') ||
              low.contains('examining doctor') ||
              low.contains('nurse signature') ||
              low.contains('doctor signature') ||
              RegExp(r'_{6,}').hasMatch(rl)) {
            break;
          }
          final sliceStart = max(0, notesCol - 2);
          if (rl.length > sliceStart) {
            final rightChunk = rl.substring(sliceStart).trim();
            if (rightChunk.isNotEmpty && !isNoiseOrSeparator(rightChunk)) {
              noteParts.add(rightChunk);
            }
          }
        }
        if (noteParts.isNotEmpty) {
          clinicalNotes = noteParts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        }
      }
      if (clinicalNotes == null) {
        final notesVal = findValueForLabel([
          'clinical notes / outtake remarks', 'clinical notes', 'outtake remarks', 'discharge notes',
        ]);
        if (notesVal != null && notesVal.isNotEmpty && !isNoiseOrSeparator(notesVal)) {
          clinicalNotes = notesVal.trim();
        }
      }
    }

    // ── Station Dates (Page 1 Intake, Station 2 Exam, Station 3 Labs, Station 4 Conclusion, Station 5 Treatment, Station 6 Outtake) ──
    String? extractDateForLabel(List<String> labels) {
      for (final line in lines) {
        final low = line.toLowerCase();
        for (final l in labels) {
          final lLow = l.toLowerCase();
          final idx = low.indexOf(lLow);
          if (idx != -1) {
            final after = line.substring(idx + l.length).trim();
            final parsed = _extractDynamicDate(after);
            if (parsed != null) return parsed;
          }
        }
      }
      return null;
    }

    final rawAnamnesisDate = extractDateForLabel(['anamnesis date:', 'anamnesis date', 'विगत मिति']);
    final parsedIntakeDate = extractDateForLabel(['intake date:', 'intake date', 'registration date:', 'registration date', 'दर्ता मिति:', 'दर्ता मिति', 'date:', 'date', 'मिति:', 'मिति']) ??
        _extractDynamicDate(text);
    final effectiveIntake = parsedIntakeDate?.trim() ?? rawAnamnesisDate?.trim();
    final effectiveAnamnesis = rawAnamnesisDate?.trim() ?? parsedIntakeDate?.trim();
    if (effectiveIntake != null && effectiveIntake.isNotEmpty) {
      demographics['intakeDate'] = effectiveIntake;
      demographics['date'] = effectiveIntake;
    }
    if (effectiveAnamnesis != null && effectiveAnamnesis.isNotEmpty) {
      demographics['anamnesisDate'] = effectiveAnamnesis;
    }
    final examDate = extractDateForLabel(['examination date:', 'exam date:', 'examination date', 'exam date', 'जाँच मिति']);
    final labTestDate = extractDateForLabel(['lab test date:', 'lab test date', 'प्रयोगशाला मिति']);
    final conclusionDate = extractDateForLabel(['conclusion date:', 'conclusion date', 'निष्कर्ष मिति', 'निदान मिति']);
    final treatmentDate = extractDateForLabel(['treatment date:', 'treatment date', 'उपचार मिति']);
    final outtakeDate = extractDateForLabel(['outtake date:', 'outtake date', 'डिस्चार्ज मिति']);

    final totalConf = confidences.values.fold<double>(0.0, (sum, val) => sum + val);
    final avgConf = confidences.isNotEmpty ? totalConf / confidences.length : 0.80;

    return OcrScanResultModel(
      pageNumber: pageNumber,
      imagePath: imagePath,
      demographics: demographics,
      obstetrics: obstetrics,
      vitals: vitals,
      popStaging: popStaging,
      diagnoses: diagnoses,
      counseling: counseling,
      medications: medications,
      surgicalReferral: surgicalReferral,
      followUpDestination: followUp,
      ringPessary: ringPessary,
      pessaryType: pessaryType,
      ringPessarySize: ringPessarySize,
      examiningDoctor: examiningDoctor,
      attendingDoctors: attendingDoctors,
      examiningNurse: examiningNurse,
      attendingNurses: attendingNurses,
      treatmentLevel: PatientModel.normalizeTreatmentLevel(treatmentLevel),
      clinicalNotes: clinicalNotes,
      intakeDate: effectiveIntake,
      anamnesisDate: effectiveAnamnesis,
      examDate: examDate?.trim(),
      treatmentDate: treatmentDate,
      conclusionDate: conclusionDate,
      labTestDate: labTestDate,
      outtakeDate: outtakeDate,
      fieldConfidences: confidences,
      overallConfidence: double.parse(avgConf.toStringAsFixed(2)),
      rawText: text,
      scannedAt: DateTime.now(),
    );
  }

  /// Check if a line looks like a label header (not a value)
  static bool _isLabel(String line) {
    final lower = line.toLowerCase().trim();
    if (lower.isEmpty) return true;
    if (lower.endsWith(':')) return true;
    if (lower.startsWith('station') ||
        lower.startsWith('camp') ||
        lower.startsWith('date') ||
        lower == 'doctor' ||
        lower == 'dr.' ||
        lower == 'dr' ||
        lower == 'nurse' ||
        lower.contains('form') ||
        lower.contains('gynocamp') ||
        lower.contains('ministry of health') ||
        lower.contains('patient registration') ||
        lower.contains('for official use only')) {
      return true;
    }
    // Check if line is a header row containing multiple field labels (e.g. "First Name: Ward: Surname: Age:")
    if (lower.contains(':') && (lower.contains('name:') || lower.contains('ward:') || lower.contains('age:') || lower.contains('mobile:') || lower.contains('palika:') || lower.contains('district:'))) {
      final labelCount = RegExp(r'\b[a-z\s]+:', caseSensitive: false).allMatches(lower).length;
      if (labelCount >= 2) return true;
    }
    return false;
  }

  /// Capitalize first letter of a word
  static String _capitalizeFirst(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  /// Extracts and normalizes any dynamic date (BS or AD) from text, handling Devanagari numerals
  static String? _extractDynamicDate(String input) {
    if (input.trim().isEmpty) return null;
    var clean = input;
    const dev = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];
    for (int i = 0; i < dev.length; i++) {
      clean = clean.replaceAll(dev[i], i.toString());
    }
    final m = RegExp(r'\b(\d{4})[-/](\d{1,2})[-/](\d{1,2})\b').firstMatch(clean);
    if (m != null) {
      final y = m.group(1)!;
      final mo = m.group(2)!.padLeft(2, '0');
      final d = m.group(3)!.padLeft(2, '0');
      return '$y-$mo-$d';
    }
    return null;
  }

  /// Pre-processes and normalizes raw OCR text to resolve common artifacts:
  /// - Spaced digits from character boxes (BP, Pulse, SpO2, Glucose, Phone)
  /// - Spaced uppercase letters from block-letter grid boxes (e.g. M A Y A -> MAYA)
  /// - Common OCR letter/digit confusions in medical values
  static String normalizeOcrText(String raw) {
    var text = raw;

    // 0. Decode OCR circled/cross box symbols: '@' or circled marks as checked boxes '[x]'
    text = text.replaceAll(RegExp(r'(?:^|(?<=\s))@\s*'), '[x] ');

    // 0.5 Collapse spaced characters for Patient Token ID: "G C - D H N - 2 0 2 6 - 0 0 0 4 2" or "GC-DHN-2026- 0 0 0 4 2"
    text = text.replaceAllMapped(
      RegExp(r'\b(?:G[ \t]*C|GC)[ \t]*-[ \t]*([A-Za-z0-9_][A-Za-z0-9_ \t]{1,9})[ \t]*-[ \t]*(\d[ \t]*\d[ \t]*\d[ \t]*\d)[ \t]*-[ \t]*([0-9][0-9 \t]{0,10})(?=[^0-9A-Za-z]|$)', caseSensitive: false),
      (m) {
        final code = m[1]!.replaceAll(RegExp(r'[ \t]+'), '').toUpperCase();
        final year = m[2]!.replaceAll(RegExp(r'[ \t]+'), '');
        final seq = m[3]!.replaceAll(RegExp(r'[ \t]+'), '');
        return 'GC-$code-$year-$seq';
      },
    );
    text = text.replaceAllMapped(
      RegExp(r'\b(?:token(?:[ \t]*id|[ \t]*no)?|बिरामी[ \t]*टोकन(?:[ \t]*नं)?)[ \t]*[:\-]?[ \t]*(\d)[ \t]+(\d)[ \t]+(\d)(?:[ \t]+(\d))?(?:[ \t]+(\d))?', caseSensitive: false),
      (m) => 'Token ID: ${m[1]}${m[2]}${m[3]}${m[4] ?? ""}${m[5] ?? ""}',
    );

    // 0.8 Collapse spaced characters for BS dates: "2 0 8 3 - 0 6 - 0 6 BS" -> "2083-06-06 BS"
    text = text.replaceAllMapped(
      RegExp(r'\b(\d)\s+(\d)\s+(\d)\s+(\d)\s*[-/]\s*(\d)(?:\s+(\d))?\s*[-/]\s*(\d)(?:\s+(\d))?(?:\s*B\s*S)?\b'),
      (m) {
        final y = '${m[1]}${m[2]}${m[3]}${m[4]}';
        final mo = (m[6] != null) ? '${m[5]}${m[6]}' : m[5]!.padLeft(2, '0');
        final d = (m[8] != null) ? '${m[7]}${m[8]}' : m[7]!.padLeft(2, '0');
        return '$y-$mo-$d BS';
      },
    );

    // 1. Collapse spaced single digits for Nepali mobile numbers: "9 8 4 1 9 8 7 6 5 4" -> "9841987654"
    text = text.replaceAllMapped(
      RegExp(r'\b([qgQG9])\s*(\d)\s+(\d)\s+(\d)\s+(\d)\s+(\d)\s+(\d)\s+(\d)\s+(\d)\s+(\d)\b'),
      (m) => '9${m[2]}${m[3]}${m[4]}${m[5]}${m[6]}${m[7]}${m[8]}${m[9]}${m[10]}',
    );

    // 2. Collapse spaced single digits for BP: "1 3 0 / 8 5" -> "130/85"
    text = text.replaceAllMapped(
      RegExp(r'(\d)\s+(\d)(?:\s+(\d))?\s*[/|\\]\s*(\d)\s+(\d)(?:\s+(\d))?'),
      (m) => '${m[1]}${m[2]}${m[3] ?? ""}/${m[4]}${m[5]}${m[6] ?? ""}',
    );

    // 3. Collapse spaced digits for Pulse: "Pulse: 7 8" or "7 8 bpm" -> "Pulse: 78 bpm"
    text = text.replaceAllMapped(
      RegExp(r'\b(?:pulse(?:\s*rate)?|pr|hr)\b[:\s]*(\d)\s+(\d)(?:\s+(\d))?', caseSensitive: false),
      (m) => 'Pulse: ${m[1]}${m[2]}${m[3] ?? ""}',
    );
    text = text.replaceAllMapped(
      RegExp(r'\b(\d)\s+(\d)(?:\s+(\d))?\s*bpm\b', caseSensitive: false),
      (m) => '${m[1]}${m[2]}${m[3] ?? ""} bpm',
    );

    // 4. Collapse spaced digits for SpO2: "sp02: 9 8" or "9 8 %" -> "SpO2: 98%"
    text = text.replaceAllMapped(
      RegExp(r'(?:spo2|sp02|saturation)\b[:\s]*(\d)\s+(\d)(?:\s+(\d))?', caseSensitive: false),
      (m) => 'SpO2: ${m[1]}${m[2]}${m[3] ?? ""}',
    );
    text = text.replaceAllMapped(
      RegExp(r'\b(\d)\s+(\d)(?:\s+(\d))?\s*%', caseSensitive: false),
      (m) => '${m[1]}${m[2]}${m[3] ?? ""}%',
    );

    // 5. Collapse spaced digits for Glucose: "glucose: 1 1 5" or "1 1 5 mg" -> "Glucose: 115 mg/dL"
    text = text.replaceAllMapped(
      RegExp(r'(?:glucose|sugar|rbs)\b[:\s]*(\d)\s+(\d)\s+(\d)', caseSensitive: false),
      (m) => 'Glucose: ${m[1]}${m[2]}${m[3]}',
    );

    // 6. Normalize common OCR duration mangling: "> I year", "> l year", "> | year" -> "> 1 year"
    text = text.replaceAll(RegExp(r'>\s*[Il|]\s*year', caseSensitive: false), '> 1 year');

    // 7. Collapse spaced single uppercase letters (block-letter boxes):
    // E.g. "M A Y A" -> "MAYA", "T A M A N G" -> "TAMANG", "S OM" -> "SOM", "T AMANG" -> "TAMANG"
    text = text.replaceAllMapped(
      RegExp(r'\b([A-Z])(?:[ \t]{1,2}([A-Z])){1,}\b'),
      (m) {
        final match = m.group(0)!;
        final letters = match.split(RegExp(r'[ \t]+'));
        if (letters.length >= 2 && letters.every((l) => l.length == 1 && RegExp(r'[A-Z]').hasMatch(l))) {
          return letters.join('');
        }
        return match;
      },
    );
    // Collapse single capital letter separated by 1-2 spaces from uppercase word chunk (e.g. "T AMANG" -> "TAMANG", "S OM" -> "SOM")
    // Preserve checkmark 'X' before uppercase medical acronyms (e.g. "X PID", "X POP", "X ECG")
    text = text.replaceAllMapped(
      RegExp(r'\b([A-Z])[ \t]{1,2}([A-Z]{2,})\b'),
      (m) {
        if (m[1] == 'X') return m.group(0)!;
        return '${m[1]}${m[2]}';
      },
    );
    text = text.replaceAllMapped(
      RegExp(r'\b([A-Z]{2,})[ \t]{1,2}([A-Z])\b'),
      (m) {
        if (m[2] == 'X') return m.group(0)!;
        return '${m[1]}${m[2]}';
      },
    );

    return text;
  }

  /// Merges Page 1 (Front: Demographics & Anamnesis) and Page 2 (Back: POP Staging & Prescriptions)
  OcrScanResultModel mergeScans(OcrScanResultModel page1, OcrScanResultModel page2) {
    return OcrScanResultModel.merge(page1, page2);
  }

  // ==========================================
  // High-Fidelity Pre-Configured Samples
  // ==========================================

  /// Sample 1: Front Page (Intake & Obstetric History)
  /// Labels MUST match what ocr_form_service.dart parsers search for.
  static const String samplePage1Text = '''
GYNOCAMP RURAL HEALTH CLINICAL INTAKE FORM (YELLOW FORM - PAGE 1)
Camp Code: KTM01    Date: 2026-09-06
First Name: MAYA
Surname: TAMANG
Patient Age: 44
Marital Status: [x] Married
Husband's Name: SOM BAHADUR TAMANG
Mobile: 9841987654
Contact Person: BISHAL TAMANG (SON)
Contact Mobile: 9851234567
Age at Marriage: 18
District: KATHMANDU
Municipality: BUDHANILKANTHA
Ward: 04
Province: Bagmati

Reasons for Visit:
[x] something hanging out
[x] discharge and or itching
[x] problems passing urine
[x] menstrual problem

OBSTETRIC HISTORY:
Deliveries: 3
Living Children: 3
Abortions: 0
Complaints Duration: > 1 year
Clinical Complaints:
[x] Mass Per Vagina
[x] White / Foul Discharge
[x] Pelvic Heaviness
Consent: [x] Treatment Informed Consent Granted
[x] Medical information storage consent granted
''';


  /// Sample 2: Back Page (Vitals, POP Examination, Diagnoses & Treatment)
  static const String samplePage2Text = '''
GYNOCAMP CLINICAL ASSESSMENT & EXAMINATION (YELLOW FORM - PAGE 2)
Station 1: Anamnesis & Obstetric History
Deliveries: 3
Living Children: 3
Abortions: 0
Complaints Duration: 3-12 months
Clinical Complaints:
[x] Mass Per Vagina
[x] White / Foul Discharge
[x] Pelvic Heaviness
[x] Lower Abdominal Pain

Station 2: Pelvic Organ Prolapse (POP) Examination
Uterus Inside: No (Prolapsed outside introitus)
Pelvic Floor Tone: Weak
Anterior Compartment Stage: 2
Middle Compartment Stage: 3
Posterior Compartment Stage: 1
Cervix Appearance: Erosion
Vagina / Vulva: Mild discharge

Station 3: Point-of-Care Lab Tests & Vitals
Blood Pressure: 130/85 mmHg
Pulse Rate: 78 bpm
SpO2: 98%
Blood Glucose: 115 mg/dL
Urine Test: Normal
Pregnancy Test: Neg

Station 4: Confirmed Diagnoses
Diagnoses:
[x] POP (Pelvic Organ Prolapse Stage 3)
[x] candid infection (Candidiasis)
[x] hypertension (Pre-hypertension monitor)

Station 5: Treatments & Prescriptions
Pessary: [x] Ring Pessary: ring (Size 65mm fitted)
Medications:
[x] clotrimazol (canesten)
[x] metronidazol

Station 6: Outtake & Referral
Surgical Referral: Scheer Memorial Hospital (Vaginal Hysterectomy evaluation)
Follow-up: Scheer Memorial Hospital
''';

  /// Sample 3: Full 2-Page Combined Intake
  static const String sampleFullFormText = '''
$samplePage1Text
----------------------------------------
$samplePage2Text
''';
}
