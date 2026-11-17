import 'dart:convert';
import '../core/utils/nepali_date_helper.dart';
import 'nurse_profile.dart';

class PatientModel {
  final String id; // UUID
  final String patientId; // Auto-generated human-readable ID: GC-[CampCode]-[Year]-[Seq]
  final String campId;
  final String campCode;
  final DateTime intakeDate;
  
  // Demographics (Yellow Form Page 1)
  final String firstName;
  final String surname;
  final int age;
  final String? spouseOrFatherName; // Father if age < 20, Husband if age >= 20
  final String? relationshipType; // 'Father', 'Husband', 'Mother', 'Guardian', 'Other'
  final String mobile;
  final String province;
  final String district;
  final String municipality;
  final String ward;
  final String? contactPerson;
  final String? contactMobile;
  final String maritalStatus; // 'married', 'widow', 'unmarried', 'divorced'
  final int? maritalAge;

  // Primary reasons for visit (multi-select checkboxes from Yellow Form)
  final List<String> reasonsForVisit;
  
  // Consents
  final bool consentTreatment;
  final bool consentStoreMedicalInfo;

  // Metadata & Sync State
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String createdByUserId;
  final String createdByDeviceId;
  final String tenantId;
  final bool isSynced;
  final DateTime? syncedAt;

  /// Transient fields — populated by repository JOIN, not stored in DB.
  final bool hasClinicalVisit;
  final bool isFollowUp;
  final int? highestPopStage;
  final List<String> diagnoses;
  final bool? surgeryDone;
  final String? surgeryType;
  final String? primaryDoctorName;
  final List<String> attendingDoctorNames;
  final String? primaryNurseName;
  final List<String> attendingNurseNames;
  final List<String> medications;
  final String? customMedication;
  final List<String> counseling;
  final String? pessaryType;
  final String? pessarySize;
  final String? surgicalReferral;
  final String? treatmentLevel;
  final List<String> clinicalComplaints;

  const PatientModel({
    required this.id,
    required this.patientId,
    required this.campId,
    required this.campCode,
    required this.intakeDate,
    required this.firstName,
    required this.surname,
    required this.age,
    this.spouseOrFatherName,
    this.relationshipType,
    required this.mobile,
    this.province = 'Bagmati',
    this.district = '',
    this.municipality = '',
    required this.ward,
    this.contactPerson,
    this.contactMobile,
    this.maritalStatus = 'married',
    this.maritalAge,
    this.reasonsForVisit = const [],
    this.consentTreatment = true,
    this.consentStoreMedicalInfo = true,
    required this.createdAt,
    this.updatedAt,
    required this.createdByUserId,
    required this.createdByDeviceId,
    this.tenantId = 'tenant_default',
    this.isSynced = false,
    this.syncedAt,
    this.hasClinicalVisit = false,
    this.isFollowUp = false,
    this.highestPopStage,
    this.diagnoses = const [],
    this.surgeryDone,
    this.surgeryType,
    this.primaryDoctorName,
    this.attendingDoctorNames = const [],
    this.primaryNurseName,
    this.attendingNurseNames = const [],
    this.medications = const [],
    this.customMedication,
    this.counseling = const [],
    this.pessaryType,
    this.pessarySize,
    this.surgicalReferral,
    this.treatmentLevel,
    this.clinicalComplaints = const [],
  });

  /// Normalizes consultation / treatment level to canonical keys ('counseling' or 'gyno_checkup')
  static String? normalizeTreatmentLevel(String? raw) {
    if (raw == null) return null;
    final clean = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');
    if (clean.isEmpty || clean == 'none' || clean == 'unassigned' || clean == 'null') return null;
    if (clean.contains('counsel') || clean.contains('council') || clean.contains('काउन्सिलिङ')) {
      return 'counseling';
    }
    if (clean.contains('gyno') || clean.contains('full') || clean.contains('checkup') || clean.contains('गाइनो') || clean.contains('पूर्ण')) {
      return 'gyno_checkup';
    }
    return clean;
  }

