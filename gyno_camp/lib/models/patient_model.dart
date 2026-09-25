import 'dart:convert';
import '../core/constants/clinical_constants.dart';

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
  final String? relationshipType; // 'Father', 'Husband', 'Guardian', 'M/SM/GP'
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
  });

  String get fullName => '$firstName $surname'.trim();
  bool get isBelowAdultAge => age < ClinicalConstants.adultAgeThreshold;

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
    return 'GC-$campCode-$yr-$seqFormatted';
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
      intakeDate: DateTime.tryParse(map['intake_date'] as String? ?? '') ?? DateTime.now(),
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
    );
  }
}
