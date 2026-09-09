class OcrScanResultModel {
  final int pageNumber; // 1 = Front Page, 2 = Back Page, 0 = Full Intake
  final String? imagePath;
  final String? page1ImagePath;
  final String? page2ImagePath;
  final String? page1RawText;
  final String? page2RawText;
  final bool isDualPage;
  final bool isSimulated; // true = ML Kit unavailable, demo fallback text was used
  final Map<String, dynamic> demographics;
  final Map<String, dynamic> obstetrics;
  final Map<String, dynamic> vitals;
  final Map<String, dynamic> popStaging;
  final List<String> diagnoses;
  final List<String> medications;
  final String? surgicalReferral;
  final String? followUpDestination;
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
    required this.demographics,
    required this.obstetrics,
    required this.vitals,
    required this.popStaging,
    required this.diagnoses,
    required this.medications,
    this.surgicalReferral,
    this.followUpDestination,
    required this.fieldConfidences,
    required this.overallConfidence,
    required this.rawText,
    required this.scannedAt,
  });

  OcrScanResultModel copyWith({
    int? pageNumber,
    String? imagePath,
    String? page1ImagePath,
    String? page2ImagePath,
    String? page1RawText,
    String? page2RawText,
    bool? isDualPage,
    bool? isSimulated,
    Map<String, dynamic>? demographics,
    Map<String, dynamic>? obstetrics,
    Map<String, dynamic>? vitals,
    Map<String, dynamic>? popStaging,
    List<String>? diagnoses,
    List<String>? medications,
    String? surgicalReferral,
    String? followUpDestination,
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
      demographics: demographics ?? Map<String, dynamic>.from(this.demographics),
      obstetrics: obstetrics ?? Map<String, dynamic>.from(this.obstetrics),
      vitals: vitals ?? Map<String, dynamic>.from(this.vitals),
      popStaging: popStaging ?? Map<String, dynamic>.from(this.popStaging),
      diagnoses: diagnoses ?? List<String>.from(this.diagnoses),
      medications: medications ?? List<String>.from(this.medications),
      surgicalReferral: surgicalReferral ?? this.surgicalReferral,
      followUpDestination: followUpDestination ?? this.followUpDestination,
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

    return OcrScanResultModel(
      pageNumber: 0, // 0 = Full Combined Intake
      isDualPage: true,
      isSimulated: page1.isSimulated || page2.isSimulated,
      imagePath: page1.imagePath ?? page2.imagePath,
      page1ImagePath: page1.imagePath,
      page2ImagePath: page2.imagePath,
      page1RawText: page1.rawText,
      page2RawText: page2.rawText,
      demographics: Map<String, dynamic>.from(page1.demographics.isNotEmpty ? page1.demographics : page2.demographics),
      obstetrics: Map<String, dynamic>.from(page1.obstetrics.isNotEmpty ? page1.obstetrics : page2.obstetrics),
      vitals: Map<String, dynamic>.from(page2.vitals.isNotEmpty ? page2.vitals : page1.vitals),
      popStaging: Map<String, dynamic>.from(page2.popStaging.isNotEmpty ? page2.popStaging : page1.popStaging),
      diagnoses: List<String>.from(page2.diagnoses.isNotEmpty ? page2.diagnoses : page1.diagnoses),
      medications: List<String>.from(page2.medications.isNotEmpty ? page2.medications : page1.medications),
      surgicalReferral: page2.surgicalReferral ?? page1.surgicalReferral,
      followUpDestination: page2.followUpDestination ?? page1.followUpDestination,
      fieldConfidences: mergedConfidences,
      overallConfidence: double.parse(avgConf.toStringAsFixed(2)),
      rawText: combinedText,
      scannedAt: DateTime.now(),
    );
  }

  /// Helper to get confidence tier for a given field
  String getConfidenceTier(String fieldKey) {
    final conf = fieldConfidences[fieldKey] ?? 0.5;
    if (conf >= 0.85) return 'HIGH';
    if (conf >= 0.60) return 'MEDIUM';
    return 'LOW';
  }

  Map<String, dynamic> toMap() {
    return {
      'pageNumber': pageNumber,
      'isSimulated': isSimulated ? 1 : 0,
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
      'medications': medications,
      'surgicalReferral': surgicalReferral,
      'followUpDestination': followUpDestination,
      'fieldConfidences': fieldConfidences,
      'overallConfidence': overallConfidence,
      'rawText': rawText,
      'scannedAt': scannedAt.toIso8601String(),
    };
  }

  factory OcrScanResultModel.empty() {
    return OcrScanResultModel(
      pageNumber: 0,
      demographics: {},
      obstetrics: {},
      vitals: {},
      popStaging: {},
      diagnoses: [],
      medications: [],
      fieldConfidences: {},
      overallConfidence: 0.0,
      rawText: '',
      scannedAt: DateTime.now(),
    );
  }
}