  String get fullName => '$firstName $surname'.trim();
  bool get isCounseling {
    final norm = normalizeTreatmentLevel(treatmentLevel);
    return norm == 'counseling' || norm == 'council_level';
  }
  bool get isGynocheckup {
    final norm = normalizeTreatmentLevel(treatmentLevel);
    return norm == 'gyno_checkup' || norm == 'full_check_up';
  }
  bool get isCouncilLevel => isCounseling;
  bool get isFullCheckUp => isGynocheckup;
  bool get isUnassigned => !isCounseling && !isGynocheckup;
  String get consultationLabel => isCounseling ? 'Counseling' : (isGynocheckup ? 'Gynocheckup' : 'Unassigned');
  String get treatmentLabel => consultationLabel;

  /// Aggregated list of treatments, medications, pessary fittings, and counseling
  List<String> get treatments {
    final list = <String>[];
    if (medications.isNotEmpty) list.addAll(medications);
    if (customMedication != null && customMedication!.trim().isNotEmpty) {
      list.add(customMedication!.trim());
    }
    if (pessarySize != null && pessarySize!.trim().isNotEmpty) {
      list.add('Pessary: ${pessaryType ?? "Ring"} $pessarySize');
    } else if (pessaryType != null && pessaryType!.trim().isNotEmpty) {
      list.add('Pessary: $pessaryType');
    }
    if (counseling.isNotEmpty) list.addAll(counseling);
    if (surgicalReferral != null && surgicalReferral!.trim().isNotEmpty) {
      list.add('Referral: $surgicalReferral');
    }
    return list;
  }

  /// Checks duplicate criteria according to specifications:
  /// Match mobile OR (match full name + age +/- 1 + ward + father/husband)
  bool matchesDuplicateCriteria({
    required String testMobile,
    required String testFirstName,
    required String testSurname,
    required int testAge,
    required String testWard,
    String? testSpouseOrFather,
  }) {
    // Exact phone match (if provided)
    if (mobile.isNotEmpty && testMobile.isNotEmpty && mobile == testMobile) {
      return true;
    }

    // Name + Ward + Age match
    final nameMatches = (firstName.toLowerCase() == testFirstName.toLowerCase()) &&
        (surname.toLowerCase() == testSurname.toLowerCase());
    final ageNear = (age - testAge).abs() <= 1;
    final wardMatches = ward.trim() == testWard.trim();

    if (nameMatches && wardMatches && ageNear) {
      if (spouseOrFatherName != null && testSpouseOrFather != null) {
        if (spouseOrFatherName!.toLowerCase().trim() == testSpouseOrFather.toLowerCase().trim()) {
          return true;
        }
      } else {
        return true;
      }
    }

    return false;
  }

