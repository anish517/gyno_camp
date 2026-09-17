import 'dart:io';
import 'dart:math';
import '../constants/nepal_geodata.dart';
import '../../models/ocr_scan_result_model.dart';
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
  OcrScanResultModel parseFormText(String text, {int pageNumber = 0, String? imagePath}) {
    final confidences = <String, double>{};

    final lines = text.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final lowerText = text.toLowerCase();

    final bool isPage1Only = pageNumber == 1;
    final bool isPage2Only = pageNumber == 2;

    // Optical Mark Recognition (OMR) on image file if available
    Map<String, OmrResult>? page1OmrReasons;
    Map<String, OmrResult>? page1OmrMarital;
    Map<String, OmrResult>? page2OmrPop;
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
          }
          if (!isPage1Only) {
            page2OmrPop = omr.evaluateImageBytes(bytes, OmrService.page2PopStagingBoxes);
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

    int? parseStageInt(String? raw) {
      if (raw == null) return null;
      final clean = raw.replaceAll('_', '').trim();
      if (clean.toLowerCase() == 'l' || clean == 'I' || clean == '|') return 1;
      return int.tryParse(clean);
    }

    /// Searches for a value associated with a label across lines.
    String? findValueForLabel(List<String> labels, {bool multiLine = true}) {
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final lowerLine = line.toLowerCase();
        for (final label in labels) {
          final labelLower = label.toLowerCase();
          if (lowerLine.contains(labelLower)) {
            final labelIdx = lowerLine.indexOf(labelLower);
            final afterLabel = line.substring(labelIdx + label.length).trim();
            final value = afterLabel.replaceFirst(RegExp(r'^[:\-=\s]+'), '').trim();
            if (value.isNotEmpty) return value;

            if (multiLine && i + 1 < lines.length) {
              final nextLine = lines[i + 1].trim();
              if (nextLine.isNotEmpty && !_isLabel(nextLine)) {
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
      for (final line in lines) {
        final lower = line.toLowerCase();
        for (final k in keywords) {
          final kw = k.toLowerCase();
          final idx = lower.indexOf(kw);
          if (idx == -1) continue;

          // Check if there are multiple checkboxes on this line (e.g. "[ ] A  [x] B")
          final checkCount = RegExp(r'\[\s*[xX✓✔•*+\#1\-]?\s*\]|\(\s*[xX✓✔]?\s*\)|[☐口Ü☑☒]').allMatches(line).length;
          if (checkCount > 1) {
            final start = max(0, idx - 25);
            final end = min(line.length, idx + kw.length + 25);
            final snippet = line.substring(start, end);

            final checkedNear = RegExp(
              r'\[\s*[xX✓✔•*+\#1\-]\s*\]\s*' + RegExp.escape(kw) +
              r'|\(\s*[xX✓✔•*+\#1\-]\s*\)\s*' + RegExp.escape(kw) +
              r'|[☑☒✓✔•]\s*' + RegExp.escape(kw) +
              r'|' + RegExp.escape(kw) + r'\s*\[\s*[xX✓✔•*+\#1\-]\s*\]' +
              r'|' + RegExp.escape(kw) + r'\s*\(\s*[xX✓✔•*+\#1\-]\s*\)' +
              r'|' + RegExp.escape(kw) + r'\s*[☑☒✓✔•]',
              caseSensitive: false,
            ).hasMatch(snippet);

            final uncheckedNear = RegExp(
              r'\[\s*\]\s*' + RegExp.escape(kw) +
              r'|\(\s*\)\s*' + RegExp.escape(kw) +
              r'|[☐口Ü]\s*' + RegExp.escape(kw) +
              r'|' + RegExp.escape(kw) + r'\s*\[\s*\]' +
              r'|' + RegExp.escape(kw) + r'\s*\(\s*\)' +
              r'|' + RegExp.escape(kw) + r'\s*[☐口Ü]',
              caseSensitive: false,
            ).hasMatch(snippet);

            if (checkedNear) return true;
            if (uncheckedNear) return false;
          } else {
            final hasPositive = RegExp(
              r'\[\s*[xX✓✔•*+\#1\-]\s*\]|☒|☑|[✓✔√]|(?:\b|[^\w])[xX](?:\b|[^\w])|•',
            ).hasMatch(line);

            final hasUnchecked = RegExp(r'\[\s*\]|\(\s*\)|[☐口Ü]').hasMatch(line);

            if (hasPositive) return true;
            if (hasUnchecked) return false;

            if (line.trim().endsWith('(x)') || line.trim().endsWith('[x]') || line.trim().endsWith('✓')) {
              return true;
            }
          }
        }
      }

      // If document has checkmarks/checkboxes elsewhere in the document, any option without one is unchecked
      final allText = lines.join('\n');
      final hasAnyCheckmarks = RegExp(r'\[\s*[xX✓✔•*+\#1\-]?\s*\]|\(\s*[xX✓✔]?\s*\)|☒|☑|[✓✔√]|•|[☐口Ü]').hasMatch(allText);
      if (hasAnyCheckmarks) {
        return false;
      }

      // If document has NO checkbox characters at all, check if keyword is in text (plain-text notes)
      return keywords.any((k) => allText.toLowerCase().contains(k.toLowerCase()));
    }

    // ==========================================
    // 1. Demographics Extraction (Page 1 / Front)
    // ==========================================
    final demographics = <String, dynamic>{};
    final obstetrics = <String, dynamic>{};

    if (!isPage2Only) {
      // ── First & Last Name ──
      // Check for distinct First Name / Surname fields first (from block-letter forms)
      final extractedFirstName = findValueForLabel(['first name', 'पहिलो नाम', 'given name']);
      final extractedSurname = findValueForLabel(['surname', 'last name', 'थर', 'family name']);

      if ((extractedFirstName != null && extractedFirstName.isNotEmpty) ||
          (extractedSurname != null && extractedSurname.isNotEmpty)) {
        if (extractedFirstName != null && extractedFirstName.isNotEmpty) {
          final cleanFirst = extractedFirstName.replaceAll(RegExp(r'\s*(surname|last name|थर|age|mobile).*$', caseSensitive: false), '').trim();
          demographics['firstName'] = _capitalizeFirst(cleanFirst.split(RegExp(r'\s+')).first);
        }
        if (extractedSurname != null && extractedSurname.isNotEmpty) {
          final cleanSurname = extractedSurname.replaceAll(RegExp(r'\s*(age|mobile|district|ward|उमेर).*$', caseSensitive: false), '').trim();
          demographics['surname'] = _capitalizeFirst(cleanSurname.split(RegExp(r'\s+')).first);
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
            r'(?:patient\s*name|patient|नाम)[:\s]+([A-Za-z\u0900-\u097F][A-Za-z\u0900-\u097F\s]{1,35})',
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
      // Priority 2: 'Age:' label, but NOT if line contains 'marriage' or 'marital'
      if (parsedAge == null) {
        for (final line in lines) {
          final lowerLine = line.toLowerCase();
          if (lowerLine.contains('age') &&
              !lowerLine.contains('marriage') &&
              !lowerLine.contains('marital') &&
              !lowerLine.contains('at marriage') &&
              !lowerLine.contains('patient age')) {
            final m = RegExp(r'(?:^|\s)age[:\s]+(\d{1,3})', caseSensitive: false)
                .firstMatch(line);
            if (m != null) {
              parsedAge = int.tryParse(m.group(1)!);
              break;
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
        demographics['age'] = 35;
        confidences['age'] = 0.50;
      }


      // ── Relative / Spouse / Father Name ──
      final relLabels = [
        "husband/spouse", "husband / spouse", "husband's name", "husband name", "husband:", "husbancl",
        "spouse name", "spouse:",
        "father's name", "father name", "father:",
        "relative name", "relative:", "guardian name", "guardian:",
        "श्रीमानको नाम", "श्रीमान", "बुबाको नाम", "बुबा", "पति",
      ];
      final relValue = findValueForLabel(relLabels);
      if (relValue != null && relValue.isNotEmpty) {
        var relName = relValue.replaceAll(RegExp(r'\s*\(.*?\)\s*$'), '').trim();
        relName = relName.replaceAll(RegExp(r'\s*(mobile|district|ward|age|उमेर).*$', caseSensitive: false), '').trim();
        demographics['relativeName'] = relName;

        final matchedLabel = relLabels.firstWhere(
          (l) => text.toLowerCase().contains(l.toLowerCase()),
          orElse: () => '',
        ).toLowerCase();
        if (relValue.toLowerCase().contains('husband') || matchedLabel.contains('husband') || matchedLabel.contains('श्रीमान') || matchedLabel.contains('पति')) {
          demographics['relativeType'] = 'Husband';
        } else if (relValue.toLowerCase().contains('father') || matchedLabel.contains('father') || matchedLabel.contains('बुबा')) {
          demographics['relativeType'] = 'Father';
        } else if (matchedLabel.contains('guardian')) {
          demographics['relativeType'] = 'Guardian';
        } else {
          demographics['relativeType'] = (demographics['age'] as int? ?? 30) < 20 ? 'Father' : 'Husband';
        }
        confidences['relative'] = 0.90;
      } else {
        demographics['relativeName'] = null;
        demographics['relativeType'] = 'Husband';
        confidences['relative'] = 0.50;
      }

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
        'contact person', 'secondary contact', 'emergency contact',
        'सम्पर्क व्यक्ति', 'सम्पर्क',
      ]);
      if (contactPersonValue != null && contactPersonValue.isNotEmpty) {
        var cleanContact = contactPersonValue
            .replaceAll(RegExp(r'\s*(mobile|phone|नम्बर|contact mobile).*$', caseSensitive: false), '')
            .trim();
        if (cleanContact.isNotEmpty) {
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
        final maritalLine = lines.firstWhere(
          (l) => l.toLowerCase().contains('marital') || l.toLowerCase().contains('वैवाहिक'),
          orElse: () => '',
        );

        if (maritalLine.isNotEmpty) {
          final lowerM = maritalLine.toLowerCase();
          if (RegExp(r'\[\s*[xX✓✔•*+\#1]\s*\]\s*unmarried|unmarried\s*\[\s*[xX✓✔•*+\#1]\s*\]|☒\s*unmarried').hasMatch(lowerM)) {
            demographics['maritalStatus'] = 'unmarried';
          } else if (RegExp(r'\[\s*[xX✓✔•*+\#1]\s*\]\s*widow|widow\s*\[\s*[xX✓✔•*+\#1]\s*\]|☒\s*widow').hasMatch(lowerM)) {
            demographics['maritalStatus'] = 'widow';
          } else if (RegExp(r'\[\s*[xX✓✔•*+\#1]\s*\]\s*married|married\s*\[\s*[xX✓✔•*+\#1]\s*\]|☒\s*married').hasMatch(lowerM)) {
            demographics['maritalStatus'] = 'married';
          } else if (demographics['relativeType'] == 'Husband') {
            demographics['maritalStatus'] = 'married';
          } else {
            demographics['maritalStatus'] = 'married';
          }
          confidences['maritalStatus'] = 0.92;
        } else {
          demographics['maritalStatus'] = 'married';
          confidences['maritalStatus'] = 0.85;
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
        if (isOptionSelected(['back pain', 'abdominal / back pain', 'ढाड दुख्ने', 'pelvic pain', 'dhaad dukhne'])) {
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

    // ── Complaints Duration ──
    String? duration;
    final rawDuration = findValueForLabel(['complaints duration', 'complaint duration', 'duration', 'अवधि']);
    if (rawDuration != null) {
      final low = rawDuration.toLowerCase();
      if (low.contains('< 3') || low.contains('<3') || low.contains('less than 3')) {
        duration = '< 3 months';
      } else if (low.contains('3-12') || low.contains('3 to 12') || low.contains('3 - 12') || low.contains('3–12')) {
        duration = '3-12 months';
      } else if (low.contains('> 1') || low.contains('>1') || low.contains('greater than 1') || low.contains('1 year') || low.contains('1year')) {
        duration = '> 1 year';
      } else {
        duration = rawDuration.trim();
      }
    }
    if (duration == null) {
      if (isOptionSelected(['< 3 months', '<3 months', '< 3m'])) {
        duration = '< 3 months';
      } else if (isOptionSelected(['3-12 months', '3 - 12 months', '3 to 12 months'])) {
        duration = '3-12 months';
      } else if (isOptionSelected(['> 1 year', '>1 year', '> 1 yr', '>1 yr', '>1 Year'])) {
        duration = '> 1 year';
      } else {
        duration = '3-12 months';
      }
    }
    obstetrics['complaintsDuration'] = duration;

    // ── 9 Chief Clinical Complaints (Page 2 Station 1 Checkboxes) ──
    final clinicalComplaints = <String>[];
    if (isOptionSelected(['lower abdominal pain', 'abdominal pain', 'तल्लो पेट दुख्ने'])) {
      clinicalComplaints.add('Lower Abdominal Pain');
    }
    if (isOptionSelected(['white / foul discharge', 'white discharge', 'foul discharge', 'discharge and or itching', 'सेतो पानी', 'चिलाउने'])) {
      clinicalComplaints.add('White / Foul Discharge');
    }
    if (isOptionSelected(['pelvic heaviness', 'heaviness', 'पेल्भिक भारी'])) {
      clinicalComplaints.add('Pelvic Heaviness');
    }
    if (isOptionSelected(['burning micturition', 'burning urine', 'पिसाब पोल्ने'])) {
      clinicalComplaints.add('Burning Micturition');
    }
    if (isOptionSelected(['urinary incontinence', 'incontinence', 'problems passing urine', 'पिसाब चुहिने'])) {
      clinicalComplaints.add('Urinary Incontinence');
    }
    if (isOptionSelected(['dyspareunia', 'pain during intercourse', 'सम्पर्कमा दुखाई'])) {
      clinicalComplaints.add('Dyspareunia');
    }
    if (isOptionSelected(['coital bleeding', 'bleeding after intercourse', 'सम्पर्कपछि रक्तस्राव'])) {
      clinicalComplaints.add('Coital Bleeding');
    }
    if (isOptionSelected(['mass per vagina', 'mass per vaginam', 'something hanging out', 'something hanging', 'योनीबाट केही बाहिर'])) {
      clinicalComplaints.add('Mass Per Vagina');
    }
    if (isOptionSelected(['severe backache', 'backache', 'ढाड दुख्ने', 'back pain'])) {
      clinicalComplaints.add('Severe Backache');
    }

    // Correlate with Page 1 intake reasons if scanning combined form and complaints list is sparse
    final reasons = (demographics['reasonsForVisit'] as List?)?.cast<String>() ?? [];
    if (reasons.any((r) => r.contains('hanging') || r.contains('prolapse')) && !clinicalComplaints.contains('Mass Per Vagina')) {
      clinicalComplaints.add('Mass Per Vagina');
    }
    if (reasons.any((r) => r.contains('discharge') || r.contains('itching')) && !clinicalComplaints.contains('White / Foul Discharge')) {
      clinicalComplaints.add('White / Foul Discharge');
    }
    if (reasons.any((r) => r.contains('urine')) && !clinicalComplaints.contains('Urinary Incontinence') && !clinicalComplaints.contains('Burning Micturition')) {
      clinicalComplaints.add('Urinary Incontinence');
    }
    if (reasons.any((r) => r.contains('pain')) && !clinicalComplaints.contains('Lower Abdominal Pain')) {
      clinicalComplaints.add('Lower Abdominal Pain');
    }

    obstetrics['clinicalComplaints'] = clinicalComplaints;
    confidences['obstetrics'] = 0.92;

    // ==========================================
    // 2. Clinical Assessment (Page 2 / Back)
    // ==========================================
    final vitals = <String, dynamic>{};
    final popStaging = <String, dynamic>{};
    final diagnoses = <String>[];
    final medications = <String>[];
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

      vitals['systolicBp'] = (systolic != null && systolic >= 60 && systolic <= 260) ? systolic : 120;
      vitals['diastolicBp'] = (diastolic != null && diastolic >= 40 && diastolic <= 160) ? diastolic : 80;
      confidences['bp'] = (systolic != null) ? 0.95 : 0.60;

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
      vitals['pulseRate'] = (parsedPulse != null && parsedPulse >= 35 && parsedPulse <= 220) ? parsedPulse : 76;
      confidences['pulse'] = (parsedPulse != null) ? 0.95 : 0.60;

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
      vitals['spo2'] = (parsedSpo2 != null && parsedSpo2 >= 50 && parsedSpo2 <= 100) ? parsedSpo2 : 98;
      confidences['spo2'] = (parsedSpo2 != null) ? 0.95 : 0.60;

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
      vitals['bloodGlucose'] = (parsedGlucose != null && parsedGlucose >= 30 && parsedGlucose <= 600) ? parsedGlucose : 110;
      confidences['glucose'] = (parsedGlucose != null) ? 0.92 : 0.60;

      // ── Rapid Tests ──
      final rawUrine = findValueForLabel(['urine test', 'urine dipstick', 'urine', 'पिसाब जाँच']);
      final urineLineText = (rawUrine ?? '').toLowerCase();

      final urineRelatedLines = lines
          .where((l) => l.toLowerCase().contains('urine') || l.toLowerCase().contains('dipstick') || l.toLowerCase().contains('पिसाब'))
          .map((l) => l.toLowerCase())
          .toList();
      final urineContext = '$urineLineText ${urineRelatedLines.join(' ')}';

      final hasUrineBoxes = rawUrine != null && RegExp(r'\[|\]|\(|\)|[☐口Ü☑☒]').hasMatch(rawUrine);

      final urineProtein = isOptionSelected(['protein+', 'urine protein', 'protein: +', 'प्रोटिन+']) ||
          (!hasUrineBoxes && rawUrine != null && rawUrine.toLowerCase().contains('protein') && !rawUrine.toLowerCase().contains('no protein') && !rawUrine.toLowerCase().contains('nil'));

      final urineGlucose = isOptionSelected(['glucose+', 'urine glucose', 'urine sugar', 'glucose: +', 'ग्लुकोज+']) ||
          (!hasUrineBoxes && rawUrine != null && (rawUrine.toLowerCase().contains('glucose+') || rawUrine.toLowerCase().contains('sugar+')));

      final urineBlood = isOptionSelected(['blood+', 'urine blood', 'dipstick blood', 'blood: +', 'रगत+']) ||
          (!hasUrineBoxes && rawUrine != null && rawUrine.toLowerCase().contains('blood+'));

      final urineNormal = (rawUrine != null && (urineLineText.contains('normal') || urineLineText.contains('nil') || urineLineText.contains('neg'))) ||
          isOptionSelected(['urine: normal', 'urine test: normal', 'dipstick: normal']) ||
          (!urineProtein && !urineGlucose && !urineBlood && urineContext.contains('normal'));

      final urineParts = <String>[];
      if (urineProtein) urineParts.add('protein');
      if (urineGlucose) urineParts.add('glucose');
      if (urineBlood) urineParts.add('blood');

      if (urineParts.isNotEmpty) {
        vitals['urineTest'] = urineParts.join(', ');
      } else if (urineNormal || rawUrine == null || rawUrine.isEmpty) {
        vitals['urineTest'] = 'normal';
      } else {
        vitals['urineTest'] = urineLineText.contains('pos') ? 'pos' : 'normal';
      }

      final rawPregnancy = findValueForLabel(['pregnancy test', 'pregnancy', 'upt', 'hcg', 'गर्भ जाँच']);
      final pregLower = (rawPregnancy ?? '').toLowerCase();
      final hasPregBoxes = rawPregnancy != null && RegExp(r'\[|\]|\(|\)|[☐口Ü☑☒]').hasMatch(rawPregnancy);

      final pregNotDone = isOptionSelected(['not done', 'upt: not done', 'pregnancy: not done', 'pregnancy test: not done', 'जाँच नगरिएको']) ||
          (!hasPregBoxes && pregLower.contains('not'));

      final pregPos = isOptionSelected(['positive', 'pos', 'hcg: pos', 'pregnancy: pos', 'pregnancy test: pos', 'upt: pos', 'upt: positive']) ||
          (!hasPregBoxes && pregLower.contains('pos'));

      if (pregNotDone) {
        vitals['pregnancyTest'] = 'not_done';
      } else if (pregPos) {
        vitals['pregnancyTest'] = 'pos';
      } else {
        vitals['pregnancyTest'] = 'neg';
      }
      confidences['labs'] = 0.88;

      // ── POP Examination & Staging (Station 3) ──
      int? ant, mid, post, explicitHighest;

      int? parsePopStage(String? val) {
        if (val == null) return null;
        final clean = val.replaceAll(RegExp(r'\([^)]*\)'), ' ').trim();
        final digitMatch = RegExp(r'(?:stage[:\s]*)?([0-4])\b', caseSensitive: false).firstMatch(clean);
        if (digitMatch != null) {
          return int.tryParse(digitMatch.group(1)!);
        }
        final ocrMatch = RegExp(r'(?:stage[:\s]*|[:\s_])([0-4IlL|])', caseSensitive: false).firstMatch(clean);
        if (ocrMatch != null) {
          return parseStageInt(ocrMatch.group(1));
        }
        return null;
      }

      final antValue = findValueForLabel(['anterior compartment', 'anterior', 'cystocele']);
      ant = parsePopStage(antValue);

      final midValue = findValueForLabel(['middle compartment', 'middle', 'uterine', 'cervical']);
      mid = parsePopStage(midValue);

      final postValue = findValueForLabel(['posterior compartment', 'posterior', 'rectocele']);
      post = parsePopStage(postValue);

      final highestValue = findValueForLabel(['highest pop stage', 'highest stage', 'highest pop']);
      explicitHighest = parsePopStage(highestValue);

      ant ??= parseStageInt(RegExp(r'anterior(?: compartment)?(?:\s*\([^)]*\))?(?: stage)?[:\s_]*([0-4IlL|])', caseSensitive: false).firstMatch(text)?.group(1));
      mid ??= parseStageInt(RegExp(r'middle(?: compartment)?(?:\s*\([^)]*\))?(?: stage)?[:\s_]*([0-4IlL|])', caseSensitive: false).firstMatch(text)?.group(1));
      post ??= parseStageInt(RegExp(r'posterior(?: compartment)?(?:\s*\([^)]*\))?(?: stage)?[:\s_]*([0-4IlL|])', caseSensitive: false).firstMatch(text)?.group(1));
      explicitHighest ??= parseStageInt(RegExp(r'highest(?: pop)?(?: stage)?[:\s_]*([0-4IlL|])', caseSensitive: false).firstMatch(text)?.group(1));

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

      final a = ant ?? 0;
      final m = mid ?? 0;
      final p = post ?? 0;
      final highest = explicitHighest ?? [a, m, p].reduce(max);

      popStaging['anteriorStage'] = a;
      popStaging['middleStage'] = m;
      popStaging['posteriorStage'] = p;
      popStaging['highestPopStage'] = highest;

      final uterusOutside = isOptionSelected(['no (prolapsed)', 'prolapsed outside', 'uterus inside: no']) || highest >= 2;
      popStaging['uterusInside'] = !uterusOutside;

      // Cervix Appearance (Station 2)
      final cervixVal = findValueForLabel(['cervix appearance', 'cervix:', 'cervix', 'पाठेघरको मुख']);
      if (cervixVal != null && cervixVal.isNotEmpty) {
        popStaging['cervixRemarks'] = cervixVal.trim();
      } else if (isOptionSelected(['erosion', 'इरोज़न'])) {
        popStaging['cervixRemarks'] = 'Erosion';
      } else if (isOptionSelected(['polyp', 'पोलिप'])) {
        popStaging['cervixRemarks'] = 'Polyp';
      } else if (isOptionSelected(['hypertrophy', 'hypertrophied'])) {
        popStaging['cervixRemarks'] = 'Hypertrophied';
      } else if (lowerText.contains('cervix') && lowerText.contains('normal')) {
        popStaging['cervixRemarks'] = 'Normal / Smooth';
      }

      // Vagina / Vulva (Station 2)
      final vaginaVal = findValueForLabel(['vagina / vulva', 'vagina/vulva', 'vagina:', 'vulva:', 'योनी']);
      if (vaginaVal != null && vaginaVal.isNotEmpty) {
        popStaging['vaginaRemarks'] = vaginaVal.trim();
      } else if (isOptionSelected(['atrophy', 'atrophic', 'सुकेको'])) {
        popStaging['vaginaRemarks'] = 'Atrophic';
      } else if (isOptionSelected(['mild discharge', 'vaginal discharge'])) {
        popStaging['vaginaRemarks'] = 'Mild discharge';
      } else if (lowerText.contains('vagina') && lowerText.contains('normal')) {
        popStaging['vaginaRemarks'] = 'Normal';
      }

      if (page2OmrPop != null && (page2OmrPop['tone_weak']?.isMarked == true || page2OmrPop['tone_torn']?.isMarked == true || page2OmrPop['tone_normal']?.isMarked == true)) {
        if (page2OmrPop['tone_torn']?.isMarked == true) {
          popStaging['pelvicFloorTone'] = 'hypertonic';
        } else if (page2OmrPop['tone_weak']?.isMarked == true) {
          popStaging['pelvicFloorTone'] = 'weak';
        } else {
          popStaging['pelvicFloorTone'] = 'normal';
        }
      } else {
        if (isOptionSelected(['hypertonic', 'tone: hypertonic', 'torn', 'tone: torn', 'कडा'])) {
          popStaging['pelvicFloorTone'] = 'hypertonic';
        } else if (isOptionSelected(['tone: weak', 'weak tone', 'weak', 'कमजोर']) || highest >= 2) {
          popStaging['pelvicFloorTone'] = 'weak';
        } else {
          popStaging['pelvicFloorTone'] = 'normal';
        }
      }
      confidences['popStaging'] = 0.94;

      // ── Diagnoses (Station 5) ──
      if (page2OmrDiagnoses != null && page2OmrDiagnoses.values.any((r) => r.isMarked)) {
        for (final entry in page2OmrDiagnoses.entries) {
          if (entry.value.isMarked && !diagnoses.contains(entry.key)) {
            diagnoses.add(entry.key);
          }
        }
      }
      if (highest >= 2 || isOptionSelected(['pop (pelvic', 'pelvic organ prolapse'])) {
        if (!diagnoses.contains('POP')) diagnoses.add('POP');
      }
      if (isOptionSelected(['candidal infection', 'candidiasis', 'candid infection'])) {
        if (!diagnoses.contains('candid infection')) diagnoses.add('candid infection');
      }
      if (isOptionSelected(['bacterial vaginosis'])) {
        if (!diagnoses.contains('bacterial vaginosis')) diagnoses.add('bacterial vaginosis');
      }
      if (isOptionSelected(['cervicitis'])) {
        if (!diagnoses.contains('cervicitis')) diagnoses.add('cervicitis');
      }
      if (isOptionSelected(['cystitis', 'uti'])) {
        if (!diagnoses.contains('cystitis')) diagnoses.add('cystitis');
      }
      if (isOptionSelected(['hypertension']) || (vitals['systolicBp'] as int? ?? 0) >= 140) {
        if (!diagnoses.contains('hypertension')) diagnoses.add('hypertension');
      }
      if (isOptionSelected(['diabetes mellitus', 'diabetes']) || (vitals['bloodGlucose'] as int? ?? 0) >= 180) {
        if (!diagnoses.contains('diabetes mellitus')) diagnoses.add('diabetes mellitus');
      }
      confidences['diagnoses'] = diagnoses.isNotEmpty ? 0.92 : 0.40;

      // ── Prescriptions & Medications ──
      if (isOptionSelected(['metronidazole']) || RegExp(r'met?ronida|me\+ronida', caseSensitive: false).hasMatch(text)) {
        medications.add('Metronidazole');
      }
      if (isOptionSelected(['fluconazole']) || RegExp(r'f?luconazole|f1uconazole', caseSensitive: false).hasMatch(text)) {
        medications.add('Fluconazole');
      }
      if (isOptionSelected(['ciprofloxacin']) || RegExp(r'ciproflox', caseSensitive: false).hasMatch(text)) {
        medications.add('Ciprofloxacin');
      }
      if (isOptionSelected(['clotrimazole']) || RegExp(r'clotrimaz', caseSensitive: false).hasMatch(text)) {
        medications.add('Clotrimazole');
      }
      if (highest >= 2 || isOptionSelected(['ring pessary', 'pessary']) || RegExp(r'pessary', caseSensitive: false).hasMatch(text)) {
        medications.add('Ring Pessary');
      }
      confidences['medications'] = medications.isNotEmpty ? 0.85 : 0.40;

      // ── Referrals ──
      if (highest >= 3 || lowerText.contains('scheer') || lowerText.contains('surgical referral')) {
        surgicalReferral = 'Scheer Memorial Hospital';
      }
      followUp = highest >= 2 ? 'GynaeSupport Nurse' : 'Health Post';
    }

    // Calculate overall confidence based on active fields
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
      medications: medications,
      surgicalReferral: surgicalReferral,
      followUpDestination: followUp,
      fieldConfidences: confidences,
      overallConfidence: double.parse(avgConf.toStringAsFixed(2)),
      rawText: text,
      scannedAt: DateTime.now(),
    );
  }

  /// Check if a line looks like a label header (not a value)
  static bool _isLabel(String line) {
    final lower = line.toLowerCase().trim();
    return lower.endsWith(':') ||
        lower.startsWith('station') ||
        lower.startsWith('camp') ||
        lower.startsWith('date') ||
        lower.contains('form') ||
        lower.contains('gynocamp') ||
        lower.isEmpty;
  }

  /// Capitalize first letter of a word
  static String _capitalizeFirst(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
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
Highest POP Stage: 3
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
Treatments & Prescriptions:
[x] Ring Pessary (Size 65mm fitted)
[x] Metronidazole 400mg PO BD x 7d
[x] Fluconazole 150mg stat

Station 6: Outtake & Referral
Surgical Referral: Scheer Memorial Hospital (Vaginal Hysterectomy evaluation)
Follow-up: GynaeSupport Nurse in 2 weeks
''';

  /// Sample 3: Full 2-Page Combined Intake
  static const String sampleFullFormText = '''
$samplePage1Text
----------------------------------------
$samplePage2Text
''';
}
