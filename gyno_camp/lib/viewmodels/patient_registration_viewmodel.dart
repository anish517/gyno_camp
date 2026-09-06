import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/duplicate_detection_service.dart';
import '../models/patient_model.dart';
import '../repositories/patient_repository.dart';

class PatientRegistrationState {
  final String firstName;
  final String surname;
  final int? age;
  final String mobile;
  final String district;
  final String municipality;
  final String ward;
  final String spouseOrFatherName;
  final String relationshipType;
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
    this.district = 'Kathmandu',
    this.municipality = 'Budhanilkantha Municipality',
    this.ward = '03',
    this.spouseOrFatherName = '',
    this.relationshipType = 'Husband',
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

  bool get isValid =>
      firstName.trim().isNotEmpty &&
      surname.trim().isNotEmpty &&
      age != null &&
      age! > 0 &&
      ward.trim().isNotEmpty;

  PatientRegistrationState copyWith({
    String? firstName,
    String? surname,
    int? age,
    String? mobile,
    String? district,
    String? municipality,
    String? ward,
    String? spouseOrFatherName,
    String? relationshipType,
    String? maritalStatus,
    int? maritalAge,
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
      age: age ?? this.age,
      mobile: mobile ?? this.mobile,
      district: district ?? this.district,
      municipality: municipality ?? this.municipality,
      ward: ward ?? this.ward,
      spouseOrFatherName: spouseOrFatherName ?? this.spouseOrFatherName,
      relationshipType: relationshipType ?? this.relationshipType,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      maritalAge: maritalAge ?? this.maritalAge,
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
    String? mobile,
    String? district,
    String? municipality,
    String? ward,
    String? spouseOrFatherName,
    String? relationshipType,
    String? maritalStatus,
    int? maritalAge,
    bool? consentTreatment,
    bool? consentStoreMedicalInfo,
  }) {
    state = state.copyWith(
      firstName: firstName,
      surname: surname,
      age: age,
      mobile: mobile,
      district: district,
      municipality: municipality,
      ward: ward,
      spouseOrFatherName: spouseOrFatherName,
      relationshipType: relationshipType,
      maritalStatus: maritalStatus,
      maritalAge: maritalAge,
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
      );

      state = state.copyWith(duplicateResult: result);
    } catch (_) {}
  }

  Future<PatientModel?> submitRegistration({
    required String campId,
    required String campCode,
    required String staffUserId,
    required String deviceId,
  }) async {
    if (!state.isValid) {
      state = state.copyWith(errorMessage: 'Please fill in required fields (Name, Age, Ward).');
      return null;
    }

    state = state.copyWith(isSubmitting: true, errorMessage: null);

    try {
      final patient = PatientModel(
        id: '', // Generated by repo
        patientId: '', // Auto formatted ID by repo
        campId: campId,
        campCode: campCode,
        intakeDate: DateTime.now(),
        firstName: state.firstName.trim(),
        surname: state.surname.trim(),
        age: state.age!,
        spouseOrFatherName: state.spouseOrFatherName.trim(),
        relationshipType: state.relationshipType,
        mobile: state.mobile.trim(),
        district: state.district,
        municipality: state.municipality,
        ward: state.ward.trim(),
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
        deviceId: deviceId,
      );

      state = state.copyWith(
        isSubmitting: false,
        registeredPatient: registered,
      );

      return registered;
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Registration failed: $e',
      );
      return null;
    }
  }

  void reset() {
    state = const PatientRegistrationState();
  }
}

final patientRepositoryProvider = Provider<IPatientRepository>((ref) {
  return PatientRepository();
});

final patientRegistrationProvider =
    StateNotifierProvider<PatientRegistrationViewModel, PatientRegistrationState>((ref) {
  final repo = ref.watch(patientRepositoryProvider);
  return PatientRegistrationViewModel(repo);
});