  PatientModel copyWith({
    String? id,
    String? patientId,
    String? campId,
    String? campCode,
    DateTime? intakeDate,
    String? firstName,
    String? surname,
    int? age,
    String? spouseOrFatherName,
    String? relationshipType,
    String? mobile,
    String? province,
    String? district,
    String? municipality,
    String? ward,
    String? contactPerson,
    String? contactMobile,
    String? maritalStatus,
    int? maritalAge,
    List<String>? reasonsForVisit,
    bool? consentTreatment,
    bool? consentStoreMedicalInfo,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdByUserId,
    String? createdByDeviceId,
    String? tenantId,
    bool? isSynced,
    DateTime? syncedAt,
    bool? hasClinicalVisit,
    bool? isFollowUp,
    int? highestPopStage,
    List<String>? diagnoses,
    bool? surgeryDone,
    String? surgeryType,
    String? primaryDoctorName,
    List<String>? attendingDoctorNames,
    String? primaryNurseName,
    List<String>? attendingNurseNames,
    List<String>? medications,
    String? customMedication,
    List<String>? counseling,
    String? pessaryType,
    String? pessarySize,
    String? surgicalReferral,
    String? treatmentLevel,
    List<String>? clinicalComplaints,
    bool clearTreatmentLevel = false,
  }) {
    return PatientModel(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      campId: campId ?? this.campId,
      campCode: campCode ?? this.campCode,
      intakeDate: intakeDate ?? this.intakeDate,
      firstName: firstName ?? this.firstName,
      surname: surname ?? this.surname,
      age: age ?? this.age,
      spouseOrFatherName: spouseOrFatherName ?? this.spouseOrFatherName,
      relationshipType: relationshipType ?? this.relationshipType,
      mobile: mobile ?? this.mobile,
      province: province ?? this.province,
      district: district ?? this.district,
      municipality: municipality ?? this.municipality,
      ward: ward ?? this.ward,
      contactPerson: contactPerson ?? this.contactPerson,
      contactMobile: contactMobile ?? this.contactMobile,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      maritalAge: maritalAge ?? this.maritalAge,
      reasonsForVisit: reasonsForVisit ?? this.reasonsForVisit,
      consentTreatment: consentTreatment ?? this.consentTreatment,
      consentStoreMedicalInfo: consentStoreMedicalInfo ?? this.consentStoreMedicalInfo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      createdByDeviceId: createdByDeviceId ?? this.createdByDeviceId,
      tenantId: tenantId ?? this.tenantId,
      isSynced: isSynced ?? this.isSynced,
      syncedAt: syncedAt ?? this.syncedAt,
      hasClinicalVisit: hasClinicalVisit ?? this.hasClinicalVisit,
      isFollowUp: isFollowUp ?? this.isFollowUp,
      highestPopStage: highestPopStage ?? this.highestPopStage,
      diagnoses: diagnoses ?? this.diagnoses,
      surgeryDone: surgeryDone ?? this.surgeryDone,
      surgeryType: surgeryType ?? this.surgeryType,
      primaryDoctorName: primaryDoctorName ?? this.primaryDoctorName,
      attendingDoctorNames: attendingDoctorNames ?? this.attendingDoctorNames,
      primaryNurseName: primaryNurseName ?? this.primaryNurseName,
      attendingNurseNames: attendingNurseNames ?? this.attendingNurseNames,
      medications: medications ?? this.medications,
      customMedication: customMedication ?? this.customMedication,
      counseling: counseling ?? this.counseling,
      pessaryType: pessaryType ?? this.pessaryType,
      pessarySize: pessarySize ?? this.pessarySize,
      surgicalReferral: surgicalReferral ?? this.surgicalReferral,
      treatmentLevel: clearTreatmentLevel ? null : (normalizeTreatmentLevel(treatmentLevel) ?? normalizeTreatmentLevel(this.treatmentLevel)),
      clinicalComplaints: clinicalComplaints ?? this.clinicalComplaints,
    );
  }

  /// Generates the standard human-readable Patient ID
  static String generatePatientId({
    required String campCode,
    required int sequenceNumber,
    int? year,
  }) {
    final yr = year ?? DateTime.now().year;
    final seqFormatted = sequenceNumber.toString().padLeft(5, '0');
    final code = campCode.trim().isEmpty ? 'CAMP' : campCode.trim().toUpperCase();
    return 'GC-$code-$yr-$seqFormatted';
  }

  /// Checks if a string conforms to a valid Patient ID format: GC-[CAMP]-[YEAR]-[5 DIGITS] or non-empty GC-* token
  static bool isValidPatientIdFormat(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return false;
    return RegExp(r'^GC-[A-Za-z0-9_-]+-\d{4}-\d{5}$', caseSensitive: false).hasMatch(trimmed) ||
        RegExp(r'^GC-[A-Za-z0-9_-]{2,}$', caseSensitive: false).hasMatch(trimmed);
  }

