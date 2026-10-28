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
  final String? treatmentLevel;
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
  final bool isFollowUp;
  final String? followUpNotes;
  final bool surgeryDone;
  final String? surgeryType;

  final List<String> attendingDoctorNames;
  final String? primaryDoctorName;
  final List<String> attendingNurseNames;
  final String? primaryNurseName;

  final bool isSaving;
  final String? errorMessage;
  final ClinicalVisitModel? savedVisit;
  final String? existingVisitId;
  final DateTime? visitDate;
  final DateTime? anamnesisDate;
  final DateTime? examDate;
  final DateTime? labTestDate;
  final DateTime? conclusionDate;
  final DateTime? treatmentDate;
  final DateTime? outtakeDate;

  const ClinicalAssessmentState({
    this.currentStationIndex = 0,
    this.visitDate,
    this.anamnesisDate,
    this.examDate,
    this.labTestDate,
    this.conclusionDate,
    this.treatmentDate,
    this.outtakeDate,
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
    this.treatmentLevel,
    this.selectedCounseling = const [],
    this.pessaryType,
    this.pessarySize,
    this.surgicalReferral,
    this.selectedMedications = const [],
    this.customMedication,
    this.followUpNeeded = false,
    this.followUpDestination,
    this.outtakeNotes,
    this.isFollowUp = false,
    this.followUpNotes,
    this.surgeryDone = false,
    this.surgeryType,
    this.attendingDoctorNames = const [],
    this.primaryDoctorName,
    this.attendingNurseNames = const [],
    this.primaryNurseName,
    this.isSaving = false,
    this.errorMessage,
    this.savedVisit,
    this.existingVisitId,
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
    String? treatmentLevel,
    bool clearTreatmentLevel = false,
    List<String>? selectedCounseling,
    String? pessaryType,
    String? pessarySize,
    String? surgicalReferral,
    List<String>? selectedMedications,
    String? customMedication,
    bool? followUpNeeded,
    String? followUpDestination,
    String? outtakeNotes,
    bool? isFollowUp,
    String? followUpNotes,
    bool? surgeryDone,
    String? surgeryType,
    bool clearSurgeryType = false,
    List<String>? attendingDoctorNames,
    String? primaryDoctorName,
    List<String>? attendingNurseNames,
    String? primaryNurseName,
    bool? isSaving,
    String? errorMessage,
    ClinicalVisitModel? savedVisit,
    bool clearSaved = false,
    String? existingVisitId,
    bool clearExistingVisitId = false,
    DateTime? visitDate,
    bool clearVisitDate = false,
    DateTime? anamnesisDate,
    bool clearAnamnesisDate = false,
    DateTime? examDate,
    bool clearExamDate = false,
    DateTime? labTestDate,
    bool clearLabTestDate = false,
    DateTime? conclusionDate,
    bool clearConclusionDate = false,
    DateTime? treatmentDate,
    bool clearTreatmentDate = false,
    DateTime? outtakeDate,
    bool clearOuttakeDate = false,
  }) {
    return ClinicalAssessmentState(
      currentStationIndex: currentStationIndex ?? this.currentStationIndex,
      visitDate: clearVisitDate ? null : (visitDate ?? this.visitDate),
      anamnesisDate: clearAnamnesisDate ? null : (anamnesisDate ?? this.anamnesisDate),
      examDate: clearExamDate ? null : (examDate ?? this.examDate),
      labTestDate: clearLabTestDate ? null : (labTestDate ?? this.labTestDate),
      conclusionDate: clearConclusionDate ? null : (conclusionDate ?? this.conclusionDate),
      treatmentDate: clearTreatmentDate ? null : (treatmentDate ?? this.treatmentDate),
      outtakeDate: clearOuttakeDate ? null : (outtakeDate ?? this.outtakeDate),
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
      treatmentLevel: clearTreatmentLevel ? null : (treatmentLevel ?? this.treatmentLevel),
      selectedCounseling: selectedCounseling ?? this.selectedCounseling,
      pessaryType: pessaryType ?? this.pessaryType,
      pessarySize: pessarySize ?? this.pessarySize,
      surgicalReferral: surgicalReferral ?? this.surgicalReferral,
      selectedMedications: selectedMedications ?? this.selectedMedications,
      customMedication: customMedication ?? this.customMedication,
      followUpNeeded: followUpNeeded ?? this.followUpNeeded,
      followUpDestination: followUpDestination ?? this.followUpDestination,
      outtakeNotes: outtakeNotes ?? this.outtakeNotes,
      isFollowUp: isFollowUp ?? this.isFollowUp,
      followUpNotes: followUpNotes ?? this.followUpNotes,
      surgeryDone: surgeryDone ?? this.surgeryDone,
      surgeryType: clearSurgeryType ? null : (surgeryType ?? this.surgeryType),
      attendingDoctorNames: attendingDoctorNames ?? this.attendingDoctorNames,
      primaryDoctorName: primaryDoctorName ?? this.primaryDoctorName,
      attendingNurseNames: attendingNurseNames ?? this.attendingNurseNames,
      primaryNurseName: primaryNurseName ?? this.primaryNurseName,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: errorMessage,
      savedVisit: clearSaved ? null : (savedVisit ?? this.savedVisit),
      existingVisitId: clearExistingVisitId ? null : (existingVisitId ?? this.existingVisitId),
    );
  }
}

