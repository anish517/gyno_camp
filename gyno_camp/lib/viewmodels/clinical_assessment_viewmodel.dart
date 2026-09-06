import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/clinical_constants.dart';
import '../core/services/clinical_validation_service.dart';
import '../models/clinical_visit_model.dart';
import '../repositories/patient_repository.dart';
import 'patient_registration_viewmodel.dart';

class ClinicalAssessmentState {
  final int currentStationIndex; // 0 to 5

  // Station 1: Obstetric History
  final int? deliveries;
  final int? livingChildren;
  final int? abortions;
  final Map<String, dynamic> complaints;

  // Station 2: Exam & POP
  final bool uterusInside;
  final String? vulvaRemarks;
  final String? vaginaRemarks;
  final String? cervixRemarks;
  final String? uterusRemarks;
  final String pelvicFloorTone;
  final int popAnteriorStage;
  final int popMiddleStage;
  final int popPosteriorStage;
  final int highestPopStage;

  // Station 3: Lab & Vitals
  final String? urineTest;
  final String? pregnancyTest;
  final int? systolicBp;
  final int? diastolicBp;
  final int? pulse;
  final int? spo2;
  final int? glucose;
  final String? ecgNotes;

  // Live Validations
  final ValidationResult systolicValidation;
  final ValidationResult diastolicValidation;
  final ValidationResult pulseValidation;
  final ValidationResult spo2Validation;
  final ValidationResult glucoseValidation;
  final ValidationResult obstetricValidation;

  // Station 4: Diagnoses
  final List<String> selectedDiagnoses;

  // Station 5: Treatment & Medication
  final List<String> selectedCounseling;
  final String? pessaryType;
  final String? pessarySize;
  final String? surgicalReferral;
  final List<String> selectedMedications;
  final String? customMedication;

  // Station 6: Outtake
  final bool followUpNeeded;
  final String? followUpDestination;
  final String? outtakeNotes;

  final bool isSaving;
  final String? errorMessage;
  final ClinicalVisitModel? savedVisit;

  const ClinicalAssessmentState({
    this.currentStationIndex = 0,
    this.deliveries,
    this.livingChildren,
    this.abortions,
    this.complaints = const {},
    this.uterusInside = true,
    this.vulvaRemarks,
    this.vaginaRemarks,
    this.cervixRemarks,
    this.uterusRemarks,
    this.pelvicFloorTone = ClinicalConstants.pelvicFloorNormal,
    this.popAnteriorStage = 0,
    this.popMiddleStage = 0,
    this.popPosteriorStage = 0,
    this.highestPopStage = 0,
    this.urineTest = 'normal',
    this.pregnancyTest = 'neg',
    this.systolicBp,
    this.diastolicBp,
    this.pulse,
    this.spo2,
    this.glucose,
    this.ecgNotes,
    this.systolicValidation = const ValidationResult.normal(),
    this.diastolicValidation = const ValidationResult.normal(),
    this.pulseValidation = const ValidationResult.normal(),
    this.spo2Validation = const ValidationResult.normal(),
    this.glucoseValidation = const ValidationResult.normal(),
    this.obstetricValidation = const ValidationResult.normal(),
    this.selectedDiagnoses = const [],
    this.selectedCounseling = const [],
    this.pessaryType,
    this.pessarySize,
    this.surgicalReferral,
    this.selectedMedications = const [],
    this.customMedication,
    this.followUpNeeded = false,
    this.followUpDestination,
    this.outtakeNotes,
    this.isSaving = false,
    this.errorMessage,
    this.savedVisit,
  });

  bool get areVitalsValid =>
      systolicValidation.isValid &&
      diastolicValidation.isValid &&
      pulseValidation.isValid &&
      spo2Validation.isValid &&
      glucoseValidation.isValid;