  /// Normalizes Devanagari digits (०-९) to ASCII digits (0-9)
  static String _devanagariToAscii(String input) {
    const dev = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];
    var out = input;
    for (int i = 0; i < dev.length; i++) {
      out = out.replaceAll(dev[i], i.toString());
    }
    return out;
  }

  /// Normalizes raw input from OCR or manual entry into standard format.
  /// - Returns '' if input is blank (signaling automatic sequential generation).
  /// - Converts numeric sequence (e.g., '42' or '00042') into 'GC-[campCode]-[year]-00042'.
  /// - Normalizes 2-part strings like 'KTM01-0001' into 'GC-KTM01-[year]-00001'.
  /// - Normalizes standard strings like 'gc-dhn-2026-42' into 'GC-DHN-2026-00042'.
  static String normalizePatientId({
    required String rawInput,
    required String campCode,
    int? year,
  }) {
    var clean = _devanagariToAscii(rawInput).trim();
    if (clean.isEmpty || clean.toLowerCase() == 'null' || clean == '—' || clean == '-') return '';

    // Strip common OCR label prefixes like "Token No:", "Patient ID:", "Reg #", etc.
    clean = clean.replaceFirst(
      RegExp(r'^(patient\s*token\s*id|patient\s*id|token\s*no\.?|token\s*id|reg\.?\s*no\.?|id|no\.?|#)\s*[:#\-]?\s*', caseSensitive: false),
      '',
    ).trim();
    if (clean.isEmpty) return '';

    // Normalize slashes and spaces around separators into hyphens
    var upper = clean.toUpperCase().replaceAll(RegExp(r'[\s/\\]+'), '-').replaceAll(RegExp(r'-+'), '-');
    upper = upper.replaceAll(RegExp(r'^-+|-+$'), '');
    if (upper.isEmpty) return '';

    final effectiveYear = year ?? DateTime.now().year;
    final cleanCampCode = campCode.trim().isEmpty ? 'CAMP' : campCode.trim().toUpperCase();

    // 1. If input is pure digits (e.g., '42', '00042')
    final digitsOnly = upper.replaceAll(RegExp(r'[^0-9]'), '');
    if (upper == digitsOnly && digitsOnly.isNotEmpty && digitsOnly.length <= 6) {
      final seq = int.tryParse(digitsOnly);
      if (seq != null) {
        return generatePatientId(
          campCode: cleanCampCode,
          sequenceNumber: seq,
          year: effectiveYear,
        );
      }
    }

    // 1b. If input is 'GC-42' (prefix + pure digits)
    final gcDigitsMatch = RegExp(r'^GC-(\d{1,6})$').firstMatch(upper);
    if (gcDigitsMatch != null) {
      final seq = int.tryParse(gcDigitsMatch.group(1)!) ?? 1;
      return generatePatientId(
        campCode: cleanCampCode,
        sequenceNumber: seq,
        year: effectiveYear,
      );
    }

    // 2. If missing the 'GC-' prefix, prepend 'GC-'
    final withPrefix = upper.startsWith('GC-') ? upper : 'GC-$upper';

    // 3. Match 'GC-[CODE]-[YEAR]-[SEQ]' (4-digit or 2-digit year)
    final match3 = RegExp(r'^GC-([A-Za-z0-9_]+)-(\d{2,4})-(\d{1,6})$').firstMatch(withPrefix);
    if (match3 != null) {
      final code = match3.group(1)!;
      var yr = int.tryParse(match3.group(2)!) ?? effectiveYear;
      if (yr < 100) {
        yr = yr >= 70 ? (2000 + yr) : (2000 + yr);
      }
      final seqNum = int.tryParse(match3.group(3)!) ?? 1;
      return generatePatientId(
        campCode: code,
        sequenceNumber: seqNum,
        year: yr,
      );
    }

    // 4. Match 2-part 'GC-[YEAR]-[SEQ]' (e.g., '2083-0015' or '2026-001')
    final matchYearSeq = RegExp(r'^GC-(20\d{2})-(\d{1,6})$').firstMatch(withPrefix);
    if (matchYearSeq != null) {
      final yr = int.tryParse(matchYearSeq.group(1)!) ?? effectiveYear;
      final seqNum = int.tryParse(matchYearSeq.group(2)!) ?? 1;
      return generatePatientId(
        campCode: cleanCampCode,
        sequenceNumber: seqNum,
        year: yr,
      );
    }

    // 5. Match 2-part 'GC-[SEQ]-[YEAR]' (e.g., '015-2083')
    final matchSeqYear = RegExp(r'^GC-(\d{1,6})-(20\d{2})$').firstMatch(withPrefix);
    if (matchSeqYear != null) {
      final seqNum = int.tryParse(matchSeqYear.group(1)!) ?? 1;
      final yr = int.tryParse(matchSeqYear.group(2)!) ?? effectiveYear;
      return generatePatientId(
        campCode: cleanCampCode,
        sequenceNumber: seqNum,
        year: yr,
      );
    }

    // 6. Match 2-part 'GC-[CAMP_CODE]-[SEQ]' (e.g., 'KTM01-0001' or 'GC-KTM01-17')
    final matchCodeSeq = RegExp(r'^GC-([A-Za-z0-9_]+)-(\d{1,6})$').firstMatch(withPrefix);
    if (matchCodeSeq != null) {
      final code = matchCodeSeq.group(1)!;
      final seqNum = int.tryParse(matchCodeSeq.group(2)!) ?? 1;
      return generatePatientId(
        campCode: code,
        sequenceNumber: seqNum,
        year: effectiveYear,
      );
    }

    return withPrefix;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patient_id': patientId,
      'camp_id': campId,
      'camp_code': campCode,
      'intake_date': intakeDate.toIso8601String(),
      'first_name': firstName,
      'surname': surname,
      'age': age,
      'spouse_or_father_name': spouseOrFatherName,
      'relationship_type': relationshipType,
      'mobile': mobile,
      'province': province,
      'district': district,
      'municipality': municipality,
      'ward': ward,
      'contact_person': contactPerson,
      'contact_mobile': contactMobile,
      'marital_status': maritalStatus,
      'marital_age': maritalAge,
      'reasons_for_visit': reasonsForVisit.join(','),
      'consent_treatment': consentTreatment ? 1 : 0,
      'consent_store_medical_info': consentStoreMedicalInfo ? 1 : 0,
      'treatment_level': normalizeTreatmentLevel(treatmentLevel),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'created_by_user_id': createdByUserId,
      'created_by_device_id': createdByDeviceId,
      'tenant_id': tenantId,
      'is_synced': isSynced ? 1 : 0,
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  factory PatientModel.fromMap(Map<String, dynamic> map) {
    return PatientModel(
      id: map['id'] as String,
      patientId: map['patient_id'] as String,
      campId: map['camp_id'] as String,
      campCode: map['camp_code'] as String? ?? '',
      intakeDate: NepaliDateHelper.parseStoredCalendarDate(map['intake_date']) ?? DateTime.now(),
      firstName: map['first_name'] as String,
      surname: map['surname'] as String,
      age: map['age'] as int,
      spouseOrFatherName: map['spouse_or_father_name'] as String?,
      relationshipType: map['relationship_type'] as String?,
      mobile: map['mobile'] as String? ?? '',
      province: map['province'] as String? ?? 'Bagmati',
      district: map['district'] as String? ?? '',
      municipality: map['municipality'] as String? ?? '',
      ward: map['ward'] as String? ?? '',
      contactPerson: map['contact_person'] as String?,
      contactMobile: map['contact_mobile'] as String?,
      maritalStatus: map['marital_status'] as String? ?? 'married',
      maritalAge: map['marital_age'] as int?,
      reasonsForVisit: map['reasons_for_visit'] != null && (map['reasons_for_visit'] as String).isNotEmpty
          ? (map['reasons_for_visit'] as String).split(',')
          : [],
      consentTreatment: (map['consent_treatment'] is int)
          ? (map['consent_treatment'] as int) == 1
          : (map['consent_treatment'] as bool? ?? true),
      consentStoreMedicalInfo: (map['consent_store_medical_info'] is int)
          ? (map['consent_store_medical_info'] as int) == 1
          : (map['consent_store_medical_info'] as bool? ?? true),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'] as String) : null,
      createdByUserId: map['created_by_user_id'] as String? ?? '',
      createdByDeviceId: map['created_by_device_id'] as String? ?? '',
      tenantId: map['tenant_id'] as String? ?? 'tenant_default',
      isSynced: (map['is_synced'] is int)
          ? (map['is_synced'] as int) == 1
          : (map['is_synced'] as bool? ?? false),
      syncedAt: map['synced_at'] != null ? DateTime.tryParse(map['synced_at'] as String) : null,
      // Transient JOIN columns — present when loaded via getPatientsByCamp
      hasClinicalVisit: (map['has_clinical_visit'] as int? ?? 0) == 1,
      isFollowUp: (map['is_follow_up'] as int? ?? 0) == 1 || map['is_follow_up'] == true,
      highestPopStage: map['highest_pop_stage'] as int?,
      diagnoses: map['diagnoses'] != null
          ? (map['diagnoses'] is String
              ? (() {
                  try {
                    final decoded = jsonDecode(map['diagnoses'] as String);
                    if (decoded is List) return decoded.map((e) => e.toString()).toList();
                  } catch (_) {}
                  return (map['diagnoses'] as String).split(',').where((s) => s.isNotEmpty).toList();
                })()
              : (map['diagnoses'] as List).map((e) => e.toString()).toList())
          : const [],
      surgeryDone: map['surgery_done'] != null ? (map['surgery_done'] == 1 || map['surgery_done'] == true) : null,
      surgeryType: map['surgery_type'] as String?,
      primaryDoctorName: map['primary_doctor_name'] as String?,
      attendingDoctorNames: map['attending_doctor_names'] != null && (map['attending_doctor_names'] as String).isNotEmpty
          ? (map['attending_doctor_names'] as String).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
          : (map['primary_doctor_name'] != null && (map['primary_doctor_name'] as String).isNotEmpty ? [(map['primary_doctor_name'] as String).trim()] : const []),
      primaryNurseName: map['primary_nurse_name'] as String?,
      attendingNurseNames: map['attending_nurse_names'] != null && (map['attending_nurse_names'] as String).isNotEmpty
          ? NurseProfile.splitList(map['attending_nurse_names'] as String).map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
          : (map['primary_nurse_name'] != null && (map['primary_nurse_name'] as String).isNotEmpty ? [(map['primary_nurse_name'] as String).trim()] : const []),
      medications: map['medications'] != null
          ? (map['medications'] is String
              ? (() {
                  try {
                    final decoded = jsonDecode(map['medications'] as String);
                    if (decoded is List) return decoded.map((e) => e.toString()).toList();
                  } catch (_) {}
                  return (map['medications'] as String).split(',').where((s) => s.isNotEmpty).toList();
                })()
              : (map['medications'] as List).map((e) => e.toString()).toList())
          : const [],
      customMedication: map['custom_medication'] as String?,
      counseling: map['counseling'] != null
          ? (map['counseling'] is String
              ? (() {
                  try {
                    final decoded = jsonDecode(map['counseling'] as String);
                    if (decoded is List) return decoded.map((e) => e.toString()).toList();
                  } catch (_) {}
                  return (map['counseling'] as String).split(',').where((s) => s.isNotEmpty).toList();
                })()
              : (map['counseling'] as List).map((e) => e.toString()).toList())
          : const [],
      pessaryType: map['pessary_type'] as String?,
      pessarySize: map['pessary_size'] as String?,
      surgicalReferral: map['surgical_referral'] as String?,
      treatmentLevel: normalizeTreatmentLevel(map['treatment_level'] as String?),
      clinicalComplaints: (map['anamnesis_json'] ?? map['anamnesis_complaints']) != null
          ? (() {
              final raw = map['anamnesis_json'] ?? map['anamnesis_complaints'];
              if (raw is String && raw.trim().isNotEmpty) {
                try {
                  final decoded = jsonDecode(raw);
                  if (decoded is Map) {
                    final out = <String>{};
                    if (decoded['clinicalComplaints'] is List) {
                      out.addAll((decoded['clinicalComplaints'] as List).map((e) => e.toString().trim()).where((s) => s.isNotEmpty));
                    }
                    if (decoded['reasons'] is List) {
                      out.addAll((decoded['reasons'] as List).map((e) => e.toString().trim()).where((s) => s.isNotEmpty));
                    }
                    return out.toList();
                  }
                  if (decoded is List) {
                    return decoded.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
                  }
                } catch (_) {}
                return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
              }
              return const <String>[];
            })()
          : const [],
    );
  }
}
