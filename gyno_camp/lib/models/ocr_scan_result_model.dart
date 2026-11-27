import 'dart:convert';
import 'dart:typed_data';
import '../core/utils/form_page_identifier.dart';
import 'patient_model.dart';

class OcrScanResultModel {
  final int pageNumber; // 1 = Front Page, 2 = Back Page, 0 = Full Intake
  final int? detectedPage; // True page detected from form badge/content (1, 2, or 0/null)
  final String? imagePath;
  final String? page1ImagePath;
  final String? page2ImagePath;
  final String? page1RawText;
  final String? page2RawText;
  final bool isDualPage;
  final bool isSimulated; // true = ML Kit unavailable, demo fallback text was used
  final String ocrEngine; // 'gemini_flash', 'mlkit_offline', or 'simulation'
  final Map<String, dynamic> demographics;
  final Map<String, dynamic> obstetrics;
  final Map<String, dynamic> vitals;
  final Map<String, dynamic> popStaging;
  final List<String> diagnoses;
  final List<String> counseling;
  final List<String> medications;
  final String? surgicalReferral;
  final String? followUpDestination;
  final bool surgeryDone;
  final String? surgeryType; // 'Open surgery', 'Laparoscopy', 'Vaginal route'
  final bool ringPessary;
  final String? pessaryType; // 'ring', 'ring with support', 'ring with knob'
  final int? ringPessarySize; // in mm, e.g. 65, 70
  final String? examiningDoctor; // Lead/attending doctor identified on Page 2
  final List<String> attendingDoctors; // Multi-doctor list if multiple attended
  final String? examiningNurse; // Lead nurse identified on Page 2
  final List<String> attendingNurses; // Multi-nurse list if multiple nurses attended
  final String? treatmentLevel; // 'council_level', 'full_check_up', or null
  final String? clinicalNotes; // Station 6 Clinical Notes / Outtake Remarks
  final String? intakeDate; // Page 1 Registration / Intake Date
  final String? anamnesisDate; // Station 1 Anamnesis Date
  final String? examDate; // Station 2 Exam Date
  final String? treatmentDate; // Station 5 Treatment Date
  final String? conclusionDate; // Station 4 Conclusion Date
  final String? labTestDate; // Station 3 Lab Test Date
  final String? outtakeDate; // Station 6 Outtake Date
  final Map<String, double> fieldConfidences;
  final double overallConfidence;
  final String rawText;
  final DateTime scannedAt;

  const OcrScanResultModel({
    required this.pageNumber,
    this.detectedPage,
    this.imagePath,
    this.page1ImagePath,
    this.page2ImagePath,
    this.page1RawText,
    this.page2RawText,
    this.isDualPage = false,
    this.isSimulated = false,
    this.ocrEngine = 'mlkit_offline',
    required this.demographics,
    required this.obstetrics,
    required this.vitals,
    required this.popStaging,
    required this.diagnoses,
    this.counseling = const [],
    required this.medications,
    this.surgicalReferral,
    this.followUpDestination,
    this.surgeryDone = false,
    this.surgeryType,
    this.ringPessary = false,
    this.pessaryType,
    this.ringPessarySize,
    this.examiningDoctor,
    this.attendingDoctors = const [],
    this.examiningNurse,
    this.attendingNurses = const [],
    this.treatmentLevel,
    this.clinicalNotes,
    this.intakeDate,
    this.anamnesisDate,
    this.examDate,
    this.treatmentDate,
    this.conclusionDate,
    this.labTestDate,
    this.outtakeDate,
    required this.fieldConfidences,
    required this.overallConfidence,
    required this.rawText,
    required this.scannedAt,
  });

  String? get patientTokenId =>
      (demographics['patientTokenId'] as String? ?? demographics['patientId'] as String?)?.trim();

  String? get patientId => patientTokenId;

  /// Effective Anamnesis Date (falls back to intakeDate if not explicitly set)
  String? get effectiveAnamnesisDate => (anamnesisDate != null && anamnesisDate!.isNotEmpty) ? anamnesisDate : intakeDate;