class ClinicalAssessmentViewModel extends StateNotifier<ClinicalAssessmentState> {
  final IPatientRepository _patientRepository;

  ClinicalAssessmentViewModel(this._patientRepository)
      : super(const ClinicalAssessmentState());

  void setVisitDate(DateTime date) {
    state = state.copyWith(visitDate: date);
  }

  void setAnamnesisDate(DateTime date) => state = state.copyWith(anamnesisDate: date);
  void setExamDate(DateTime date) => state = state.copyWith(examDate: date);
  void setLabTestDate(DateTime date) => state = state.copyWith(labTestDate: date);
  void setConclusionDate(DateTime date) => state = state.copyWith(conclusionDate: date);
  void setTreatmentDate(DateTime date) => state = state.copyWith(treatmentDate: date);
  void setOuttakeDate(DateTime date) => state = state.copyWith(outtakeDate: date);

  void setStationDate(int stationIndex, DateTime date) {
    switch (stationIndex) {
      case 0:
        setAnamnesisDate(date);
        break;
      case 1:
        setExamDate(date);
        break;
      case 2:
        setLabTestDate(date);
        break;
      case 3:
        setConclusionDate(date);
        break;
      case 4:
        setTreatmentDate(date);
        break;
      case 5:
        setOuttakeDate(date);
        break;
    }
  }

  void setAttendingDoctors(List<String> doctors) {
    state = state.copyWith(
      attendingDoctorNames: doctors,
      primaryDoctorName: doctors.isNotEmpty ? doctors.first : null,
    );
  }

  void toggleAttendingDoctor(String doctor) {
    final list = List<String>.from(state.attendingDoctorNames);
    if (list.contains(doctor)) {
      list.remove(doctor);
    } else {
      list.add(doctor);
    }
    state = state.copyWith(
      attendingDoctorNames: list,
      primaryDoctorName: list.isNotEmpty ? list.first : null,
    );
  }

  void setAttendingNurses(List<String> nurses) {
    state = state.copyWith(
      attendingNurseNames: nurses,
      primaryNurseName: nurses.isNotEmpty ? nurses.first : null,
    );
  }

  void toggleAttendingNurse(String nurse) {
    final list = List<String>.from(state.attendingNurseNames);
    if (list.contains(nurse)) {
      list.remove(nurse);
    } else {
      list.add(nurse);
    }
    state = state.copyWith(
      attendingNurseNames: list,
      primaryNurseName: list.isNotEmpty ? list.first : null,
    );
  }

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

