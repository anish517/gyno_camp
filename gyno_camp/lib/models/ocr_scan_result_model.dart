class OcrScanResultModel {
  final int pageNumber; // 1 = Front Page, 2 = Back Page, 0 = Full Intake
  final String? imagePath;
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
      'imagePath': imagePath,
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
