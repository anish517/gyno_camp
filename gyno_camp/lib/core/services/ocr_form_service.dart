import 'dart:io';
import 'dart:math';
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

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final lowerLine = line.toLowerCase();
        for (final label in labels) {
          final labelLower = label.toLowerCase();
          if (lowerLine.contains(labelLower)) {
            final labelIdx = lowerLine.indexOf(labelLower);
            final afterLabel = line.substring(labelIdx + label.length).trim();
            var afterVal = afterLabel;
            if (afterVal.startsWith('/') && afterVal.contains(':')) {
              afterVal = afterVal.substring(afterVal.indexOf(':') + 1).trim();
            }

            var value = afterVal.replaceFirst(RegExp(r'^[/:=\s\\-]+'), '').trim();
            // Cut off at the next header label on the same line if multiple labels are present
            final nextLabelMatch = RegExp(
              r'\b(?:' + knownLabelStems.map(RegExp.escape).join('|') + r')\b[:\s_]',
              caseSensitive: false,
            ).firstMatch(value);
            if (nextLabelMatch != null) {
              value = value.substring(0, nextLabelMatch.start).trim();
            }

            if (value.isNotEmpty && !_isLabel(value) && !isNoiseOrSeparator(value)) {
              return value;
            }

            if (multiLine && i + 1 < lines.length) {
              final nextLine = lines[i + 1].trim();
              if (nextLine.isNotEmpty && !_isLabel(nextLine) && !isNoiseOrSeparator(nextLine)) {
                // Determine columnar slice if multiple labels exist on header line
                final lineAfterCurrent = line.substring(labelIdx + label.length);
                final nextHeaderCol = RegExp(
                  r'\b(?:' + knownLabelStems.map(RegExp.escape).join('|') + r')\b[:\s_]',
                  caseSensitive: false,
                ).firstMatch(lineAfterCurrent);

                if (nextHeaderCol != null && lines[i + 1].length > labelIdx) {
                  final colStart = max(0, labelIdx - 6).clamp(0, lines[i + 1].length);
                  final colEnd = (labelIdx + label.length + nextHeaderCol.start).clamp(colStart, lines[i + 1].length);
                  final rawCol = lines[i + 1].substring(colStart, colEnd).trim();
                  final colVal = rawCol.split(RegExp(r'\s{3,}')).first.trim();
                  if (colVal.isNotEmpty && !isNoiseOrSeparator(colVal) && !_isLabel(colVal)) {
                    return colVal;
                  }
                } else if (lines[i + 1].length > labelIdx) {
                  final rawCol = lines[i + 1].substring(labelIdx).trim();
                  final colVal = rawCol.split(RegExp(r'\s{3,}')).first.trim();
                  if (colVal.isNotEmpty && !isNoiseOrSeparator(colVal) && !_isLabel(colVal)) {
                    return colVal;
                  }
                }
                return nextLine;
              }
            }
          }
        }
      }
      return null;
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
        final digits = rawTokenVal.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.isNotEmpty && digits.length <= 6) {
          extractedTokenId = digits.padLeft(5, '0');
        } else if (RegExp(r'GC-[A-Za-z0-9_-]+-\d{4}-\d{1,6}', caseSensitive: false).hasMatch(rawTokenVal)) {
          final m = RegExp(r'GC-([A-Za-z0-9_-]+)-(\d{4})-(\d{1,6})', caseSensitive: false).firstMatch(rawTokenVal);
          if (m != null) {
            extractedTokenId = 'GC-${m.group(1)!.toUpperCase()}-${m.group(2)}-${m.group(3)!.padLeft(5, "0")}';
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
      if (relValue != null && relValue.isNotEmpty) {
        var relName = relValue.replaceAll(RegExp(r'\s*\(.*?\)\s*$'), '').trim();
        relName = relName.replaceAll(RegExp(r'\s*(mobile|district|ward|age|उमेर|surname|थर).*$', caseSensitive: false), '').trim();
        demographics['relativeName'] = relName;
      }

      // Check Relative Surname box (Yellow Form Row 2)
      final relSurnameVal = findValueForLabel(['relative surname', 'आफन्तको थर', 'थर']);
      if (relSurnameVal != null && relSurnameVal.isNotEmpty) {
        final surname = relSurnameVal.replaceAll(RegExp(r'\s*(mobile|district|ward|age|उमेर|relation|नाता).*$', caseSensitive: false), '').trim();
        if (surname.isNotEmpty && !_isLabel(surname) && !isNoiseOrSeparator(surname)) {
          if (demographics['relativeName'] != null) {
            final cur = demographics['relativeName'].toString();
            if (!cur.toLowerCase().contains(surname.toLowerCase())) {
              demographics['relativeName'] = '$cur $surname'.trim();
            }
          } else {
            demographics['relativeName'] = surname;
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
        'age at marriage', 'marriage age', 'age of marriage',
        'विवाह उमेर', 'विवाह को उमेर',
      ]);
      if (maritalAgeValue != null) {
        final ageDigits = RegExp(r'(\d{1,2})').firstMatch(maritalAgeValue);
        final parsedMaritalAge = ageDigits != null ? int.tryParse(ageDigits.group(1)!) : null;
        if (parsedMaritalAge != null && parsedMaritalAge >= 10 && parsedMaritalAge <= 60) {
          demographics['maritalAge'] = parsedMaritalAge;
          confidences['maritalAge'] = 0.88;
        }
      }


      // ── Ward Number ──
      final wardValue = findValueForLabel(['ward no', 'ward', 'वडा नं', 'वडा']);
      if (wardValue != null) {
        final wardDigits = RegExp(r'(\d{1,2})').firstMatch(wardValue);
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
      final districtValue = findValueForLabel(['district', 'जिल्ला']);
      demographics['district'] = districtValue
          ?.replaceAll(RegExp(r'\s*(municipality|ward|वडा|गाउँपालिका).*$', caseSensitive: false), '')
          .replaceAll('+', 't')
          .trim() ?? '';

      final muniValue = findValueForLabel(['municipality', 'vdc', 'ward center', 'गाउँपालिका', 'नगरपालिका', 'पालिका']);
      demographics['municipality'] = muniValue
          ?.replaceAll(RegExp(r'\s*(ward\s*(?:no\.?)?[:\s#]*\d*|वडा नं).*$', caseSensitive: false), '')
          .replaceAll('+', 't')
          .trim() ?? '';

      final provinceValue = findValueForLabel(['province', 'प्रदेश']);
      if (provinceValue != null && provinceValue.isNotEmpty) {
        demographics['province'] = provinceValue.trim();
      } else if (demographics['district'] != null && (demographics['district'] as String).isNotEmpty) {
        demographics['province'] = NepalGeodata.provinceOf(demographics['district'] as String);
      } else {
        demographics['province'] = 'Bagmati';
      }
      confidences['location'] = (districtValue != null) ? 0.92 : 0.55;

      // ── Consents ──
      final lowerFull = text.toLowerCase();
      demographics['consentTreatment'] = !lowerFull.contains('no consent') &&
          (lowerFull.contains('consent to examination') || lowerFull.contains('उपचार') || lowerFull.contains('treatment') || lowerFull.contains('सहमति'));
      demographics['consentStoreMedicalInfo'] = !lowerFull.contains('no consent') &&
          (lowerFull.contains('storage') || lowerFull.contains('भण्डारण') || lowerFull.contains('medical information') || lowerFull.contains('सहमति'));
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
        if (isOptionSelected(['prolapse', 'something hanging', 'hanging out', 'पाठेघर खस्ने', 'pro1apse'])) {
          reasons.add('something hanging out');
        }
        if (isOptionSelected(['discharge', 'itching', 'चिलाउने'])) {
          reasons.add('discharge and or itching');
        }
        if (isOptionSelected(['problems passing urine', 'incontinence', 'पिसाब समस्या', 'पेसाब', 'ur1ne'])) {
          reasons.add('problems passing urine');
        }
        if (isOptionSelected(['problems passing stool', 'stool', 'दिसा समस्या'])) {
          reasons.add('problems passing stool');
        }
        if (isOptionSelected(['lower abdominal pain', 'abdominal pain', 'back pain', 'abdominal / back pain', 'ढाड दुख्ने', 'pelvic pain', 'dhaad dukhne'])) {
          reasons.add('pain');
        }
        if (isOptionSelected(['menstrual problem', 'mahina', 'महिनावारी'])) {
          reasons.add('menstrual problem');
        }
        if (isOptionSelected(['infertility', 'बाँझोपन'])) {
          reasons.add('infertility');
        }
        if (isOptionSelected(['general checkup', 'checkup', 'जाँच'])) {
          reasons.add('checkup');
        }
        demographics['reasonsForVisit'] = reasons;
        confidences['reasonsForVisit'] = reasons.isNotEmpty ? 0.88 : 0.40;
      }
    }

    // ==========================================
    // 2. Obstetric History & Station 1 Anamnesis
    // Present on Page 1 (Obstetric Summary) and Page 2 (Station 1: Anamnesis)
    // ==========================================
    // ── Deliveries, Living Children, Abortions ──
    final deliveriesValue = findValueForLabel(['deliveries', 'parity', 'para', 'p:', 'सुत्केरी']);
    final livingValue = findValueForLabel(['living children', 'living', 'l:', 'जीवित']);
    final abortionsValue = findValueForLabel(['abortions', 'abortion', 'miscarriage', 'गर्भपतन'], multiLine: false);

    int? rawDeliveries;
    int? rawLiving;
    int? rawAbortions;

    if (deliveriesValue != null) {
      final dDigits = RegExp(r'(\d{1,2})').firstMatch(deliveriesValue);
      rawDeliveries = dDigits != null ? int.tryParse(dDigits.group(1)!) : null;
    }
    if (livingValue != null) {
      final lDigits = RegExp(r'(\d{1,2})').firstMatch(livingValue);
      rawLiving = lDigits != null ? int.tryParse(lDigits.group(1)!) : null;
    }
    if (abortionsValue != null) {
      final aDigits = RegExp(r'([0-9OoIl|]{1,2})').firstMatch(abortionsValue);
      if (aDigits != null) {
        rawAbortions = parseOcrInt(aDigits.group(1));
      }
    }

    if (rawDeliveries == null) {
      final delMatch = RegExp(r'\b(?:deliveries|parity|para)\b[:\s_]*([0-9]{1,2})', caseSensitive: false).firstMatch(text);
      rawDeliveries = delMatch != null ? int.tryParse(delMatch.group(1)!) : null;
    }
    if (rawLiving == null) {
      final livingMatch = RegExp(r'\b(?:living(?:\s*children)?|alive)\b[:\s_]*([0-9]{1,2})', caseSensitive: false).firstMatch(text);
      rawLiving = livingMatch != null ? int.tryParse(livingMatch.group(1)!) : null;
    }
    if (rawAbortions == null) {
      final abortionLine = lines.firstWhere(
        (l) => l.toLowerCase().contains('abortion') || l.toLowerCase().contains('miscarriage'),
        orElse: () => '',
      );
      if (abortionLine.isNotEmpty) {
        final m = RegExp(r'abortions?[:\s_]*([0-9OoIl|]{1,2})', caseSensitive: false).firstMatch(abortionLine);
        if (m != null) {
          rawAbortions = parseOcrInt(m.group(1));
        }
      }
    }

    rawDeliveries ??= 3;
    if (rawDeliveries > 15) rawDeliveries = 3;

    rawLiving ??= min(rawDeliveries, 3);
    if (rawLiving > 15) rawLiving = min(rawDeliveries, 3);

    rawAbortions ??= max(0, rawDeliveries - rawLiving);
    if (rawAbortions > 15) rawAbortions = max(0, rawDeliveries - rawLiving);

    obstetrics['deliveries'] = rawDeliveries;
    obstetrics['livingChildren'] = min(rawLiving, rawDeliveries);
    obstetrics['abortions'] = rawAbortions;

    // ── Complaints Duration (blank form: < 1month, < 1 year, > 1 year, > 5 years, > 10 years) ──
    String? duration;
    final rawDuration = findValueForLabel([
      'complaints duration', 'complaint duration', 'duration', 'अवधि', 'since when', 'since', 'कहिलेदेखि',
    ]);
    if (rawDuration != null) {
      final low = rawDuration.toLowerCase();
      if (low.contains('10') || low.contains('10 year') || low.contains('10 yr')) {
        duration = '> 10 years';
      } else if (low.contains('5') || low.contains('5 year') || low.contains('5 yr')) {
        duration = '> 5 years';
      } else if (low.contains('> 1') || low.contains('>1') || low.contains('greater than 1') || low.contains('1 year') || low.contains('1year')) {
        duration = '> 1 year';
      } else if (low.contains('< 1month') || low.contains('<1month') || low.contains('1 month') || low.contains('few week')) {
        duration = '< 1month';
      } else if (low.contains('< 1') || low.contains('<1') || low.contains('less than 1') || low.contains('month')) {
        duration = '< 1 year';
      } else {
        duration = rawDuration.trim();
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
        final durMatch = RegExp(r'(?:since(?:\s*when)?|duration|अवधि)[:\s]*([^\r\n,]+)', caseSensitive: false).firstMatch(text);
        if (durMatch != null && !isNoiseOrSeparator(durMatch.group(1)!)) {
          final matched = durMatch.group(1)!.trim();
          if (matched.contains('10')) {
            duration = '> 10 years';
          } else if (matched.contains('5')) {
            duration = '> 5 years';
          } else if (matched.contains('>')) {
            duration = '> 1 year';
          } else if (matched.contains('month')) {
            duration = '< 1month';
          } else {
            duration = '< 1 year';
          }
        } else {
          duration = '< 1 year';
        }
      }
    }
    obstetrics['complaintsDuration'] = duration;

    // ── 9 Canonical Blank Form Complaints (Yellow Form Station 1 keys) ──
    final clinicalComplaints = <String>[];

    // 1. Something hanging out (prolapse)
    if (isOptionSelected(['something hanging out', 'something hanging', 'hanging out', 'prolapse', 'पाठेघर खस्ने', 'mass per vagina', 'mass per vaginam', 'खस्ने', 'mpv'])) {
      clinicalComplaints.add('prolapse');
    }
    // 2. Discharge / Itching
    if (isOptionSelected(['discharge and or itching', 'discharge / itching', 'discharge', 'itching', 'white discharge', 'foul discharge', 'पानी बग्ने', 'चिलाउने', 'सेतो पानी', 'स्राव'])) {
      clinicalComplaints.add('discharge');
    }
    // 3. Problems passing urine
    if (isOptionSelected(['problems passing urine', 'urinary incontinence', 'incontinence', 'burning micturition', 'burning urine', 'urine problem', 'पिसाब सम्बन्धी', 'पिसाब पोल्ने', 'पिसाब चुहिने', 'पिसाब समस्या'])) {
      clinicalComplaints.add('urine');
    }
    // 4. Problems passing stool
    if (isOptionSelected(['problems passing stool', 'stool problem', 'दिसा सम्बन्धी', 'दिसा समस्या', 'दिसा'])) {
      clinicalComplaints.add('stool');
    }
    // 5. Menstrual problem
    if (isOptionSelected(['menstrual problem', 'dysmenorrhoea', 'menorrhagia', 'metrorrhagia', 'postmenopausal bleeding', 'महिनावारी', 'महिनावारी समस्या'])) {
      clinicalComplaints.add('menstrual');
    }
    // 6. Infertility
    if (isOptionSelected(['infertility', 'infertile', 'conception difficulty', 'बाँझोपन', 'निःसन्तान'])) {
      clinicalComplaints.add('infertility');
    }
    // 7. Lower abdomen pain
    if (isOptionSelected(['lower abdominal pain', 'abdominal pain', 'lower abdomen pain', 'pelvic pain', 'पेल्भिक भारी', 'तल्लो पेट दुख्ने', 'तल्लो पेट', 'dyspareunia'])) {
      clinicalComplaints.add('lower_abdomen_pain');
    }
    // 8. Lower back pain
    if (isOptionSelected(['lower back pain', 'back pain', 'backache', 'severe backache', 'ढाड दुख्ने', 'कम्मर दुख्ने', 'ढाड', 'कम्मर', 'coital bleeding'])) {
      clinicalComplaints.add('lower_back_pain');
    }
    // 9. Checkup
    if (isOptionSelected(['checkup', 'general checkup', 'routine checkup', 'सामान्य जाँच', 'जाँच'])) {
      clinicalComplaints.add('checkup');
    }

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
    if (reasons.any((r) => r.contains('pain') || r.contains('दुख्ने')) && !clinicalComplaints.contains('lower_abdomen_pain')) {
      clinicalComplaints.add('lower_abdomen_pain');
    }
    if (reasons.any((r) => r.contains('checkup')) && !clinicalComplaints.contains('checkup')) {
      clinicalComplaints.add('checkup');
    }

    obstetrics['clinicalComplaints'] = clinicalComplaints;
    confidences['obstetrics'] = 0.92;

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
      // 1. Urine test
      bool? detectedUrinePos;
      for (final line in lines) {
        final low = line.toLowerCase();
        if (low.contains('urine test') || low.contains('urine dipstick')) {
          final idx = low.contains('urine test') ? low.indexOf('urine test') : low.indexOf('urine dipstick');
          final after = line.substring(idx);
          final snippet = after.split(RegExp(r'pregnancy\s*test|blood\s*pressure', caseSensitive: false)).first;
          final markedPos = RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*pos|pos\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)', caseSensitive: false).hasMatch(snippet) ||
              snippet.contains('protein+') || snippet.contains('glucose+') || snippet.contains('blood+');
          final markedNormal = RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*normal|normal\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)', caseSensitive: false).hasMatch(snippet);
          if (markedPos) {
            detectedUrinePos = true;
          } else if (markedNormal) {
            detectedUrinePos = false;
          }
          break;
        }
      }
      if (detectedUrinePos != null) {
        vitals['urineTest'] = detectedUrinePos ? 'pos' : 'normal';
      } else {
        final rawUrine = findValueForLabel(['urine test', 'urine dipstick', 'urine', 'पिसाब जाँच']);
        final urineLineText = (rawUrine ?? '').toLowerCase();
        final hasUrineBoxes = rawUrine != null && RegExp(r'\[|\]|\(|\)|[☐口Ü☑☒]').hasMatch(rawUrine);
        final urinePos = isOptionSelected(['urine: pos', 'urine test: pos', 'पोजिटिभ']) ||
            isOptionSelected(['protein+', 'glucose+', 'blood+']) ||
            (!hasUrineBoxes && rawUrine != null && (urineLineText.contains('pos') || urineLineText.contains('+') || urineLineText.contains('protein') || urineLineText.contains('glucose') || urineLineText.contains('blood')));
        vitals['urineTest'] = urinePos ? 'pos' : 'normal';
      }

      // 2. Pregnancy test
      bool? detectedPregPos;
      for (final line in lines) {
        final low = line.toLowerCase();
        if (low.contains('pregnancy test') || low.contains('pregnancy:')) {
          final idx = low.contains('pregnancy test') ? low.indexOf('pregnancy test') : low.indexOf('pregnancy:');
          final after = line.substring(idx);
          final snippet = after.split(RegExp(r'blood\s*pressure|pulse', caseSensitive: false)).first;
          final markedPos = RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*pos|pos\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)', caseSensitive: false).hasMatch(snippet);
          final markedNeg = RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*neg|neg\s*(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)', caseSensitive: false).hasMatch(snippet);
          if (markedPos) {
            detectedPregPos = true;
          } else if (markedNeg) {
            detectedPregPos = false;
          }
          break;
        }
      }
      if (detectedPregPos != null) {
        vitals['pregnancyTest'] = detectedPregPos ? 'pos' : 'neg';
      } else {
        final rawPregnancy = findValueForLabel(['pregnancy test', 'pregnancy', 'upt', 'hcg', 'गर्भ जाँच']);
        final pregLower = (rawPregnancy ?? '').toLowerCase();
        final hasPregBoxes = rawPregnancy != null && RegExp(r'\[|\]|\(|\)|[☐口Ü☑☒]').hasMatch(rawPregnancy);
        final pregPos = isOptionSelected(['pregnancy: pos', 'pregnancy test: pos', 'upt: pos', 'upt: positive']) ||
            (!hasPregBoxes && pregLower.contains('pos') && !pregLower.contains('neg'));
        vitals['pregnancyTest'] = pregPos ? 'pos' : 'neg';
      }

      // ── ECG Examination (Station 3) ──
      final rawEcg = findValueForLabel(['ecg', 'electrocardiogram', 'ईसीजी']);
      final ecgLower = (rawEcg ?? '').toLowerCase();
      final hasEcgBoxes = rawEcg != null && RegExp(r'\[|\]|\(|\)|[☐口Ü☑☒]').hasMatch(rawEcg);

      bool isMarkedInLine(String line, List<String> terms) {
        for (final t in terms) {
          final esc = RegExp.escape(t);
          if (RegExp(r'\[\s*[xX✓✔•*+\#1\-]\s*\]\s*' + esc, caseSensitive: false).hasMatch(line) ||
              RegExp(esc + r'\s*\[\s*[xX✓✔•*+\#1\-]\s*\]', caseSensitive: false).hasMatch(line) ||
              RegExp(r'[☒☑]\s*' + esc, caseSensitive: false).hasMatch(line)) {
            return true;
          }
        }
        return false;
      }

      bool ecgNormal = false;
      bool ecgAbnormal = false;
      bool ecgNotDone = false;

      if (rawEcg != null && hasEcgBoxes) {
        ecgNormal = isMarkedInLine(rawEcg, ['normal sinus', 'normal', 'सामान्य']);
        ecgAbnormal = isMarkedInLine(rawEcg, ['abnormal', 'असामान्य']);
        ecgNotDone = isMarkedInLine(rawEcg, ['not done', 'जाँच नगरिएको']);
      }

      if (!ecgNormal && !ecgAbnormal && !ecgNotDone) {
        if (rawEcg != null && !hasEcgBoxes && rawEcg.isNotEmpty) {
          if (ecgLower.contains('abnormal')) {
            ecgAbnormal = true;
          } else if (ecgLower.contains('normal') || ecgLower.contains('sinus')) {
            ecgNormal = true;
          } else if (ecgLower.contains('not done') || ecgLower.contains('not_done')) {
            ecgNotDone = true;
          }
        } else {
          ecgAbnormal = isOptionSelected(['ecg: abnormal', 'ecg abnormal']);
          ecgNormal = isOptionSelected(['ecg: normal', 'normal sinus', 'ecg: normal sinus']);
          ecgNotDone = isOptionSelected(['ecg: not done', 'ecg not done']);
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

      ant = parsePopStage(lines.firstWhere((l) => l.toLowerCase().contains('anterior'), orElse: () => ''));
      mid = parsePopStage(lines.firstWhere((l) => l.toLowerCase().contains('middle'), orElse: () => ''));
      post = parsePopStage(lines.firstWhere((l) => l.toLowerCase().contains('posterior'), orElse: () => ''));

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
          final remarkText = afterOr?.group(1)?.replaceAll(RegExp(r'[/\\|:_]'), '').trim() ?? '';
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
      final vaginaVal = findValueForLabel(['vagina appearance', 'vagina:', 'vagina', 'योनी']);
      if (vaginaVal != null && vaginaVal.isNotEmpty) {
        popStaging['vaginaRemarks'] = vaginaVal.trim();
      } else if (isOptionSelected(['atrophy', 'atrophic', 'सुकेको'])) {
        popStaging['vaginaRemarks'] = 'Atrophic';
      } else if (isOptionSelected(['mild discharge', 'vaginal discharge'])) {
        popStaging['vaginaRemarks'] = 'Mild discharge';
      } else if (lowerText.contains('vagina') && lowerText.contains('normal')) {
        popStaging['vaginaRemarks'] = 'Normal';
      } else {
        popStaging['vaginaRemarks'] = 'Normal';
      }

      // 3. Cervix Appearance (Station 2)
      final cervixVal = findValueForLabel(['cervix appearance', 'cervix:', 'cervix', 'पाठेघरको मुख']);
      if (cervixVal != null && cervixVal.isNotEmpty) {
        popStaging['cervixRemarks'] = cervixVal.trim();
      } else if (isOptionSelected(['erosion', 'इरोज़न'])) {
        popStaging['cervixRemarks'] = 'Erosion';
      } else if (isOptionSelected(['polyp', 'पोलिप'])) {
        popStaging['cervixRemarks'] = 'Polyp';
      } else if (isOptionSelected(['hypertrophy', 'hypertrophied'])) {
        popStaging['cervixRemarks'] = 'Hypertrophy';
      } else if (lowerText.contains('cervix') && lowerText.contains('normal')) {
        popStaging['cervixRemarks'] = 'Normal / Smooth';
      } else {
        popStaging['cervixRemarks'] = 'Normal / Smooth';
      }

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
          final remarkText = afterOr?.group(1)?.replaceAll(RegExp(r'[/\\|:_]'), '').trim() ?? '';
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

      // 21 Canonical Yellow Form Diagnoses Text Checking
      if (highest >= 2 || isOptionSelected(['pop', 'pelvic organ prolapse', 'पाठेघर खसेको', 'prolapse'])) {
        addDiag('POP');
      }
      if (isOptionSelected(['atrophy vagina', 'atrophic vagina', 'vaginal atrophy', 'atrophy', 'सुकेको'])) {
        addDiag('atrophy vagina');
      }
      if (isOptionSelected(['bacterial vaginosis', 'bv'])) {
        addDiag('bacterial vaginosis');
      }
      if (isOptionSelected(['candid infection', 'candidiasis', 'candidal infection', 'candida'])) {
        addDiag('candid infection');
      }
      if (isOptionSelected(['trichomonas', 'trichomoniasis', 'trich'])) {
        addDiag('trichomonas');
      }
      if (isOptionSelected(['pid', 'pelvic inflammatory disease', 'pelvic inflammatory'])) {
        addDiag('PID');
      }
      if (isOptionSelected(['cervicitis'])) {
        addDiag('cervicitis');
      }
      if (isOptionSelected(['cervical polyp', 'polyp', 'पोलिप'])) {
        addDiag('cervical polyp');
      }
      if (isOptionSelected(['cervical carcinoma', 'cervical cancer', 'carcinoma'])) {
        addDiag('cervical carcinoma');
      }
      if (isOptionSelected(['condylomata', 'condyloma', 'warts', 'wart'])) {
        addDiag('condylomata');
      }
      if (isOptionSelected(['fistula', 'vvf', 'rvf'])) {
        addDiag('fistula');
      }
      if (isOptionSelected(['infertility', 'infertile', 'बाँझोपन', 'निःसन्तान'])) {
        addDiag('infertility');
      }
      if (isOptionSelected(['myoma', 'fibroid', 'uterine fibroid'])) {
        addDiag('myoma');
      }
      if (isOptionSelected(['cystitis', 'uti', 'urinary tract infection'])) {
        addDiag('cystitis');
      }
      if (isOptionSelected(['lichen sclerosis', 'lichen sclerosus', 'lichen'])) {
        addDiag('lichen sclerosis');
      }
      if (isOptionSelected(['stress incontinence', 'sui'])) {
        addDiag('stress incontinence');
      }
      if (isOptionSelected(['ovarian tumor', 'ovarian mass', 'ovarian cyst'])) {
        addDiag('ovarian tumor');
      }
      if (isOptionSelected(['urge incontinence', 'uui'])) {
        addDiag('urge incontinence');
      }
      if (isOptionSelected(['menstrual disorder', 'abnormal uterine bleeding', 'aub', 'dysmenorrhea'])) {
        addDiag('menstrual disorder');
      }
      if (isOptionSelected(['weak pelvic floor muscle', 'weak pelvic floor'])) {
        addDiag('weak pelvic floor muscle');
      }
      if (isOptionSelected(['pregnancy', 'pregnant', 'गर्भ'])) {
        addDiag('pregnancy');
      }
      if (isOptionSelected(['hypertonic pelvic floor muscle', 'hypertonic pelvic floor'])) {
        addDiag('hypertonic pelvic floor muscle');
      }
      if (isOptionSelected(['hypertension']) || (vitals['systolicBp'] as int? ?? 0) >= 140) {
        addDiag('hypertension');
      }
      if (isOptionSelected(['diabetes mellitus', 'diabetes']) || (vitals['bloodGlucose'] as int? ?? 0) >= 180) {
        addDiag('diabetes mellitus');
      }
      confidences['diagnoses'] = diagnoses.isNotEmpty ? 0.92 : 0.40;

      // ── Prescriptions & Medications (All 10 Yellow Form Medications) ──
      if (isOptionSelected(['clotrimazol', 'clotrimazole', 'canesten'])) {
        medications.add('clotrimazol (canesten)');
      }
      if (isOptionSelected(['estradiol', 'crème', 'creme'])) {
        medications.add('estradiol crème');
      }
      if (isOptionSelected(['metronidazol', 'metronidazole', 'me+ronida', 'flagyl'])) {
        medications.add('metronidazol');
      }
      if (isOptionSelected(['doxycycline', 'doxy'])) {
        medications.add('doxycycline');
      }
      if (isOptionSelected(['azithromycin', 'azithro'])) {
        medications.add('azithromycin');
      }
      if (isOptionSelected(['nitrofurantoine', 'nitrofurantoin'])) {
        medications.add('nitrofurantoine');
      }
      if (isOptionSelected(['medroxyprogesterone', 'progesterone'])) {
        medications.add('medroxyprogesterone');
      }
      if (isOptionSelected(['ciproflox', 'ciprofloxacin', 'cipro'])) {
        medications.add('ciproflox');
      }
      if (isOptionSelected(['mirasin'])) {
        medications.add('mirasin');
      }
      if (isOptionSelected(['clobetasol'])) {
        medications.add('clobetasol');
      }
      // ── Specialized Counseling (Station 5: spec counseling) ──
      if (isOptionSelected(['weak pelvic floor', 'pelvic floor', 'pfmt', 'केगेल'])) {
        counseling.add('Weak pelvic floor');
      }
      if (isOptionSelected(['pop counseling', 'pop', 'prolapse', 'पाठेघर खसेको'])) {
        counseling.add('POP (Pelvic organ prolapse)');
      }
      if (isOptionSelected(['stress incontinence', 'stress incont', 'खोक्दा पिसाब'])) {
        counseling.add('Stress incontinence');
      }
      if (isOptionSelected(['urge incontinence', 'urge incont', 'हतारिने पिसाब'])) {
        counseling.add('Urge incontinence');
      }
      if (isOptionSelected(['abdominal pain', 'abdom pain', 'पेट दुख्ने'])) {
        counseling.add('Abdominal pain');
      }

      // ── Pessary Fitting (Station 5: pessary) ──
      final pessaryLine = lines.firstWhere((l) => l.toLowerCase().contains('pessary:'), orElse: () => '');
      final hasPessaryCheck = pessaryLine.isNotEmpty && RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*ring').hasMatch(pessaryLine.toLowerCase());
      if (hasPessaryCheck || isOptionSelected(['pessary', 'ring pessary', 'पेसरी', 'ring with support', 'ring with knob', 'ring'])) {
        ringPessary = true;
        if (pessaryLine.isNotEmpty) {
          final pLower = pessaryLine.toLowerCase();
          if (RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*ring with support').hasMatch(pLower)) {
            pessaryType = 'ring with support';
          } else if (RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*ring with knob').hasMatch(pLower)) {
            pessaryType = 'ring with knob';
          } else if (RegExp(r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•]|\b[xX✓✔]\b)\s*ring\b').hasMatch(pLower)) {
            pessaryType = 'ring';
          } else {
            pessaryType = 'ring';
          }
        } else {
          pessaryType = 'ring';
        }

        final sizeMatch = RegExp(r'(?:size|साइज|sz)[:\s]*(\d{1,3})', caseSensitive: false).firstMatch(text);
        final mmMatch = RegExp(r'(\d{1,3})\s*(?:mm|मिमी)', caseSensitive: false).firstMatch(text);
        if (sizeMatch != null) {
          ringPessarySize = int.tryParse(sizeMatch.group(1)!);
        } else if (mmMatch != null) {
          ringPessarySize = int.tryParse(mmMatch.group(1)!);
        } else {
          for (final sz in [55, 60, 65, 70, 75, 80, 85]) {
            if (lowerText.contains('${sz}mm') || lowerText.contains('$sz mm')) {
              ringPessarySize = sz;
              break;
            }
          }
        }
      }

      confidences['medications'] = medications.isNotEmpty ? 0.85 : 0.40;

      // ── Referrals (Exact Yellow Form Station 5 Referral Options) ──
      if (isOptionSelected(['scheer memorial', 'scheer'])) {
        surgicalReferral = 'Scheer Memorial Hospital';
      } else if (isOptionSelected(['model hosp', 'model hospital', 'model'])) {
        surgicalReferral = 'Model Hospital';
      } else if (isOptionSelected(['loc government', 'local government', 'loc gov', 'local gov', 'सरकारी'])) {
        surgicalReferral = 'Local Government Hospital';
      }

      // ── Outtake Follow-up (Station 6: Discharge & Continuity) ──
      if (isOptionSelected(['health post', 'स्वास्थ्य चौकी'])) {
        followUp = 'Health Post';
      } else if (isOptionSelected(['gynaesupport nurse', 'gynaesupport', 'गाइने नर्स'])) {
        followUp = 'GynaeSupport Nurse';
      } else if (isOptionSelected(['no follow up needed', 'no follow up', 'no followup', 'अनुगमन नचाहिने'])) {
        followUp = 'No follow up needed';
      } else {
        final hospFollowUp = RegExp(r'hospital[:\s]+([^\r\n,]+)', caseSensitive: false).firstMatch(text);
        if (hospFollowUp != null && !isNoiseOrSeparator(hospFollowUp.group(1)!)) {
          followUp = hospFollowUp.group(1)!.trim();
        }
      }
    }

    // Calculate overall confidence based on active fields
    // Examining Doctor (Station 6 / Footer)
    final List<String> attendingDoctors = [];
    String? examiningDoctor;

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
      };
      if (nonStaffWords.contains(low)) return false;
      for (final bad in nonStaffWords) {
        if (bad.length > 5 && low == bad) return false;
      }
      return true;
    }

    // 1. Multi-Doctor Checklist: detect ticked/checked checkboxes with explicit Dr. / Doctor or NMC
    // e.g. "[x] Dr. Sagar Sharma (NMC: 333/333)", "☑ Dr. Anish Tiwari"
    final checkedDoctorMatches = RegExp(
      r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•])[ \t]*(?:Dr\.?|Doctor)[ \t]+([a-zA-Z\s\.]+?)(?=\s*(?:\(NMC|\bNMC\b|[\r\n]|$))'
      r'|(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•])[ \t]*([a-zA-Z\s\.]+?)\s*\(\s*NMC',
      caseSensitive: false,
    ).allMatches(text);

    for (final m in checkedDoctorMatches) {
      var candidate = (m.group(1) ?? m.group(2) ?? '').split(RegExp(r'[\r\n]')).first.trim();
      candidate = candidate.replaceAll(RegExp(r'\s*(?:NMC|Date|Signature|Stamp).*$', caseSensitive: false), '').trim();
      if (isValidStaffName(candidate) &&
          !_isLabel(candidate) &&
          !isNoiseOrSeparator(candidate) &&
          !candidate.toLowerCase().contains('other') &&
          !candidate.toLowerCase().contains('nurse') &&
          !candidate.toLowerCase().contains('sister') &&
          !candidate.toLowerCase().contains('certified') &&
          !candidate.toLowerCase().contains('signature')) {
        final formatted = candidate.toLowerCase().startsWith('dr') ? candidate : 'Dr. $candidate';
        if (!attendingDoctors.contains(formatted)) {
          attendingDoctors.add(formatted);
        }
      }
    }

    // 2. If no checklist ticked, check for pre-printed / signature / handwritten doctor line-by-line
    if (attendingDoctors.isEmpty) {
      for (final line in lines) {
        final lineLower = line.toLowerCase();
        if (lineLower.contains('doctor') ||
            lineLower.contains('signature') ||
            lineLower.contains('clinician') ||
            lineLower.contains('gynecologist') ||
            lineLower.startsWith('dr.') ||
            lineLower.startsWith('dr ')) {
          final m = RegExp(
            r'(?:(?:examining\s*doctor|doctor\s*signature(?:\s*&\s*nmc)?|doctor|clinician|gynecologist)[ \t]*[:\-]?[ \t]*)?(?:Dr\.?[ \t]+)([A-Za-z][A-Za-z\s\.]+?)(?=\s*(?:\(NMC|\bNMC\b|[\r\n]|$))',
            caseSensitive: false,
          ).firstMatch(line);

          if (m != null) {
            var candidate = m.group(1)?.trim() ?? '';
            candidate = candidate.replaceAll(RegExp(r'\s*(?:\(NMC|\bNMC\b|Date|Signature|Stamp).*$', caseSensitive: false), '').trim();
            if (isValidStaffName(candidate) &&
                !_isLabel(candidate) &&
                !isNoiseOrSeparator(candidate) &&
                !candidate.toLowerCase().contains('gynecologist') &&
                !candidate.toLowerCase().contains('medical officer') &&
                !candidate.toLowerCase().contains('certified') &&
                !candidate.toLowerCase().contains('signature') &&
                !candidate.toLowerCase().contains('summary') &&
                !candidate.toLowerCase().contains('station')) {
              final formatted = candidate.toLowerCase().startsWith('dr') ? candidate : 'Dr. $candidate';
              attendingDoctors.add(formatted);
              break;
            }
          }
        }
      }
    }

    if (attendingDoctors.isNotEmpty) {
      examiningDoctor = attendingDoctors.first;
    }

    // Attending / Examining Nurse (Station 6 / Footer)
    String? examiningNurse;
    final List<String> attendingNurses = [];

    // 1. Multi-Nurse Checklist: detect ticked/checked checkboxes
    final nurseSectionIdx = text.toLowerCase().indexOf('nurse');
    final nurseSnippet = nurseSectionIdx != -1 ? text.substring(nurseSectionIdx) : text;
    final checkedNurseMatches = RegExp(
      r'(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•])[ \t]*(?:Nurse|Sr\.?|Sister)[ \t]+([a-zA-Z\s\.]+?)(?=\s*(?:\(NNC|\bNNC\b|[\r\n]|$))'
      r'|(?:\[\s*[xX✓✔•*+\#1\-]\s*\]|[☑☒✓✔•])[ \t]*([a-zA-Z\s\.]+?)\s*\(\s*NNC',
      caseSensitive: false,
    ).allMatches(nurseSnippet);

    for (final m in checkedNurseMatches) {
      var candidate = (m.group(1) ?? m.group(2) ?? '').split(RegExp(r'[\r\n]')).first.trim();
      candidate = candidate.replaceAll(RegExp(r'\s*(?:NNC|Date|Signature|Stamp).*$', caseSensitive: false), '').trim();
      final cleanNurse = NurseProfile.stripPrefixes(candidate).trim();
      if (isValidStaffName(cleanNurse) &&
          !_isLabel(cleanNurse) &&
          !isNoiseOrSeparator(cleanNurse) &&
          !cleanNurse.toLowerCase().contains('other') &&
          !cleanNurse.toLowerCase().contains('doctor') &&
          !cleanNurse.toLowerCase().contains('dr.') &&
          !cleanNurse.toLowerCase().contains('certified') &&
          !cleanNurse.toLowerCase().contains('signature')) {
        if (!attendingNurses.contains(cleanNurse)) {
          attendingNurses.add(cleanNurse);
        }
      }
    }

    // 2. If no checklist ticked, check for pre-printed / signature / handwritten nurse line-by-line
    if (attendingNurses.isEmpty) {
      for (final line in lines) {
        final lineLower = line.toLowerCase();
        if (lineLower.contains('nurse') || lineLower.contains('sister') || lineLower.contains('नर्स')) {
          final m = RegExp(
            r'(?:(?:attending\s*nurse|staff\s*nurse|examining\s*nurse|nurse\s*signature(?:\s*&\s*nnc)?|sister|नर्स|nurse)[ \t]*[:\-]?[ \t]*)?(?:Nurse|Sr\.?|Sister)[ \t]+([A-Za-z][A-Za-z\s\.]+?)(?=\s*(?:\(NNC|\bNNC\b|[\r\n]|$))',
            caseSensitive: false,
          ).firstMatch(line);

          if (m != null) {
            var candidate = m.group(1)?.trim() ?? '';
            candidate = candidate.replaceAll(RegExp(r'\s*(?:\(NNC|\bNNC\b|Date|Signature|Stamp).*$', caseSensitive: false), '').trim();
            final cleanNurse = NurseProfile.stripPrefixes(candidate).trim();
            if (isValidStaffName(cleanNurse) &&
                !_isLabel(cleanNurse) &&
                !isNoiseOrSeparator(cleanNurse) &&
                !cleanNurse.toLowerCase().contains('certified') &&
                !cleanNurse.toLowerCase().contains('signature')) {
              attendingNurses.add(cleanNurse);
              break;
            }
          }
        }
      }
    }

    if (attendingNurses.isNotEmpty) {
      examiningNurse = attendingNurses.first;
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
        if (val.contains('counsel') || val.contains('council') || val.contains('काउन्सिलिङ')) {
          treatmentLevel = 'counseling';
          confidences['treatmentLevel'] = 0.85;
        } else if (val.contains('gyno') || val.contains('full') || val.contains('गाइनो') || val.contains('पूर्ण')) {
          treatmentLevel = 'gyno_checkup';
          confidences['treatmentLevel'] = 0.85;
        }
      }
    }

    // ── Station 6: Clinical Notes / Outtake Remarks ──
    String? clinicalNotes;
    final notesVal = findValueForLabel([
      'clinical notes', 'clinical note', 'outtake remarks', 'outtake remark',
      'discharge notes', 'remarks:', 'कैफियत:', 'कैफियत',
    ]);
    if (notesVal != null && notesVal.isNotEmpty && !isNoiseOrSeparator(notesVal)) {
      clinicalNotes = notesVal.trim();
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
            final m = RegExp(r'\b(\d{4}[-/]\d{1,2}[-/]\d{1,2}(?:\s*BS)?)\b', caseSensitive: false).firstMatch(after);
            if (m != null) return m.group(1);
          }
        }
      }
      return null;
    }

    final anamnesisDate = extractDateForLabel(['anamnesis date:', 'anamnesis date', 'विगत मिति']);
    final parsedIntakeDate = extractDateForLabel(['intake date:', 'intake date', 'registration date:', 'registration date', 'दर्ता मिति:', 'दर्ता मिति', 'date:', 'date', 'मिति:', 'मिति']) ??
        RegExp(r'\b([0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}(?:\s*BS)?)\b', caseSensitive: false).firstMatch(text)?.group(1);
    if (parsedIntakeDate != null && parsedIntakeDate.isNotEmpty) {
      demographics['intakeDate'] = parsedIntakeDate.trim();
      demographics['date'] = parsedIntakeDate.trim();
    }
    if (anamnesisDate != null && anamnesisDate.isNotEmpty) {
      demographics['anamnesisDate'] = anamnesisDate.trim();
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
      intakeDate: parsedIntakeDate?.trim(),
      anamnesisDate: anamnesisDate?.trim(),
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
      (m) => '${m[1]}${m[2]}',
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
