import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/duplicate_detection_service.dart';
import '../models/patient_model.dart';
import '../repositories/patient_repository.dart';

class PatientRegistrationState {
  final String firstName;
  final String surname;
  final int? age;
  final String mobile;
  final String province;
  final String district;
  final String municipality;
  final String ward;
  final String spouseOrFatherName;
  final String relationshipType;
  final String? contactPerson;
  final String? contactMobile;
  final String maritalStatus;
  final int? maritalAge;
  final List<String> selectedReasons;
  final bool consentTreatment;
  final bool consentStoreMedicalInfo;

  final DuplicateCheckResult duplicateResult;
  final bool isSubmitting;
  final String? errorMessage;
  final PatientModel? registeredPatient;

  const PatientRegistrationState({
    this.firstName = '',
    this.surname = '',
    this.age,
    this.mobile = '',
    this.province = 'Bagmati',
    this.district = '',
    this.municipality = '',
    this.ward = '',
    this.spouseOrFatherName = '',
    this.relationshipType = 'Husband',
    this.contactPerson,
    this.contactMobile,
    this.maritalStatus = 'married',
    this.maritalAge,
    this.selectedReasons = const [],
    this.consentTreatment = true,
    this.consentStoreMedicalInfo = true,
    this.duplicateResult = const DuplicateCheckResult.none(),
    this.isSubmitting = false,
    this.errorMessage,
    this.registeredPatient,
  });


  String? get validationError {
    if (firstName.trim().isEmpty) return 'First name is required (पहिलो नाम अनिवार्य छ).';
    if (firstName.trim().length < 2) return 'First name must be at least 2 characters.';
    if (surname.trim().isEmpty) return 'Surname is required (थर अनिवार्य छ).';
    if (surname.trim().length < 2) return 'Surname must be at least 2 characters.';
    if (age == null) return 'Age is required (उमेर अनिवार्य छ).';
    if (age! <= 0 || age! > 120) return 'Please enter a valid age between 1 and 120.';
    if (ward.trim().isEmpty) return 'Ward is required (वडा नं अनिवार्य छ).';
    if (mobile.trim().isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(mobile.trim())) {
      return 'Mobile number must be exactly 10 digits (e.g. 9841234567).';
    }
    if (contactMobile != null && contactMobile!.trim().isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(contactMobile!.trim())) {
      return 'Emergency contact mobile must be exactly 10 digits.';
    }
    if (spouseOrFatherName.trim().isNotEmpty && spouseOrFatherName.trim().length < 2) {
      return 'Guardian/Spouse name must be at least 2 characters.';
    }
    if (!consentTreatment || !consentStoreMedicalInfo) {
      return 'Patient consent is required to proceed with registration (उपचारको सहमति अनिवार्य छ).';
    }
    return null;
  }

  bool get isValid => validationError == null;

  PatientRegistrationState copyWith({
    String? firstName,
    String? surname,
    int? age,
    bool clearAge = false,
    String? mobile,
    String? province,
    String? district,
    String? municipality,
    String? ward,
    String? spouseOrFatherName,
    String? relationshipType,
    String? contactPerson,
    String? contactMobile,
    String? maritalStatus,
    int? maritalAge,
    bool clearMaritalAge = false,
    List<String>? selectedReasons,
    bool? consentTreatment,
    bool? consentStoreMedicalInfo,
    DuplicateCheckResult? duplicateResult,
    bool? isSubmitting,
    String? errorMessage,
    PatientModel? registeredPatient,
    bool clearRegistered = false,
  }) {
    return PatientRegistrationState(
      firstName: firstName ?? this.firstName,
      surname: surname ?? this.surname,
      age: clearAge ? null : (age ?? this.age),
      mobile: mobile ?? this.mobile,
      province: province ?? this.province,
      district: district ?? this.district,
      municipality: municipality ?? this.municipality,
      ward: ward ?? this.ward,
      spouseOrFatherName: spouseOrFatherName ?? this.spouseOrFatherName,
      relationshipType: relationshipType ?? this.relationshipType,
      contactPerson: contactPerson ?? this.contactPerson,
      contactMobile: contactMobile ?? this.contactMobile,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      maritalAge: clearMaritalAge ? null : (maritalAge ?? this.maritalAge),
      selectedReasons: selectedReasons ?? this.selectedReasons,
      consentTreatment: consentTreatment ?? this.consentTreatment,
      consentStoreMedicalInfo: consentStoreMedicalInfo ?? this.consentStoreMedicalInfo,
      duplicateResult: duplicateResult ?? this.duplicateResult,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
      registeredPatient: clearRegistered ? null : (registeredPatient ?? this.registeredPatient),
    );
  }
}