  OcrScanResultModel copyWith({
    int? pageNumber,
    int? detectedPage,
    String? imagePath,
    bool clearImagePath = false,
    String? page1ImagePath,
    bool clearPage1ImagePath = false,
    String? page2ImagePath,
    bool clearPage2ImagePath = false,
    String? page1RawText,
    String? page2RawText,
    bool? isDualPage,
    bool? isSimulated,
    String? ocrEngine,
    Map<String, dynamic>? demographics,
    Map<String, dynamic>? obstetrics,
    Map<String, dynamic>? vitals,
    Map<String, dynamic>? popStaging,
    List<String>? diagnoses,
    List<String>? counseling,
    List<String>? medications,
    String? surgicalReferral,
    bool clearSurgicalReferral = false,
    String? followUpDestination,
    bool clearFollowUpDestination = false,
    bool? surgeryDone,
    String? surgeryType,
    bool clearSurgeryType = false,
    bool? ringPessary,
    String? pessaryType,
    bool clearPessaryType = false,
    int? ringPessarySize,
    bool clearRingPessarySize = false,
    String? examiningDoctor,
    bool clearExaminingDoctor = false,
    List<String>? attendingDoctors,
    String? examiningNurse,
    bool clearExaminingNurse = false,
    List<String>? attendingNurses,
    String? treatmentLevel,
    bool clearTreatmentLevel = false,
    String? clinicalNotes,
    bool clearClinicalNotes = false,
    String? intakeDate,
    bool clearIntakeDate = false,
    String? anamnesisDate,
    bool clearAnamnesisDate = false,
    String? examDate,
    bool clearExamDate = false,
    String? treatmentDate,
    bool clearTreatmentDate = false,
    String? conclusionDate,
    bool clearConclusionDate = false,
    String? labTestDate,
    bool clearLabTestDate = false,
    String? outtakeDate,
    bool clearOuttakeDate = false,
    Map<String, double>? fieldConfidences,
    double? overallConfidence,
    String? rawText,
    DateTime? scannedAt,
  }) {
    return OcrScanResultModel(
      pageNumber: pageNumber ?? this.pageNumber,
      detectedPage: detectedPage ?? this.detectedPage,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      page1ImagePath: clearPage1ImagePath ? null : (page1ImagePath ?? this.page1ImagePath),
      page2ImagePath: clearPage2ImagePath ? null : (page2ImagePath ?? this.page2ImagePath),
      page1RawText: page1RawText ?? this.page1RawText,
      page2RawText: page2RawText ?? this.page2RawText,
      isDualPage: isDualPage ?? this.isDualPage,
      isSimulated: isSimulated ?? this.isSimulated,
      ocrEngine: ocrEngine ?? this.ocrEngine,
      demographics: demographics ?? Map<String, dynamic>.from(this.demographics),
      obstetrics: obstetrics ?? Map<String, dynamic>.from(this.obstetrics),
      vitals: vitals ?? Map<String, dynamic>.from(this.vitals),
      popStaging: popStaging ?? Map<String, dynamic>.from(this.popStaging),
      diagnoses: diagnoses ?? List<String>.from(this.diagnoses),
      counseling: counseling ?? List<String>.from(this.counseling),
      medications: medications ?? List<String>.from(this.medications),
      surgicalReferral: clearSurgicalReferral ? null : (surgicalReferral ?? this.surgicalReferral),
      followUpDestination: clearFollowUpDestination ? null : (followUpDestination ?? this.followUpDestination),
      surgeryDone: surgeryDone ?? this.surgeryDone,
      surgeryType: clearSurgeryType ? null : (surgeryType ?? this.surgeryType),
      ringPessary: ringPessary ?? this.ringPessary,
      pessaryType: clearPessaryType ? null : (pessaryType ?? this.pessaryType),
      ringPessarySize: clearRingPessarySize ? null : (ringPessarySize ?? this.ringPessarySize),
      examiningDoctor: clearExaminingDoctor ? null : (examiningDoctor ?? this.examiningDoctor),
      attendingDoctors: attendingDoctors ?? List<String>.from(this.attendingDoctors),
      examiningNurse: clearExaminingNurse ? null : (examiningNurse ?? this.examiningNurse),
      attendingNurses: attendingNurses ?? List<String>.from(this.attendingNurses),
      treatmentLevel: clearTreatmentLevel ? null : (treatmentLevel != null ? PatientModel.normalizeTreatmentLevel(treatmentLevel) : this.treatmentLevel),
      clinicalNotes: clearClinicalNotes ? null : (clinicalNotes ?? this.clinicalNotes),
      intakeDate: clearIntakeDate ? null : (intakeDate ?? this.intakeDate),
      anamnesisDate: clearAnamnesisDate ? null : (anamnesisDate ?? this.anamnesisDate),
      examDate: clearExamDate ? null : (examDate ?? this.examDate),
      treatmentDate: clearTreatmentDate ? null : (treatmentDate ?? this.treatmentDate),
      conclusionDate: clearConclusionDate ? null : (conclusionDate ?? this.conclusionDate),
      labTestDate: clearLabTestDate ? null : (labTestDate ?? this.labTestDate),
      outtakeDate: clearOuttakeDate ? null : (outtakeDate ?? this.outtakeDate),
      fieldConfidences: fieldConfidences ?? Map<String, double>.from(this.fieldConfidences),
      overallConfidence: overallConfidence ?? this.overallConfidence,
      rawText: rawText ?? this.rawText,
      scannedAt: scannedAt ?? this.scannedAt,
    );
  }