  ClinicalAssessmentState copyWith({
    int? currentStationIndex,
    int? deliveries,
    int? livingChildren,
    int? abortions,
    Map<String, dynamic>? complaints,
    bool? uterusInside,
    String? vulvaRemarks,
    String? vaginaRemarks,
    String? cervixRemarks,
    String? uterusRemarks,
    String? pelvicFloorTone,
    int? popAnteriorStage,
    int? popMiddleStage,
    int? popPosteriorStage,
    int? highestPopStage,
    String? urineTest,
    String? pregnancyTest,
    int? systolicBp,
    int? diastolicBp,
    int? pulse,
    int? spo2,
    int? glucose,
    String? ecgNotes,
    ValidationResult? systolicValidation,
    ValidationResult? diastolicValidation,
    ValidationResult? pulseValidation,
    ValidationResult? spo2Validation,
    ValidationResult? glucoseValidation,
    ValidationResult? obstetricValidation,
    List<String>? selectedDiagnoses,
    List<String>? selectedCounseling,
    String? pessaryType,
    String? pessarySize,
    String? surgicalReferral,
    List<String>? selectedMedications,
    String? customMedication,
    bool? followUpNeeded,
    String? followUpDestination,
    String? outtakeNotes,
    bool? isSaving,
    String? errorMessage,
    ClinicalVisitModel? savedVisit,
    bool clearSaved = false,
  }) {
    return ClinicalAssessmentState(
      currentStationIndex: currentStationIndex ?? this.currentStationIndex,
      deliveries: deliveries ?? this.deliveries,
      livingChildren: livingChildren ?? this.livingChildren,
      abortions: abortions ?? this.abortions,
      complaints: complaints ?? this.complaints,
      uterusInside: uterusInside ?? this.uterusInside,
      vulvaRemarks: vulvaRemarks ?? this.vulvaRemarks,
      vaginaRemarks: vaginaRemarks ?? this.vaginaRemarks,
      cervixRemarks: cervixRemarks ?? this.cervixRemarks,
      uterusRemarks: uterusRemarks ?? this.uterusRemarks,
      pelvicFloorTone: pelvicFloorTone ?? this.pelvicFloorTone,
      popAnteriorStage: popAnteriorStage ?? this.popAnteriorStage,
      popMiddleStage: popMiddleStage ?? this.popMiddleStage,
      popPosteriorStage: popPosteriorStage ?? this.popPosteriorStage,
      highestPopStage: highestPopStage ?? this.highestPopStage,
      urineTest: urineTest ?? this.urineTest,
      pregnancyTest: pregnancyTest ?? this.pregnancyTest,
      systolicBp: systolicBp ?? this.systolicBp,
      diastolicBp: diastolicBp ?? this.diastolicBp,
      pulse: pulse ?? this.pulse,
      spo2: spo2 ?? this.spo2,
      glucose: glucose ?? this.glucose,
      ecgNotes: ecgNotes ?? this.ecgNotes,
      systolicValidation: systolicValidation ?? this.systolicValidation,
      diastolicValidation: diastolicValidation ?? this.diastolicValidation,
      pulseValidation: pulseValidation ?? this.pulseValidation,
      spo2Validation: spo2Validation ?? this.spo2Validation,
      glucoseValidation: glucoseValidation ?? this.glucoseValidation,
      obstetricValidation: obstetricValidation ?? this.obstetricValidation,
      selectedDiagnoses: selectedDiagnoses ?? this.selectedDiagnoses,
      selectedCounseling: selectedCounseling ?? this.selectedCounseling,
      pessaryType: pessaryType ?? this.pessaryType,
      pessarySize: pessarySize ?? this.pessarySize,
      surgicalReferral: surgicalReferral ?? this.surgicalReferral,
      selectedMedications: selectedMedications ?? this.selectedMedications,
      customMedication: customMedication ?? this.customMedication,
      followUpNeeded: followUpNeeded ?? this.followUpNeeded,
      followUpDestination: followUpDestination ?? this.followUpDestination,
      outtakeNotes: outtakeNotes ?? this.outtakeNotes,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: errorMessage,
      savedVisit: clearSaved ? null : (savedVisit ?? this.savedVisit),
    );
  }
}

class ClinicalAssessmentViewModel extends StateNotifier<ClinicalAssessmentState> {
  final IPatientRepository _patientRepository;

  ClinicalAssessmentViewModel(this._patientRepository)
      : super(const ClinicalAssessmentState());

  void setStation(int index) {
    state = state.copyWith(currentStationIndex: index.clamp(0, 5));
  }

  void goToStation(int index) => setStation(index);

  void nextStation() {
    if (state.currentStationIndex < 5) {
      state = state.copyWith(currentStationIndex: state.currentStationIndex + 1);
    }
  }

  void previousStation() {
    if (state.currentStationIndex > 0) {
      state = state.copyWith(currentStationIndex: state.currentStationIndex - 1);
    }
  }

  // --- Station 1: Obstetric History ---
  void setObstetricHistory({int? deliveries, int? livingChildren, int? abortions}) {
    final newDeliv = deliveries ?? state.deliveries;
    final newLiving = livingChildren ?? state.livingChildren;
    final newAbort = abortions ?? state.abortions;

    final obsValidation = ClinicalValidationService.validateObstetricCounts(
      deliveries: newDeliv,
      livingChildren: newLiving,
      abortions: newAbort,
    );

    state = state.copyWith(
      deliveries: newDeliv,
      livingChildren: newLiving,
      abortions: newAbort,
      obstetricValidation: obsValidation,
    );
  }

