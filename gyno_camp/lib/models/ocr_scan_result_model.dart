import 'patient_model.dart';

class OcrScanResultModel {
  final int pageNumber; // 1 = Front Page, 2 = Back Page, 0 = Full Intake
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

  OcrScanResultModel copyWith({
    int? pageNumber,
    String? imagePath,
    String? page1ImagePath,
    String? page2ImagePath,
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
      imagePath: imagePath ?? this.imagePath,
      page1ImagePath: page1ImagePath ?? this.page1ImagePath,
      page2ImagePath: page2ImagePath ?? this.page2ImagePath,
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

    String? harmonizedIntake = page1.intakeDate ?? page2.intakeDate;
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
          if (p1Parts[0] == p2Parts[0] && p1Parts[2] == p2Parts[2]) {
            harmonizedIntake = dominantP2Date;
          }
        }
      }
    }

    final effectiveCampDate = harmonizedIntake ?? (p2Dates.isNotEmpty ? p2Dates.first : null);

    final mergedDemographics = Map<String, dynamic>.from(page1.demographics.isNotEmpty ? page1.demographics : page2.demographics);
    if (harmonizedIntake != null) {
      mergedDemographics['intakeDate'] = harmonizedIntake;
      mergedDemographics['date'] = harmonizedIntake;
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
      examDate: page2.examDate ?? page1.examDate ?? effectiveCampDate,
      treatmentDate: page2.treatmentDate ?? page1.treatmentDate ?? effectiveCampDate,
      conclusionDate: page2.conclusionDate ?? page1.conclusionDate ?? effectiveCampDate,
      labTestDate: page2.labTestDate ?? page1.labTestDate ?? effectiveCampDate,
      outtakeDate: page2.outtakeDate ?? page1.outtakeDate ?? effectiveCampDate,
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