class PatientRegistrationViewModel extends StateNotifier<PatientRegistrationState> {
  final IPatientRepository _patientRepository;

  PatientRegistrationViewModel(this._patientRepository)
      : super(const PatientRegistrationState());

  void updateField({
    String? firstName,
    String? surname,
    int? age,
    bool clearAge = false,
    String? mobile,
    String? province,
    String? district,
    String? municipality,
    String? ward,
    String? spouseOrFatherName,
    String? relationshipType,
    String? contactPerson,
    String? contactMobile,
    String? maritalStatus,
    int? maritalAge,
    bool clearMaritalAge = false,
    bool? consentTreatment,
    bool? consentStoreMedicalInfo,
  }) {
    String? resolvedRelation = relationshipType ?? state.relationshipType;
    if (maritalStatus != null && maritalStatus != state.maritalStatus) {
      if (maritalStatus == 'unmarried') {
        resolvedRelation = 'Father';
      } else if (maritalStatus == 'married' && state.relationshipType != 'Husband') {
        resolvedRelation = 'Husband';
      }
    }

    final shouldClearAge = clearMaritalAge || (maritalStatus == 'unmarried');

    state = state.copyWith(
      firstName: firstName,
      surname: surname,
      age: clearAge ? null : (age ?? state.age),
      clearAge: clearAge,
      mobile: mobile,
      province: province,
      district: district,
      municipality: municipality,
      ward: ward,
      spouseOrFatherName: spouseOrFatherName,
      relationshipType: resolvedRelation,
      contactPerson: contactPerson,
      contactMobile: contactMobile,
      maritalStatus: maritalStatus,
      maritalAge: shouldClearAge ? null : (maritalAge ?? state.maritalAge),
      clearMaritalAge: shouldClearAge,
      consentTreatment: consentTreatment,
      consentStoreMedicalInfo: consentStoreMedicalInfo,
    );
  }

  void toggleReason(String reason) {
    final list = List<String>.from(state.selectedReasons);
    if (list.contains(reason)) {
      list.remove(reason);
    } else {
      list.add(reason);
    }
    state = state.copyWith(selectedReasons: list);
  }

  Future<void> runLiveDuplicateCheck(String campId) async {
    if (state.firstName.trim().isEmpty || state.surname.trim().isEmpty || state.age == null) {
      state = state.copyWith(duplicateResult: const DuplicateCheckResult.none());
      return;
    }

    try {
      final result = await _patientRepository.checkDuplicate(
        campId: campId,
        firstName: state.firstName,
        surname: state.surname,
        age: state.age!,
        mobile: state.mobile,
        ward: state.ward,
        spouseOrFatherName: state.spouseOrFatherName,
        maritalStatus: state.maritalStatus,
      );

      if (!mounted) return;
      state = state.copyWith(duplicateResult: result);
    } catch (_) {}
  }