  void updateComplaint(String complaintKey, Map<String, dynamic> data) {
    final map = Map<String, dynamic>.from(state.complaints);
    map[complaintKey] = data;
    state = state.copyWith(complaints: map);
  }

  void setComplaintDuration(String complaintKey, String duration) {
    final map = Map<String, dynamic>.from(state.complaints);
    final current = Map<String, dynamic>.from((map[complaintKey] as Map?) ?? {});
    current['duration'] = duration;
    map[complaintKey] = current;
    state = state.copyWith(complaints: map);
  }

  void toggleComplaintOption(String complaintKey, String option) {
    final map = Map<String, dynamic>.from(state.complaints);
    final current = Map<String, dynamic>.from((map[complaintKey] as Map?) ?? {});
    final rawOptions = current['options'];
    final List<String> optionsList = rawOptions is List ? List<String>.from(rawOptions) : [];
    if (optionsList.contains(option)) {
      optionsList.remove(option);
    } else {
      optionsList.add(option);
    }
    current['options'] = optionsList;
    map[complaintKey] = current;
    state = state.copyWith(complaints: map);
  }

  // --- Station 2: Exam & POP Staging ---
  void updateExam({
    bool? uterusInside,
    String? vulvaRemarks,
    String? vaginaRemarks,
    String? cervixRemarks,
    String? uterusRemarks,
    String? pelvicFloorTone,
  }) {
    state = state.copyWith(
      uterusInside: uterusInside,
      vulvaRemarks: vulvaRemarks,
      vaginaRemarks: vaginaRemarks,
      cervixRemarks: cervixRemarks,
      uterusRemarks: uterusRemarks,
      pelvicFloorTone: pelvicFloorTone,
    );
  }

  void setPopStages({int? anterior, int? middle, int? posterior}) {
    final a = anterior ?? state.popAnteriorStage;
    final m = middle ?? state.popMiddleStage;
    final p = posterior ?? state.popPosteriorStage;
    final highest = ClinicalVisitModel.computeHighestPopStage(a, m, p);

    state = state.copyWith(
      popAnteriorStage: a,
      popMiddleStage: m,
      popPosteriorStage: p,
      highestPopStage: highest,
    );
  }

  void setAnamnesis({int? deliveries, int? livingChildren, int? abortions}) {
    setObstetricHistory(deliveries: deliveries, livingChildren: livingChildren, abortions: abortions);
  }

  void setPhysicalExam({
    bool? uterusInside,
    String? vulvaRemarks,
    String? vaginaRemarks,
    String? cervixRemarks,
    String? uterusRemarks,
    String? pelvicFloorTone,
    int? popAnterior,
    int? popMiddle,
    int? popPosterior,
  }) {
    updateExam(
      uterusInside: uterusInside,
      vulvaRemarks: vulvaRemarks,
      vaginaRemarks: vaginaRemarks,
      cervixRemarks: cervixRemarks,
      uterusRemarks: uterusRemarks,
      pelvicFloorTone: pelvicFloorTone,
    );
    if (popAnterior != null || popMiddle != null || popPosterior != null) {
      setPopStages(anterior: popAnterior, middle: popMiddle, posterior: popPosterior);
    }
  }

  // --- Station 3: Vitals & Lab (Real-time Validation) ---
  void setVitals({
    int? systolic,
    int? diastolic,
    int? pulse,
    int? spo2,
    int? glucose,
    String? urineTest,
    String? pregnancyTest,
    String? ecgNotes,
  }) {
    final s = systolic ?? state.systolicBp;
    final d = diastolic ?? state.diastolicBp;
    final p = pulse ?? state.pulse;
    final o = spo2 ?? state.spo2;
    final g = glucose ?? state.glucose;

    final sysVal = ClinicalValidationService.validateSystolicBp(s);
    final diaVal = ClinicalValidationService.validateDiastolicBp(d, systolic: s);
    final pulVal = ClinicalValidationService.validatePulse(p);
    final spoVal = ClinicalValidationService.validateSpO2(o);
    final gluVal = ClinicalValidationService.validateGlucose(g);

    state = state.copyWith(
      systolicBp: s,
      diastolicBp: d,
      pulse: p,
      spo2: o,
      glucose: g,
      urineTest: urineTest ?? state.urineTest,
      pregnancyTest: pregnancyTest ?? state.pregnancyTest,
      ecgNotes: ecgNotes ?? state.ecgNotes,
      systolicValidation: sysVal,
      diastolicValidation: diaVal,
      pulseValidation: pulVal,
      spo2Validation: spoVal,
      glucoseValidation: gluVal,
    );
  }