  /// Merges Page 1 (Demographics & Obstetric history) with Page 2 (POP Exam, Vitals & Prescriptions)
  static OcrScanResultModel merge(OcrScanResultModel page1, OcrScanResultModel page2) {
    final mergedConfidences = <String, double>{
      ...page1.fieldConfidences,
      ...page2.fieldConfidences,
    };

    final totalConf = mergedConfidences.values.fold<double>(0.0, (sum, val) => sum + val);
    final avgConf = mergedConfidences.isNotEmpty ? totalConf / mergedConfidences.length : 0.85;

    final combinedText = '''
--- [PAGE 1: FRONT (DEMOGRAPHICS & ANAMNESIS)] ---
${page1.rawText}

--- [PAGE 2: BACK (EXAM, VITALS & TREATMENT)] ---
${page2.rawText}
''';

    final mergedEngine = (page1.ocrEngine == 'gemini_flash' || page2.ocrEngine == 'gemini_flash')
        ? 'gemini_flash'
        : page1.ocrEngine;

    final mergedDoctor = page2.examiningDoctor ?? page1.examiningDoctor;
    final mergedDoctors = <String>{
      ...page1.attendingDoctors,
      ...page2.attendingDoctors,
      if (mergedDoctor != null && mergedDoctor.isNotEmpty) mergedDoctor,
    }.toList();

    final mergedNurse = page2.examiningNurse ?? page1.examiningNurse;
    final mergedNurses = <String>{
      ...page1.attendingNurses,
      ...page2.attendingNurses,
      if (mergedNurse != null && mergedNurse.isNotEmpty) mergedNurse,
    }.toList();

    // Harmonize station dates across dual pages
    // All stations on a patient's Yellow Form encounter share the same camp date.
    // If Page 2 stations have consensus (e.g. 2083-07-06), and Page 1's intakeDate
    // was misread with month 01 vs 07, harmonize intakeDate to the confirmed camp date.
    final p2Dates = [
      page2.examDate,
      page2.labTestDate,
      page2.conclusionDate,
      page2.treatmentDate,
      page2.outtakeDate,
    ].where((d) => d != null && d.trim().isNotEmpty).map((d) => d!.trim()).toList();

    String? harmonizedIntake = page1.intakeDate ??
        (page1.demographics['intakeDate'] as String?) ??
        (page1.demographics['date'] as String?) ??
        page2.intakeDate ??
        (page2.demographics['intakeDate'] as String?) ??
        (page2.demographics['date'] as String?) ??
        page1.anamnesisDate ??
        page2.anamnesisDate ??
        (p2Dates.isNotEmpty ? p2Dates.first : null);
    if (harmonizedIntake != null && p2Dates.isNotEmpty) {
      final dateCounts = <String, int>{};
      for (final d in p2Dates) {
        dateCounts[d] = (dateCounts[d] ?? 0) + 1;
      }
      final dominantP2Date = dateCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      if ((dateCounts[dominantP2Date] ?? 0) >= 2) {
        final p1Clean = harmonizedIntake.replaceAll(RegExp(r'\s*BS', caseSensitive: false), '').trim();
        final p2Clean = dominantP2Date.replaceAll(RegExp(r'\s*BS', caseSensitive: false), '').trim();
        final p1Parts = p1Clean.split(RegExp(r'[-/]'));
        final p2Parts = p2Clean.split(RegExp(r'[-/]'));
        if (p1Parts.length == 3 && p2Parts.length == 3) {
          final m1 = p1Parts[1].padLeft(2, '0');
          final m2 = p2Parts[1].padLeft(2, '0');
          final is17Confusion = (m1 == '01' && m2 == '07') || (m1 == '07' && m2 == '01');
          if (p1Parts[0] == p2Parts[0] && p1Parts[2] == p2Parts[2] && is17Confusion) {
            harmonizedIntake = dominantP2Date;
          }
        }
      }
    }

    final mergedDemographics = _mergeMapNullAware(page2.demographics, page1.demographics);
    final mergedTokenId = (mergedDemographics['patientId'] as String?)?.trim().isNotEmpty == true
        ? (mergedDemographics['patientId'] as String).trim()
        : ((mergedDemographics['patientTokenId'] as String?)?.trim().isNotEmpty == true
            ? (mergedDemographics['patientTokenId'] as String).trim()
            : null);
    if (mergedTokenId != null) {
      mergedDemographics['patientId'] = mergedTokenId;
      mergedDemographics['patientTokenId'] = mergedTokenId;
    }
    if (harmonizedIntake != null) {
      mergedDemographics['intakeDate'] = harmonizedIntake;
      mergedDemographics['date'] = harmonizedIntake;
    }
    String? nonEmptyStr(dynamic v) {
      final s = v?.toString().trim();
      return (s != null && s.isNotEmpty) ? s : null;
    }
    final resolvedAnamnesis = nonEmptyStr(page1.anamnesisDate) ??
        nonEmptyStr(page1.demographics['anamnesisDate']) ??
        nonEmptyStr(page2.anamnesisDate) ??
        nonEmptyStr(page2.demographics['anamnesisDate']) ??
        harmonizedIntake;
    if (resolvedAnamnesis != null) {
      mergedDemographics['anamnesisDate'] = resolvedAnamnesis;
    }

    return OcrScanResultModel(
      pageNumber: 0, // 0 = Full Combined Intake
      isDualPage: true,
      isSimulated: page1.isSimulated || page2.isSimulated,
      ocrEngine: mergedEngine,
      imagePath: page1.imagePath ?? page2.imagePath,
      page1ImagePath: page1.imagePath,
      page2ImagePath: page2.imagePath,
      page1RawText: page1.rawText,
      page2RawText: page2.rawText,
      demographics: mergedDemographics,
      obstetrics: () {
        final mergedObs = _mergeMapNullAware(page1.obstetrics, page2.obstetrics);
        final c1 = (page1.obstetrics['clinicalComplaints'] as List?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() ?? [];
        final c2 = (page2.obstetrics['clinicalComplaints'] as List?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() ?? [];
        final combined = <String>{...c1, ...c2}.toList();
        if (combined.isNotEmpty) {
          mergedObs['clinicalComplaints'] = combined;
        }
        return mergedObs;
      }(),
      vitals: _mergeMapNullAware(page1.vitals, page2.vitals),
      popStaging: () {
        final mergedPop = _mergeMapNullAware(page1.popStaging, page2.popStaging);
        final ant = mergedPop['anteriorStage'] as int?;
        final mid = mergedPop['middleStage'] as int?;
        final post = mergedPop['posteriorStage'] as int?;
        final highest = (mergedPop['highestPopStage'] ?? mergedPop['highestStage'] ?? mergedPop['stage']) as int? ??
            (ant != null || mid != null || post != null
                ? [ant ?? 0, mid ?? 0, post ?? 0].reduce((a, b) => a > b ? a : b)
                : null);
        if (highest != null) {
          mergedPop['highestPopStage'] = highest;
          mergedPop['highestStage'] = highest;
          mergedPop['stage'] = highest;
        }
        return mergedPop;
      }(),
      diagnoses: List<String>.from(page2.diagnoses.isNotEmpty ? page2.diagnoses : page1.diagnoses),
      counseling: List<String>.from(page2.counseling.isNotEmpty ? page2.counseling : page1.counseling),
      medications: List<String>.from(page2.medications.isNotEmpty ? page2.medications : page1.medications),
      surgicalReferral: page2.surgicalReferral ?? page1.surgicalReferral,
      followUpDestination: page2.followUpDestination ?? page1.followUpDestination,
      surgeryDone: page2.surgeryDone || page1.surgeryDone,
      surgeryType: page2.surgeryType ?? page1.surgeryType,
      ringPessary: page2.ringPessary || page1.ringPessary,
      pessaryType: page2.pessaryType ?? page1.pessaryType,
      ringPessarySize: page2.ringPessarySize ?? page1.ringPessarySize,
      examiningDoctor: mergedDoctor,
      attendingDoctors: mergedDoctors,
      examiningNurse: mergedNurse,
      attendingNurses: mergedNurses,
      treatmentLevel: PatientModel.normalizeTreatmentLevel((page1.treatmentLevel != null && page1.treatmentLevel!.isNotEmpty)
          ? page1.treatmentLevel
          : (page2.treatmentLevel ?? page1.treatmentLevel)),
      clinicalNotes: page2.clinicalNotes ?? page1.clinicalNotes,
      intakeDate: harmonizedIntake,
      anamnesisDate: resolvedAnamnesis,
      examDate: page2.examDate ?? page1.examDate,
      treatmentDate: page2.treatmentDate ?? page1.treatmentDate,
      conclusionDate: page2.conclusionDate ?? page1.conclusionDate,
      labTestDate: page2.labTestDate ?? page1.labTestDate,
      outtakeDate: page2.outtakeDate ?? page1.outtakeDate,
      fieldConfidences: mergedConfidences,
      overallConfidence: double.parse(avgConf.toStringAsFixed(2)),
      rawText: combinedText,
      scannedAt: DateTime.now(),
    );
  }

  /// Helper to get confidence tier for a given field
  String getConfidenceTier(String fieldKey) {
    // Check direct key in fieldConfidences first
    double? conf = fieldConfidences[fieldKey];

    // Smart aliases if direct key not present
    if (conf == null) {
      switch (fieldKey) {
        case 'firstName':
        case 'first_name':
          conf = fieldConfidences['firstName'] ?? fieldConfidences['name'];
          break;
        case 'surname':
        case 'lastName':
        case 'last_name':
          conf = fieldConfidences['surname'] ?? fieldConfidences['name'];
          break;
        case 'name':
          conf = fieldConfidences['name'] ?? fieldConfidences['firstName'] ?? fieldConfidences['surname'];
          break;
        case 'relative':
        case 'relativeName':
        case 'spouseOrFatherName':
          conf = fieldConfidences['relativeName'] ??
              fieldConfidences['relativeSurname'] ??
              fieldConfidences['relative'] ??
              fieldConfidences['spouseOrFatherName'];
          break;
        case 'relativeSurname':
          conf = fieldConfidences['relativeSurname'] ?? fieldConfidences['relative'];
          break;
        case 'mobile':
          conf = fieldConfidences['mobile'] ?? fieldConfidences['phone'];
          break;
        case 'contactMobile':
          conf = fieldConfidences['contactMobile'] ?? fieldConfidences['mobile'];
          break;
        case 'ward':
          conf = fieldConfidences['ward'];
          break;
        case 'age':
          conf = fieldConfidences['age'];
          break;
      }
    }

    // Fallback: If a field has a detected, non-empty value in demographics,
    // it was successfully extracted by OCR, so confidence is high.
    if (conf == null) {
      final demoVal = demographics[fieldKey]?.toString().trim();
      if (demoVal != null && demoVal.isNotEmpty && demoVal.toLowerCase() != 'null') {
        conf = 0.95;
      }
    }

    conf ??= overallConfidence;
    if (conf >= 0.85) return 'HIGH';
    if (conf >= 0.60) return 'MEDIUM';
    return 'LOW';
  }

  Map<String, dynamic> toMap() {
    return {
      'pageNumber': pageNumber,
      'detectedPage': detectedPage,
      'isSimulated': isSimulated ? 1 : 0,
      'ocrEngine': ocrEngine,
      'imagePath': imagePath,
      'page1ImagePath': page1ImagePath,
      'page2ImagePath': page2ImagePath,
      'page1RawText': page1RawText,
      'page2RawText': page2RawText,
      'isDualPage': isDualPage ? 1 : 0,
      'demographics': demographics,
      'obstetrics': obstetrics,
      'vitals': vitals,
      'popStaging': popStaging,
      'diagnoses': diagnoses,
      'counseling': counseling,
      'medications': medications,
      'surgicalReferral': surgicalReferral,
      'followUpDestination': followUpDestination,
      'surgeryDone': surgeryDone ? 1 : 0,
      'surgeryType': surgeryType,
      'ringPessary': ringPessary ? 1 : 0,
      'pessaryType': pessaryType,
      'ringPessarySize': ringPessarySize,
      'examiningDoctor': examiningDoctor,
      'attendingDoctors': attendingDoctors.join(','),
      'examiningNurse': examiningNurse,
      'attendingNurses': attendingNurses.join(','),
      'treatmentLevel': PatientModel.normalizeTreatmentLevel(treatmentLevel),
      'clinicalNotes': clinicalNotes,
      'intakeDate': intakeDate,
      'anamnesisDate': anamnesisDate,
      'examDate': examDate,
      'treatmentDate': treatmentDate,
      'conclusionDate': conclusionDate,
      'labTestDate': labTestDate,
      'outtakeDate': outtakeDate,
      'fieldConfidences': fieldConfidences,
      'overallConfidence': overallConfidence,
      'rawText': rawText,
      'scannedAt': scannedAt.toIso8601String(),
    };
  }

  factory OcrScanResultModel.fromMap(Map<String, dynamic> map) {
    List<String> parseStringList(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      }
      if (raw is String && raw.trim().isNotEmpty) {
        return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
      return const [];
    }

    Map<String, double> parseConfidences(dynamic raw) {
      if (raw is Map) {
        final out = <String, double>{};
        raw.forEach((k, v) {
          if (v is num) out[k.toString()] = v.toDouble();
        });
        return out;
      }
      return {};
    }

    return OcrScanResultModel(
      pageNumber: (map['pageNumber'] as num?)?.toInt() ?? 0,
      detectedPage: (map['detectedPage'] as num?)?.toInt(),
      imagePath: map['imagePath'] as String?,
      page1ImagePath: map['page1ImagePath'] as String?,
      page2ImagePath: map['page2ImagePath'] as String?,
      page1RawText: map['page1RawText'] as String?,
      page2RawText: map['page2RawText'] as String?,
      isDualPage: map['isDualPage'] == true || map['isDualPage'] == 1,
      isSimulated: map['isSimulated'] == true || map['isSimulated'] == 1,
      ocrEngine: map['ocrEngine'] as String? ?? 'gemini_flash',
      demographics: map['demographics'] is Map
          ? Map<String, dynamic>.from(map['demographics'] as Map)
          : {},
      obstetrics: map['obstetrics'] is Map
          ? Map<String, dynamic>.from(map['obstetrics'] as Map)
          : {},
      vitals: map['vitals'] is Map
          ? Map<String, dynamic>.from(map['vitals'] as Map)
          : {},
      popStaging: map['popStaging'] is Map
          ? Map<String, dynamic>.from(map['popStaging'] as Map)
          : {},
      diagnoses: parseStringList(map['diagnoses']),
      counseling: parseStringList(map['counseling']),
      medications: parseStringList(map['medications']),
      surgicalReferral: map['surgicalReferral'] as String?,
      followUpDestination: map['followUpDestination'] as String?,
      surgeryDone: map['surgeryDone'] == true || map['surgeryDone'] == 1,
      surgeryType: map['surgeryType'] as String?,
      ringPessary: map['ringPessary'] == true || map['ringPessary'] == 1,
      pessaryType: map['pessaryType'] as String?,
      ringPessarySize: (map['ringPessarySize'] as num?)?.toInt(),
      examiningDoctor: map['examiningDoctor'] as String?,
      attendingDoctors: parseStringList(map['attendingDoctors']),
      examiningNurse: map['examiningNurse'] as String?,
      attendingNurses: parseStringList(map['attendingNurses']),
      treatmentLevel: map['treatmentLevel'] as String?,
      clinicalNotes: map['clinicalNotes'] as String?,
      intakeDate: map['intakeDate'] as String?,
      anamnesisDate: map['anamnesisDate'] as String?,
      examDate: map['examDate'] as String?,
      treatmentDate: map['treatmentDate'] as String?,
      conclusionDate: map['conclusionDate'] as String?,
      labTestDate: map['labTestDate'] as String?,
      outtakeDate: map['outtakeDate'] as String?,
      fieldConfidences: parseConfidences(map['fieldConfidences']),
      overallConfidence: (map['overallConfidence'] as num?)?.toDouble() ?? 0.9,
      rawText: map['rawText'] as String? ?? '',
      scannedAt: DateTime.tryParse(map['scannedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  factory OcrScanResultModel.empty() {
    return OcrScanResultModel(
      pageNumber: 0,
      ocrEngine: 'mlkit_offline',
      demographics: {},
      obstetrics: {},
      vitals: {},
      popStaging: {},
      diagnoses: [],
      medications: [],
      examiningDoctor: null,
      attendingDoctors: const [],
      examiningNurse: null,
      attendingNurses: const [],
      treatmentLevel: null,
      clinicalNotes: null,
      treatmentDate: null,
      conclusionDate: null,
      labTestDate: null,
      outtakeDate: null,
      fieldConfidences: {},
      overallConfidence: 0.0,
      rawText: '',
      scannedAt: DateTime.now(),
    );
  }

  bool get isCounseling {
    final norm = PatientModel.normalizeTreatmentLevel(treatmentLevel);
    return norm == 'counseling' || norm == 'council_level';
  }
  bool get isGynocheckup {
    final norm = PatientModel.normalizeTreatmentLevel(treatmentLevel);
    return norm == 'gyno_checkup' || norm == 'full_check_up';
  }
  bool get isCouncilLevel => isCounseling;
  bool get isFullCheckUp => isGynocheckup;
  bool get isUnassigned => !isCounseling && !isGynocheckup;
  String get consultationLabel => isCounseling ? 'Counseling' : (isGynocheckup ? 'Gynocheckup' : 'Unassigned');
  String get treatmentLabel => consultationLabel;

  /// Returns true if followUpDestination indicates a hospital referral/visit.
  bool get isFollowUpHospitalSelected {
    final d = followUpDestination?.trim().toLowerCase();
    if (d == null || d.isEmpty) return false;
    return d != 'health post' &&
        d != 'gynaesupport nurse' &&
        d != 'no follow up needed' &&
        d != 'camp follow-up day';
  }

  /// Returns the specific hospital name (if any) or null if generic/none.
  String? get followUpHospitalName {
    if (!isFollowUpHospitalSelected) return null;
    final d = followUpDestination!.trim();
    if (d.toLowerCase() == 'hospital') return null;
    if (d.toLowerCase().startsWith('hospital:')) {
      return d.substring('hospital:'.length).trim();
    }
    return d;
  }

  /// Null/empty-aware map merge for dual-page OCR results.
  /// Later page values only override earlier page values when they are
  /// non-null and non-empty. This prevents Page 2's default empty lists /
  /// null fields from wiping Page 1's real extracted data.
  static Map<String, dynamic> _mergeMapNullAware(
    Map<String, dynamic> base,
    Map<String, dynamic> overlay,
  ) {
    final result = Map<String, dynamic>.from(base);
    for (final entry in overlay.entries) {
      final value = entry.value;
      // Skip null values — keep base
      if (value == null) continue;
      // Skip empty strings
      if (value is String && value.isEmpty) continue;
      // Skip empty lists
      if (value is List && value.isEmpty) continue;
      // Skip empty maps
      if (value is Map && value.isEmpty) continue;
      // Non-null, non-empty: override
      result[entry.key] = value;
    }
    return result;
  }
}

/// Represents a raw Yellow Form scan saved locally while offline, waiting for Internet connectivity
/// to be processed via Gemini Cloud OCR and synced to the central server.
class OfflineScanQueueItem {
  final String id;
  final String campId;
  final String campCode;
  final String? page1ImageBase64;
  final String? page1ImagePath;
  final String? page2ImageBase64;
  final String? page2ImagePath;
  final String? patientTokenHint;
  final String? intakeDateHint;
  final String? examiningNurseHint;
  final String? examiningDoctorHint;
  final String status; // 'pending', 'processing', 'completed', 'failed'
  final String reviewStatus; // 'pending', 'needs_review', 'verified'
  final String? errorMessage;
  final String? committedPatientUuid;
  final String? committedPatientId;
  final String? committedPatientName;
  final String? committedVisitId;
  final String? extractedJson;
  final String createdByUserId;
  final String createdByUserName;
  final String createdByUserRole;
  final String deviceId;
  final String tenantId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OfflineScanQueueItem({
    required this.id,
    required this.campId,
    required this.campCode,
    this.page1ImageBase64,
    this.page1ImagePath,
    this.page2ImageBase64,
    this.page2ImagePath,
    this.patientTokenHint,
    this.intakeDateHint,
    this.examiningNurseHint,
    this.examiningDoctorHint,
    this.status = 'pending',
    this.reviewStatus = 'pending',
    this.errorMessage,
    this.committedPatientUuid,
    this.committedPatientId,
    this.committedPatientName,
    this.committedVisitId,
    this.extractedJson,
    required this.createdByUserId,
    this.createdByUserName = 'Field Staff',
    this.createdByUserRole = 'DATA_TAKER',
    required this.deviceId,
    this.tenantId = 'tenant_default',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasPage1 => (page1ImageBase64 != null && page1ImageBase64!.isNotEmpty) || (page1ImagePath != null && page1ImagePath!.isNotEmpty);
  bool get hasPage2 => (page2ImageBase64 != null && page2ImageBase64!.isNotEmpty) || (page2ImagePath != null && page2ImagePath!.isNotEmpty);
  bool get hasAnyImage => hasPage1 || hasPage2;
  bool get isCompleted => status == 'completed';
  bool get isConflict => status == 'conflict';
  bool get isPendingOrFailed => status == 'pending' || status == 'failed' || status == 'processing' || status == 'conflict';
  bool get needsReview => reviewStatus == 'needs_review';
  bool get isVerified => reviewStatus == 'verified';
  String? get patientIdHint =>
      (committedPatientId != null && committedPatientId!.isNotEmpty) ? committedPatientId : patientTokenHint;

  /// Normalized Form / Token Number if known from committed ID, hint, extracted JSON, or filename.
  String? get resolvedFormNumber {
    final candidates = <String?>[
      committedPatientId,
      patientTokenHint,
    ];
    for (final c in candidates) {
      if (c == null || c.trim().isEmpty) continue;
      final parsed = FormPageIdentity.parse(c, campCode: campCode);
      if (parsed.hasFormNumber) return parsed.formNumber;
    }
    final extracted = parsedExtractedResult;
    if (extracted != null) {
      final fromExtracted =
          FormPageIdentity.extractFormNumber(extracted, campCode: campCode);
      if (fromExtracted != null && fromExtracted.isNotEmpty) {
        return fromExtracted;
      }
    }
    final p1File = FormPageIdentity.parseFromFilePath(page1ImagePath);
    if (p1File.hasFormNumber) return p1File.formNumber;
    final p2File = FormPageIdentity.parseFromFilePath(page2ImagePath);
    if (p2File.hasFormNumber) return p2File.formNumber;
    return null;
  }

  String get pagePresenceBadge => hasPage1 && hasPage2
      ? 'P1+P2'
      : (hasPage1 ? 'P1 Only' : (hasPage2 ? 'P2 Only' : 'Empty'));

  OcrScanResultModel? get parsedExtractedResult {
    if (extractedJson == null || extractedJson!.isEmpty) return null;
    try {
      final decoded = jsonDecode(extractedJson!);
      if (decoded is Map<String, dynamic>) {
        return OcrScanResultModel.fromMap(decoded);
      }
    } catch (_) {}
    return null;
  }

  Uint8List? get page1Bytes {
    if (page1ImageBase64 == null || page1ImageBase64!.isEmpty) return null;
    try {
      return base64Decode(page1ImageBase64!);
    } catch (_) {
      return null;
    }
  }

  Uint8List? get page2Bytes {
    if (page2ImageBase64 == null || page2ImageBase64!.isEmpty) return null;
    try {
      return base64Decode(page2ImageBase64!);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'camp_id': campId,
      'camp_code': campCode,
      'page1_image_base64': page1ImageBase64,
      'page1_image_path': page1ImagePath,
      'page2_image_base64': page2ImageBase64,
      'page2_image_path': page2ImagePath,
      'patient_token_hint': patientTokenHint,
      'intake_date_hint': intakeDateHint,
      'examining_nurse_hint': examiningNurseHint,
      'examining_doctor_hint': examiningDoctorHint,
      'status': status,
      'review_status': reviewStatus,
      'error_message': errorMessage,
      'committed_patient_uuid': committedPatientUuid,
      'committed_patient_id': committedPatientId,
      'committed_patient_name': committedPatientName,
      'committed_visit_id': committedVisitId,
      'extracted_json': extractedJson,
      'created_by_user_id': createdByUserId,
      'created_by_user_name': createdByUserName,
      'created_by_user_role': createdByUserRole,
      'device_id': deviceId,
      'tenant_id': tenantId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory OfflineScanQueueItem.fromMap(Map<String, dynamic> map) {
    return OfflineScanQueueItem(
      id: map['id'] as String,
      campId: map['camp_id'] as String? ?? '',
      campCode: map['camp_code'] as String? ?? 'CAMP01',
      page1ImageBase64: map['page1_image_base64'] as String?,
      page1ImagePath: map['page1_image_path'] as String?,
      page2ImageBase64: map['page2_image_base64'] as String?,
      page2ImagePath: map['page2_image_path'] as String?,
      patientTokenHint: map['patient_token_hint'] as String?,
      intakeDateHint: map['intake_date_hint'] as String?,
      examiningNurseHint: map['examining_nurse_hint'] as String?,
      examiningDoctorHint: map['examining_doctor_hint'] as String?,
      status: map['status'] as String? ?? 'pending',
      reviewStatus: map['review_status'] as String? ??
          ((map['status'] as String?) == 'completed' ? 'needs_review' : 'pending'),
      errorMessage: map['error_message'] as String?,
      committedPatientUuid: map['committed_patient_uuid'] as String?,
      committedPatientId: map['committed_patient_id'] as String?,
      committedPatientName: map['committed_patient_name'] as String?,
      committedVisitId: map['committed_visit_id'] as String?,
      extractedJson: map['extracted_json'] as String?,
      createdByUserId: map['created_by_user_id'] as String? ?? 'usr-local',
      createdByUserName: map['created_by_user_name'] as String? ?? 'Field Staff',
      createdByUserRole: map['created_by_user_role'] as String? ?? 'DATA_TAKER',
      deviceId: map['device_id'] as String? ?? 'dev-local',
      tenantId: map['tenant_id'] as String? ?? 'tenant_default',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