  Future<PatientModel?> submitRegistration({
    required String campId,
    required String campCode,
    required String staffUserId,
    required String staffUserName,
    required String staffUserRole,
    required String deviceId,
    String tenantId = 'default_tenant',
  }) async {
    if (!state.isValid) {
      state = state.copyWith(errorMessage: state.validationError ?? 'Please fill in required fields properly.');
      return null;
    }

    state = state.copyWith(isSubmitting: true, errorMessage: null);

    try {
      final patient = PatientModel(
        id: '', // Generated by repo
        patientId: '', // Auto formatted ID by repo
        campId: campId,
        campCode: campCode,
        tenantId: tenantId,
        intakeDate: DateTime.now(),
        firstName: state.firstName.trim(),
        surname: state.surname.trim(),
        age: state.age!,
        spouseOrFatherName: state.spouseOrFatherName.trim(),
        relationshipType: state.relationshipType,
        mobile: state.mobile.trim(),
        province: state.province.trim(),
        district: state.district.trim(),
        municipality: state.municipality.trim(),
        ward: state.ward.trim(),
        contactPerson: state.contactPerson?.trim(),
        contactMobile: state.contactMobile?.trim(),
        maritalStatus: state.maritalStatus,
        maritalAge: state.maritalAge,
        reasonsForVisit: state.selectedReasons,
        consentTreatment: state.consentTreatment,
        consentStoreMedicalInfo: state.consentStoreMedicalInfo,
        createdAt: DateTime.now(),
        createdByUserId: staffUserId,
        createdByDeviceId: deviceId,
      );

      final registered = await _patientRepository.registerPatient(
        patient,
        createdByUserId: staffUserId,
        createdByUserName: staffUserName,
        createdByUserRole: staffUserRole,
        deviceId: deviceId,
      );

      if (!mounted) return registered;
      state = PatientRegistrationState(
        province: state.province,
        district: state.district,
        municipality: state.municipality,
        ward: state.ward,
        isSubmitting: false,
        registeredPatient: registered,
      );

      return registered;
    } catch (e) {
      if (!mounted) return null;
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Registration failed: $e',
      );
      return null;
    }
  }

  void loadPatientForEditing(PatientModel patient) {
    state = PatientRegistrationState(
      firstName: patient.firstName,
      surname: patient.surname,
      age: patient.age,
      mobile: patient.mobile,
      province: patient.province.isNotEmpty ? patient.province : 'Bagmati',
      district: patient.district,
      municipality: patient.municipality,
      ward: patient.ward,
      spouseOrFatherName: patient.spouseOrFatherName ?? '',
      relationshipType: patient.relationshipType ?? (patient.age < 20 ? 'Father' : 'Husband'),
      contactPerson: patient.contactPerson,
      contactMobile: patient.contactMobile,
      maritalStatus: patient.maritalStatus,
      maritalAge: patient.maritalAge,
      selectedReasons: List<String>.from(patient.reasonsForVisit),
      consentTreatment: patient.consentTreatment,
      consentStoreMedicalInfo: patient.consentStoreMedicalInfo,
      registeredPatient: patient,
    );
  }

  Future<PatientModel?> submitUpdate({
    required PatientModel originalPatient,
    required String staffUserId,
    required String staffUserName,
    required String staffUserRole,
    required String deviceId,
  }) async {
    if (!state.isValid) {
      state = state.copyWith(errorMessage: state.validationError ?? 'Please fill in required fields properly.');
      return null;
    }

    state = state.copyWith(isSubmitting: true, errorMessage: null);

    try {
      final updatedPatient = originalPatient.copyWith(
        firstName: state.firstName.trim().toUpperCase(),
        surname: state.surname.trim().toUpperCase(),
        age: state.age,
        spouseOrFatherName: state.spouseOrFatherName.trim().toUpperCase(),
        relationshipType: state.relationshipType,
        mobile: state.mobile.trim(),
        province: state.province.trim(),
        district: state.district.trim(),
        municipality: state.municipality.trim(),
        ward: state.ward.trim(),
        contactPerson: state.contactPerson?.trim().toUpperCase(),
        contactMobile: state.contactMobile?.trim(),
        maritalStatus: state.maritalStatus,
        maritalAge: state.maritalAge,
        reasonsForVisit: state.selectedReasons,
        consentTreatment: state.consentTreatment,
        consentStoreMedicalInfo: state.consentStoreMedicalInfo,
        updatedAt: DateTime.now(),
      );

      final result = await _patientRepository.updatePatient(
        updatedPatient,
        updatedByUserId: staffUserId,
        updatedByUserName: staffUserName,
        updatedByUserRole: staffUserRole,
        deviceId: deviceId,
      );

      if (!mounted) return result;
      state = state.copyWith(
        isSubmitting: false,
        registeredPatient: result,
      );

      return result;
    } catch (e) {
      if (!mounted) return null;
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Update failed: $e',
      );
      return null;
    }
  }

  void reset({String province = 'Bagmati', String district = '', String municipality = '', String ward = ''}) {
    state = PatientRegistrationState(
      province: province,
      district: district,
      municipality: municipality,
      ward: ward,
    );
  }
}

final patientRepositoryProvider = Provider<IPatientRepository>((ref) {
  return PatientRepository();
});

final patientRegistrationProvider =
    StateNotifierProvider.autoDispose<PatientRegistrationViewModel, PatientRegistrationState>((ref) {
  final repo = ref.watch(patientRepositoryProvider);
  return PatientRegistrationViewModel(repo);
});