  // --- Station 4: Diagnoses ---
  void toggleDiagnosis(String diagnosis) {
    final list = List<String>.from(state.selectedDiagnoses);
    if (list.contains(diagnosis)) {
      list.remove(diagnosis);
    } else {
      list.add(diagnosis);
    }
    state = state.copyWith(selectedDiagnoses: list);
  }

  // --- Station 5: Treatment & Medications ---
  void toggleCounseling(String point) {
    final list = List<String>.from(state.selectedCounseling);
    if (list.contains(point)) {
      list.remove(point);
    } else {
      list.add(point);
    }
    state = state.copyWith(selectedCounseling: list);
  }

  void setPessary({String? type, String? size}) {
    state = state.copyWith(pessaryType: type, pessarySize: size);
  }

  void setSurgicalReferral(String? hospital) {
    state = state.copyWith(surgicalReferral: hospital);
  }

  void toggleMedication(String med) {
    final list = List<String>.from(state.selectedMedications);
    if (list.contains(med)) {
      list.remove(med);
    } else {
      list.add(med);
    }
    state = state.copyWith(selectedMedications: list);
  }

  void setCustomMedication(String text) {
    state = state.copyWith(customMedication: text);
  }

  // --- Station 6: Outtake & Follow-up ---
  void setOuttake({bool? followUpNeeded, String? destination, String? notes}) {
    state = state.copyWith(
      followUpNeeded: followUpNeeded,
      followUpDestination: destination,
      outtakeNotes: notes,
    );
  }

  Future<ClinicalVisitModel?> submitAssessment({
    required String patientId,
    required String campId,
    required String staffUserId,
    required String deviceId,
  }) async {
    if (!state.areVitalsValid) {
      state = state.copyWith(
        errorMessage: 'Cannot save: One or more vitals contain critical errors. Please correct.',
      );
      return null;
    }

    state = state.copyWith(isSaving: true, errorMessage: null);

    try {
      final visit = ClinicalVisitModel(
        id: '',
        patientId: patientId,
        campId: campId,
        visitDate: DateTime.now(),
        deliveries: state.deliveries,
        livingChildren: state.livingChildren,
        abortions: state.abortions,
        anamnesisComplaints: state.complaints,
        uterusInside: state.uterusInside,
        vulvaRemarks: state.vulvaRemarks,
        vaginaRemarks: state.vaginaRemarks,
        cervixRemarks: state.cervixRemarks,
        uterusRemarks: state.uterusRemarks,
        pelvicFloorTone: state.pelvicFloorTone,
        popAnteriorStage: state.popAnteriorStage,
        popMiddleStage: state.popMiddleStage,
        popPosteriorStage: state.popPosteriorStage,
        highestPopStage: state.highestPopStage,
        urineTest: state.urineTest,
        pregnancyTest: state.pregnancyTest,
        systolicBp: state.systolicBp,
        diastolicBp: state.diastolicBp,
        pulse: state.pulse,
        spo2: state.spo2,
        glucose: state.glucose,
        ecgNotes: state.ecgNotes,
        diagnoses: state.selectedDiagnoses,
        counseling: state.selectedCounseling,
        pessaryType: state.pessaryType,
        pessarySize: state.pessarySize,
        surgicalReferral: state.surgicalReferral,
        medications: state.selectedMedications,
        customMedication: state.customMedication,
        followUpNeeded: state.followUpNeeded,
        followUpDestination: state.followUpDestination,
        outtakeNotes: state.outtakeNotes,
        createdAt: DateTime.now(),
        createdByUserId: staffUserId,
      );

      final saved = await _patientRepository.saveClinicalVisit(
        visit,
        createdByUserId: staffUserId,
        deviceId: deviceId,
      );

      state = state.copyWith(isSaving: false, savedVisit: saved);
      return saved;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Failed to save clinical assessment: $e',
      );
      return null;
    }
  }

  void reset() {
    state = const ClinicalAssessmentState();
  }
}

final clinicalAssessmentProvider =
    StateNotifierProvider<ClinicalAssessmentViewModel, ClinicalAssessmentState>((ref) {
  final repo = ref.watch(patientRepositoryProvider);
  return ClinicalAssessmentViewModel(repo);
});