  Map<String, dynamic> _resolveComplaintData(String complaintKey) {
    if (state.complaints.isEmpty) return const {};
    if (state.complaints[complaintKey] is Map && (state.complaints[complaintKey] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(state.complaints[complaintKey] as Map);
    }
    final lowerKey = complaintKey.toLowerCase().trim();
    if (state.complaints[lowerKey] is Map && (state.complaints[lowerKey] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(state.complaints[lowerKey] as Map);
    }
    final withSpaces = lowerKey.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    final withUnderscores = lowerKey.replaceAll(RegExp(r'[\s\-]+'), '_').trim();
    if (state.complaints[withSpaces] is Map && (state.complaints[withSpaces] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(state.complaints[withSpaces] as Map);
    }
    if (state.complaints[withUnderscores] is Map && (state.complaints[withUnderscores] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(state.complaints[withUnderscores] as Map);
    }

    final List<String> aliases = [];
    if (lowerKey.contains('prolapse') || lowerKey.contains('hanging') || lowerKey.contains('mass')) {
      aliases.addAll(['prolapse', 'something hanging out', 'something_hanging_out']);
    } else if (lowerKey.contains('discharge') || lowerKey.contains('itching')) {
      aliases.addAll(['discharge', 'discharge and or itching', 'discharge_and_or_itching', 'discharge / itching', 'discharge___itching', 'discharge_itching']);
    } else if (lowerKey.contains('urine') || lowerKey.contains('micturition')) {
      aliases.addAll(['urine', 'problems passing urine', 'problems_passing_urine']);
    } else if (lowerKey.contains('stool') || lowerKey.contains('bowel')) {
      aliases.addAll(['stool', 'problems passing stool', 'problems_passing_stool']);
    } else if (lowerKey.contains('menstrual')) {
      aliases.addAll(['menstrual', 'menstrual problem', 'menstrual_problem']);
    } else if (lowerKey.contains('infertility')) {
      aliases.addAll(['infertility']);
    } else if (lowerKey.contains('abdomen')) {
      aliases.addAll(['lower_abdomen_pain', 'lower abdomen pain', 'pain']);
    } else if (lowerKey.contains('back')) {
      aliases.addAll(['lower_back_pain', 'lower back pain', 'pain']);
    } else if (lowerKey == 'pain') {
      aliases.addAll(['pain', 'lower_abdomen_pain', 'lower_back_pain']);
    } else if (lowerKey.contains('checkup')) {
      aliases.addAll(['checkup']);
    }

    for (final a in aliases) {
      if (state.complaints[a] is Map && (state.complaints[a] as Map).isNotEmpty) {
        return Map<String, dynamic>.from(state.complaints[a] as Map);
      }
    }
    return const {};
  }

  List<String> _getComplaintAliases(String complaintKey) {
    final lowerKey = complaintKey.toLowerCase().trim();
    final withSpaces = lowerKey.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    final withUnderscores = lowerKey.replaceAll(RegExp(r'[\s\-]+'), '_').trim();
    final set = <String>{complaintKey, lowerKey, withSpaces, withUnderscores};
    if (lowerKey.contains('hanging') || lowerKey.contains('prolapse') || lowerKey.contains('mass')) {
      set.addAll(['prolapse', 'something hanging out', 'something_hanging_out']);
    } else if (lowerKey.contains('discharge') || lowerKey.contains('itching')) {
      set.addAll(['discharge', 'discharge and or itching', 'discharge_and_or_itching', 'discharge / itching', 'discharge___itching', 'discharge_itching']);
    } else if (lowerKey.contains('urine') || lowerKey.contains('micturition')) {
      set.addAll(['urine', 'problems passing urine', 'problems_passing_urine']);
    } else if (lowerKey.contains('stool') || lowerKey.contains('bowel')) {
      set.addAll(['stool', 'problems passing stool', 'problems_passing_stool']);
    } else if (lowerKey.contains('menstrual')) {
      set.addAll(['menstrual', 'menstrual problem', 'menstrual_problem']);
    } else if (lowerKey.contains('infertility')) {
      set.addAll(['infertility']);
    } else if (lowerKey.contains('abdomen')) {
      set.addAll(['lower_abdomen_pain', 'lower abdomen pain', 'pain']);
    } else if (lowerKey.contains('back')) {
      set.addAll(['lower_back_pain', 'lower back pain', 'pain']);
    } else if (lowerKey == 'pain') {
      set.addAll(['pain', 'lower_abdomen_pain', 'lower_back_pain']);
    } else if (lowerKey.contains('checkup')) {
      set.addAll(['checkup']);
    }
    return set.toList();
  }

  String _canonicalKey(String key) {
    final k = key.toLowerCase().replaceAll(RegExp(r'[_\-\s]+'), ' ').trim();
    if (k.contains('prolapse') || k.contains('hanging') || k.contains('mass')) return 'prolapse';
    if (k.contains('discharge') || k.contains('itching')) return 'discharge';
    if (k.contains('urine') || k.contains('micturition')) return 'urine';
    if (k.contains('stool') || k.contains('bowel')) return 'stool';
    if (k.contains('menstrual')) return 'menstrual';
    if (k.contains('infertility')) return 'infertility';
    if (k.contains('abdomen') || k.contains('abdominal')) return 'lower_abdomen_pain';
    if (k.contains('back')) return 'lower_back_pain';
    if (k.contains('checkup')) return 'checkup';
    return key;
  }

  void _syncClinicalComplaintsList(Map<String, dynamic> map) {
    const metaKeys = {
      'clinicalComplaints',
      'clinical_complaints',
      'complaints_duration',
      'complaintsDuration',
      'reasons',
      'new_issues',
      'newIssues',
      'visitReasons',
    };

    final activeKeys = <String>{};

    for (final entry in map.entries) {
      if (metaKeys.contains(entry.key)) continue;
      if (entry.value is Map) {
        final m = entry.value as Map;
        final isActive = m['active'] == true ||
            m['present'] == true ||
            ((m['duration'] as String?)?.isNotEmpty == true) ||
            ((m['subOption'] as String?)?.isNotEmpty == true) ||
            (m['options'] is List && (m['options'] as List).isNotEmpty) ||
            ((m['remarks'] as String?)?.isNotEmpty == true);
        if (isActive) {
          final canon = _canonicalKey(entry.key);
          activeKeys.add(canon);
        }
      }
    }

    map['clinicalComplaints'] = activeKeys.toList();
  }

  void updateComplaint(String complaintKey, Map<String, dynamic> data) {
    final map = Map<String, dynamic>.from(state.complaints);
    for (final k in _getComplaintAliases(complaintKey)) {
      if (data.isEmpty) {
        map.remove(k);
      } else {
        map[k] = Map<String, dynamic>.from(data);
      }
    }
    _syncClinicalComplaintsList(map);
    state = state.copyWith(complaints: map);
  }

  void setComplaintDuration(String complaintKey, String duration) {
    final map = Map<String, dynamic>.from(state.complaints);
    final current = Map<String, dynamic>.from(_resolveComplaintData(complaintKey));
    current['duration'] = duration;
    current['active'] = true;
    current['present'] = true;
    for (final k in _getComplaintAliases(complaintKey)) {
      map[k] = Map<String, dynamic>.from(current);
    }
    _syncClinicalComplaintsList(map);
    state = state.copyWith(complaints: map);
  }

  void toggleComplaintOption(String complaintKey, String option) {
    final map = Map<String, dynamic>.from(state.complaints);
    final current = Map<String, dynamic>.from(_resolveComplaintData(complaintKey));
    final rawOptions = current['options'] ?? current['subOptions'] ?? current['subOption'];
    final List<String> optionsList = [];
    if (rawOptions is List) {
      for (final item in rawOptions) {
        final s = item?.toString().trim();
        if (s != null && s.isNotEmpty && !optionsList.contains(s)) {
          optionsList.add(s);
        }
      }
    } else if (rawOptions is String && rawOptions.trim().isNotEmpty) {
      for (final item in rawOptions.split(',')) {
        final s = item.trim();
        if (s.isNotEmpty && !optionsList.contains(s)) {
          optionsList.add(s);
        }
      }
    }

    final matchIdx = optionsList.indexWhere((e) => e.toLowerCase() == option.toLowerCase());
    if (matchIdx >= 0) {
      optionsList.removeAt(matchIdx);
    } else {
      optionsList.add(option);
    }
    current['options'] = optionsList;
    current['subOptions'] = optionsList;
    current['subOption'] = optionsList.join(', ');
    current['active'] = true;
    current['present'] = true;
    for (final k in _getComplaintAliases(complaintKey)) {
      map[k] = Map<String, dynamic>.from(current);
    }
    _syncClinicalComplaintsList(map);
    state = state.copyWith(complaints: map);
  }

  void setComplaintRemarks(String complaintKey, String remarks) {
    final map = Map<String, dynamic>.from(state.complaints);
    final current = Map<String, dynamic>.from(_resolveComplaintData(complaintKey));
    current['remarks'] = remarks;
    current['active'] = true;
    current['present'] = true;
    for (final k in _getComplaintAliases(complaintKey)) {
      map[k] = Map<String, dynamic>.from(current);
    }
    _syncClinicalComplaintsList(map);
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

  void setPopStages({int? anterior, int? middle, int? posterior, int? highest}) {
    final a = anterior ?? state.popAnteriorStage;
    final m = middle ?? state.popMiddleStage;
    final p = posterior ?? state.popPosteriorStage;
    final computedHighest = ClinicalVisitModel.computeHighestPopStage(a, m, p);
    final h = highest ?? computedHighest;

    state = state.copyWith(
      popAnteriorStage: a,
      popMiddleStage: m,
      popPosteriorStage: p,
      highestPopStage: h,
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
  void setTreatmentLevel(String? level) {
    state = state.copyWith(
      treatmentLevel: level,
      clearTreatmentLevel: level == null || level.isEmpty,
    );
  }

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
  void setOuttake({
    bool? followUpNeeded,
    String? destination,
    String? notes,
    bool? isFollowUp,
    String? followUpNotes,
    bool? surgeryDone,
    String? surgeryType,
  }) {
    state = state.copyWith(
      followUpNeeded: followUpNeeded,
      followUpDestination: destination,
      outtakeNotes: notes,
      isFollowUp: isFollowUp,
      followUpNotes: followUpNotes,
      surgeryDone: surgeryDone,
      surgeryType: surgeryType,
    );
  }

  void setSurgery({required bool surgeryDone, String? surgeryType}) {
    state = state.copyWith(
      surgeryDone: surgeryDone,
      surgeryType: surgeryType,
      clearSurgeryType: !surgeryDone,
    );
  }

  /// Loads an existing clinical visit for the patient from SQLite if present
  Future<ClinicalVisitModel?> loadPatientAssessment(String patientId, {String? patientUuid}) async {
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final visit = await _patientRepository.getLatestClinicalVisit(patientId, patientUuid: patientUuid);
      if (!mounted) return visit;
      if (visit != null) {
        state = state.copyWith(
          existingVisitId: visit.id,
          visitDate: visit.visitDate,
          anamnesisDate: visit.anamnesisDate,
          examDate: visit.examDate,
          labTestDate: visit.labTestDate,
          conclusionDate: visit.conclusionDate,
          treatmentDate: visit.treatmentDate,
          outtakeDate: visit.outtakeDate,
          deliveries: visit.deliveries,
          livingChildren: visit.livingChildren,
          abortions: visit.abortions,
          complaints: visit.anamnesisComplaints,
          uterusInside: visit.uterusInside,
          vulvaRemarks: visit.vulvaRemarks,
          vaginaRemarks: visit.vaginaRemarks,
          cervixRemarks: visit.cervixRemarks,
          uterusRemarks: visit.uterusRemarks,
          pelvicFloorTone: visit.pelvicFloorTone,
          popAnteriorStage: visit.popAnteriorStage,
          popMiddleStage: visit.popMiddleStage,
          popPosteriorStage: visit.popPosteriorStage,
          highestPopStage: visit.highestPopStage,
          urineTest: visit.urineTest ?? 'normal',
          pregnancyTest: visit.pregnancyTest ?? 'neg',
          systolicBp: visit.systolicBp,
          diastolicBp: visit.diastolicBp,
          pulse: visit.pulse,
          spo2: visit.spo2,
          glucose: visit.glucose,
          ecgNotes: visit.ecgNotes,
          selectedDiagnoses: visit.diagnoses,
          treatmentLevel: visit.treatmentLevel,
          selectedCounseling: visit.counseling,
          pessaryType: visit.pessaryType,
          pessarySize: visit.pessarySize,
          surgicalReferral: visit.surgicalReferral,
          selectedMedications: visit.medications,
          customMedication: visit.customMedication,
          followUpNeeded: visit.followUpNeeded,
          followUpDestination: visit.followUpDestination,
          outtakeNotes: visit.outtakeNotes,
          isFollowUp: visit.isFollowUp,
          followUpNotes: visit.followUpNotes,
          surgeryDone: visit.surgeryDone,
          surgeryType: visit.surgeryType,
          attendingDoctorNames: visit.attendingDoctorNames,
          primaryDoctorName: visit.primaryDoctorName,
          attendingNurseNames: visit.attendingNurseNames,
          primaryNurseName: visit.primaryNurseName,
          isSaving: false,
          savedVisit: visit,
          systolicValidation: visit.systolicBp != null
              ? ClinicalValidationService.validateSystolicBp(visit.systolicBp)
              : const ValidationResult.normal(),
          diastolicValidation: visit.diastolicBp != null
              ? ClinicalValidationService.validateDiastolicBp(visit.diastolicBp, systolic: visit.systolicBp)
              : const ValidationResult.normal(),
          pulseValidation: visit.pulse != null
              ? ClinicalValidationService.validatePulse(visit.pulse)
              : const ValidationResult.normal(),
          spo2Validation: visit.spo2 != null
              ? ClinicalValidationService.validateSpO2(visit.spo2)
              : const ValidationResult.normal(),
          glucoseValidation: visit.glucose != null
              ? ClinicalValidationService.validateGlucose(visit.glucose)
              : const ValidationResult.normal(),
          obstetricValidation: (visit.deliveries != null && visit.livingChildren != null)
              ? ClinicalValidationService.validateObstetricCounts(
                  deliveries: visit.deliveries!,
                  livingChildren: visit.livingChildren!,
                  abortions: visit.abortions ?? 0,
                )
              : const ValidationResult.normal(),
        );
        return visit;
      } else {
        state = const ClinicalAssessmentState();
        return null;
      }
    } catch (e) {
      if (!mounted) return null;
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Failed to load existing visit: $e',
      );
      return null;
    }
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
      final complaintsMap = Map<String, dynamic>.from(state.complaints);
      _syncClinicalComplaintsList(complaintsMap);

      final visit = ClinicalVisitModel(
        id: state.existingVisitId ?? '',
        patientId: patientId,
        campId: campId,
        visitDate: state.visitDate ?? state.savedVisit?.visitDate ?? DateTime.now(),
        anamnesisDate: state.anamnesisDate ?? state.savedVisit?.anamnesisDate,
        examDate: state.examDate ?? state.savedVisit?.examDate,
        labTestDate: state.labTestDate ?? state.savedVisit?.labTestDate,
        conclusionDate: state.conclusionDate ?? state.savedVisit?.conclusionDate,
        treatmentDate: state.treatmentDate ?? state.savedVisit?.treatmentDate,
        outtakeDate: state.outtakeDate ?? state.savedVisit?.outtakeDate,
        deliveries: state.deliveries,
        livingChildren: state.livingChildren,
        abortions: state.abortions,
        anamnesisComplaints: complaintsMap,
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
        treatmentLevel: state.treatmentLevel,
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
        isFollowUp: state.isFollowUp,
        followUpNotes: state.followUpNotes,
        surgeryDone: state.surgeryDone,
        surgeryType: state.surgeryDone ? state.surgeryType : null,
        attendingDoctorNames: state.attendingDoctorNames,
        primaryDoctorName: state.primaryDoctorName ??
            (state.attendingDoctorNames.isNotEmpty ? state.attendingDoctorNames.first : null),
        attendingNurseNames: state.attendingNurseNames,
        primaryNurseName: state.primaryNurseName ??
            (state.attendingNurseNames.isNotEmpty ? state.attendingNurseNames.first : null),
        createdAt: DateTime.now(),
        createdByUserId: staffUserId,
      );

      final saved = await _patientRepository.saveClinicalVisit(
        visit,
        createdByUserId: staffUserId,
        deviceId: deviceId,
      );

      if (!mounted) return saved;
      state = state.copyWith(isSaving: false, savedVisit: saved, existingVisitId: saved.id);
      return saved;
    } catch (e) {
      if (!mounted) return null;
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
