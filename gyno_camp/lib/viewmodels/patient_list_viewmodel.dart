import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nurse_profile.dart';
import '../models/patient_model.dart';
import '../repositories/patient_repository.dart';
import 'patient_registration_viewmodel.dart';

class PatientFilterCriteria {
  final String? campId; // null or 'all'
  final int? minAge;
  final int? maxAge;
  final String? district;
  final String? province;
  final String? municipality;
  final String? maritalStatus; // 'all', 'married', 'unmarried', 'widow', 'divorced'
  final String? disease; // diagnosis substring
  final String? surgeryDone; // 'all', 'yes', 'no'
  final String? surgeryType; // 'Open surgery', 'Laparoscopy', 'Vaginal route'
  final String? popStage; // 'all', '0', '1', '2', '3', '4'
  final String? chiefComplaint; // reason for visit key e.g. 'something hanging out'
  final String? clinicalIntake; // 'all', 'completed', 'pending', 'followup'
  final String? doctor; // 'all' or specific doctor name
  final String? nurse; // 'all' or specific nurse name
  final Map<String, List<String>> campDoctorsMap; // campId -> doctorNames list

  const PatientFilterCriteria({
    this.campId,
    this.minAge,
    this.maxAge,
    this.district,
    this.province,
    this.municipality,
    this.maritalStatus,
    this.disease,
    this.surgeryDone,
    this.surgeryType,
    this.popStage,
    this.chiefComplaint,
    this.clinicalIntake,
    this.doctor,
    this.nurse,
    this.campDoctorsMap = const {},
  });

  bool get hasActiveFilters =>
      (campId != null && campId != 'all') ||
      minAge != null ||
      maxAge != null ||
      (district != null && district!.trim().isNotEmpty) ||
      (province != null && province!.trim().isNotEmpty && province != 'all') ||
      (municipality != null && municipality!.trim().isNotEmpty) ||
      (maritalStatus != null && maritalStatus != 'all') ||
      (disease != null && disease!.trim().isNotEmpty) ||
      (surgeryDone != null && surgeryDone != 'all') ||
      (surgeryType != null && surgeryType!.trim().isNotEmpty) ||
      (popStage != null && popStage != 'all') ||
      (chiefComplaint != null && chiefComplaint!.trim().isNotEmpty) ||
      (clinicalIntake != null && clinicalIntake != 'all') ||
      (doctor != null && doctor != 'all' && doctor!.trim().isNotEmpty) ||
      (nurse != null && nurse != 'all' && nurse!.trim().isNotEmpty);

  int get activeFilterCount {
    int count = 0;
    if (campId != null && campId != 'all') count++;
    if (minAge != null || maxAge != null) count++;
    if (district != null && district!.trim().isNotEmpty) count++;
    if (province != null && province!.trim().isNotEmpty && province != 'all') count++;
    if (municipality != null && municipality!.trim().isNotEmpty) count++;
    if (maritalStatus != null && maritalStatus != 'all') count++;
    if (disease != null && disease!.trim().isNotEmpty) count++;
    if (surgeryDone != null && surgeryDone != 'all') count++;
    if (surgeryType != null && surgeryType!.trim().isNotEmpty) count++;
    if (popStage != null && popStage != 'all') count++;
    if (chiefComplaint != null && chiefComplaint!.trim().isNotEmpty) count++;
    if (clinicalIntake != null && clinicalIntake != 'all') count++;
    if (doctor != null && doctor != 'all' && doctor!.trim().isNotEmpty) count++;
    if (nurse != null && nurse != 'all' && nurse!.trim().isNotEmpty) count++;
    return count;
  }

  PatientFilterCriteria copyWith({
    String? campId,
    int? minAge,
    int? maxAge,
    String? district,
    String? province,
    String? municipality,
    String? maritalStatus,
    String? disease,
    String? surgeryDone,
    String? surgeryType,
    String? popStage,
    String? chiefComplaint,
    String? clinicalIntake,
    String? doctor,
    String? nurse,
    Map<String, List<String>>? campDoctorsMap,
    bool clearMinAge = false,
    bool clearMaxAge = false,
    bool clearDistrict = false,
    bool clearProvince = false,
    bool clearMunicipality = false,
    bool clearMaritalStatus = false,
    bool clearDisease = false,
    bool clearSurgeryDone = false,
    bool clearSurgeryType = false,
    bool clearPopStage = false,
    bool clearChiefComplaint = false,
    bool clearClinicalIntake = false,
    bool clearDoctor = false,
    bool clearNurse = false,
  }) {
    return PatientFilterCriteria(
      campId: campId ?? this.campId,
      minAge: clearMinAge ? null : (minAge ?? this.minAge),
      maxAge: clearMaxAge ? null : (maxAge ?? this.maxAge),
      district: clearDistrict ? null : (district ?? this.district),
      province: clearProvince ? null : (province ?? this.province),
      municipality: clearMunicipality ? null : (municipality ?? this.municipality),
      maritalStatus: clearMaritalStatus ? null : (maritalStatus ?? this.maritalStatus),
      disease: clearDisease ? null : (disease ?? this.disease),
      surgeryDone: clearSurgeryDone ? null : (surgeryDone ?? this.surgeryDone),
      surgeryType: clearSurgeryType ? null : (surgeryType ?? this.surgeryType),
      popStage: clearPopStage ? null : (popStage ?? this.popStage),
      chiefComplaint: clearChiefComplaint ? null : (chiefComplaint ?? this.chiefComplaint),
      clinicalIntake: clearClinicalIntake ? null : (clinicalIntake ?? this.clinicalIntake),
      doctor: clearDoctor ? null : (doctor ?? this.doctor),
      nurse: clearNurse ? null : (nurse ?? this.nurse),
      campDoctorsMap: campDoctorsMap ?? this.campDoctorsMap,
    );
  }
}

class PatientListState {
  final bool isLoading;
  final bool hasLoaded;
  final String? loadedCampId;
  final String? errorMessage;
  final String searchQuery;
  final List<PatientModel> rawPatients;
  final List<PatientModel> patients;
  final PatientFilterCriteria filters;

  const PatientListState({
    this.isLoading = false,
    this.hasLoaded = false,
    this.loadedCampId,
    this.errorMessage,
    this.searchQuery = '',
    this.rawPatients = const [],
    this.patients = const [],
    this.filters = const PatientFilterCriteria(),
  });

  PatientListState copyWith({
    bool? isLoading,
    bool? hasLoaded,
    String? loadedCampId,
    String? errorMessage,
    String? searchQuery,
    List<PatientModel>? rawPatients,
    List<PatientModel>? patients,
    PatientFilterCriteria? filters,
  }) {
    return PatientListState(
      isLoading: isLoading ?? this.isLoading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      loadedCampId: loadedCampId ?? this.loadedCampId,
      errorMessage: errorMessage,
      searchQuery: searchQuery ?? this.searchQuery,
      rawPatients: rawPatients ?? this.rawPatients,
      patients: patients ?? this.patients,
      filters: filters ?? this.filters,
    );
  }
}

class PatientListViewModel extends StateNotifier<PatientListState> {
  final IPatientRepository _patientRepository;

  PatientListViewModel(this._patientRepository) : super(const PatientListState());

  Future<void> loadPatients([String? campId, bool silent = false]) async {
    final cleanCampId = (campId == null || campId == 'all' || campId.trim().isEmpty) ? null : campId.trim();
    final isDifferentCamp = cleanCampId != state.loadedCampId;
    final updatedFilters = cleanCampId != null
        ? state.filters.copyWith(campId: cleanCampId)
        : (campId == 'all' || (campId == null && state.filters.campId == 'all')
            ? state.filters.copyWith(campId: 'all')
            : state.filters);

    if (!silent) {
      state = state.copyWith(
        isLoading: true,
        errorMessage: null,
        // Clear stale patients if switching to a different camp to prevent 3 -> 1 flash
        patients: isDifferentCamp ? const [] : state.patients,
        rawPatients: isDifferentCamp ? const [] : state.rawPatients,
        filters: updatedFilters,
      );
    }
    try {
      final list = await _patientRepository.getPatientsByCamp(cleanCampId);
      if (!mounted) return;
      final filtered = _filterList(list, state.searchQuery, updatedFilters);
      state = state.copyWith(
        isLoading: false,
        hasLoaded: true,
        loadedCampId: cleanCampId,
        rawPatients: list,
        patients: filtered,
        filters: updatedFilters,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        hasLoaded: true,
        loadedCampId: cleanCampId,
        errorMessage: 'Failed to load patients: $e',
      );
    }
  }

  Future<void> search(String? campId, String query) async {
    final cleanCampId = (campId == null || campId == 'all' || campId.trim().isEmpty) ? null : campId.trim();
    if (state.rawPatients.isEmpty || cleanCampId != state.loadedCampId) {
      await loadPatients(campId);
    }
    if (!mounted) return;
    final filtered = _filterList(state.rawPatients, query, state.filters);
    state = state.copyWith(
      searchQuery: query,
      patients: filtered,
    );
  }

  void updateFilters(PatientFilterCriteria newFilters) {
    final filtered = _filterList(state.rawPatients, state.searchQuery, newFilters);
    state = state.copyWith(
      filters: newFilters,
      patients: filtered,
    );
  }

  void resetFilters() {
    final preservedCampId = state.filters.campId;
    final defaultFilters = PatientFilterCriteria(campId: preservedCampId);
    final filtered = _filterList(state.rawPatients, state.searchQuery, defaultFilters);
    state = state.copyWith(
      filters: defaultFilters,
      patients: filtered,
    );
  }

  List<PatientModel> _filterList(
    List<PatientModel> list,
    String query,
    PatientFilterCriteria filters,
  ) {
    final q = query.trim().toLowerCase();

    return list.where((p) {
      // 1. Search query
      if (q.isNotEmpty) {
        final matchesQuery = p.fullName.toLowerCase().contains(q) ||
            p.patientId.toLowerCase().contains(q) ||
            p.mobile.contains(q) ||
            p.ward.toLowerCase().contains(q) ||
            p.district.toLowerCase().contains(q) ||
            p.municipality.toLowerCase().contains(q);
        if (!matchesQuery) return false;
      }

      // 2. Demographic & Patient Filters
      // Camp
      if (filters.campId != null && filters.campId != 'all') {
        if (p.campId != filters.campId) return false;
      }

      // Age
      if (filters.minAge != null && p.age < filters.minAge!) return false;
      if (filters.maxAge != null && p.age > filters.maxAge!) return false;

      // Province
      if (filters.province != null && filters.province!.isNotEmpty && filters.province != 'all') {
        if (p.province.toLowerCase() != filters.province!.toLowerCase()) return false;
      }

      // District
      if (filters.district != null && filters.district!.trim().isNotEmpty) {
        if (!p.district.toLowerCase().contains(filters.district!.trim().toLowerCase())) return false;
      }

      // Municipality
      if (filters.municipality != null && filters.municipality!.trim().isNotEmpty) {
        if (!p.municipality.toLowerCase().contains(filters.municipality!.trim().toLowerCase())) return false;
      }

      // Marital status
      if (filters.maritalStatus != null && filters.maritalStatus != 'all') {
        if (p.maritalStatus.toLowerCase() != filters.maritalStatus!.toLowerCase()) return false;
      }

      // Disease / Diagnosis
      if (filters.disease != null && filters.disease!.trim().isNotEmpty && filters.disease != 'all') {
        final dLower = filters.disease!.trim().toLowerCase().replaceAll('_', ' ');
        final matchesDisease = p.diagnoses.any((d) {
          final cleanD = d.toLowerCase().trim().replaceAll('_', ' ');
          return cleanD == dLower || cleanD.contains(dLower) || dLower.contains(cleanD);
        });
        if (!matchesDisease) return false;
      }

      // Surgery Done
      if (filters.surgeryDone != null && filters.surgeryDone != 'all') {
        if (filters.surgeryDone == 'yes') {
          if (p.surgeryDone != true) return false;
        } else if (filters.surgeryDone == 'no') {
          if (p.surgeryDone == true) return false;
        }
      }

      // Surgery Type
      if (filters.surgeryType != null && filters.surgeryType!.trim().isNotEmpty) {
        if (p.surgeryType != filters.surgeryType) return false;
      }

      // 3. Clinical & Staging Filters
      // POP Stage
      if (filters.popStage != null && filters.popStage != 'all') {
        if (p.highestPopStage?.toString() != filters.popStage) return false;
      }

      // Chief complaint / Visit Reason
      if (filters.chiefComplaint != null && filters.chiefComplaint!.trim().isNotEmpty && filters.chiefComplaint != 'all') {
        final cLower = filters.chiefComplaint!.trim().toLowerCase().replaceAll('_', ' ');
        final matchesComplaint = p.reasonsForVisit.any((r) {
          final rLower = r.trim().toLowerCase().replaceAll('_', ' ');
          if (rLower == cLower) return true;
          if (rLower.contains(cLower) || cLower.contains(rLower)) return true;
          if (cLower.contains('hanging') || cLower.contains('prolapse') || cLower.contains('खस्ने')) {
            return rLower.contains('hanging') || rLower.contains('prolapse') || rLower.contains('खस्ने');
          }
          if (cLower.contains('discharge') || cLower.contains('itching') || cLower.contains('स्राव') || cLower.contains('चिलाउने')) {
            return rLower.contains('discharge') || rLower.contains('itching') || rLower.contains('सेतो') || rLower.contains('चिलाउने') || rLower.contains('स्राव');
          }
          if (cLower.contains('urine') || cLower.contains('पिसाब')) {
            return rLower.contains('urine') || rLower.contains('dysuria') || rLower.contains('पिसाब');
          }
          if (cLower.contains('stool') || cLower.contains('bowel') || cLower.contains('दिसा')) {
            return rLower.contains('stool') || rLower.contains('bowel') || rLower.contains('constipation') || rLower.contains('दिसा');
          }
          if (cLower.contains('pain') || cLower.contains('दुखाई') || cLower.contains('दुख्ने')) {
            return rLower.contains('pain') || rLower.contains('दुख्ने') || rLower.contains('दुखाई') || rLower.contains('तल्लो पेट');
          }
          if (cLower.contains('menstrual') || cLower.contains('महिनावारी') || cLower.contains('bleeding')) {
            return rLower.contains('menstrual') || rLower.contains('महिनावारी') || rLower.contains('bleeding');
          }
          if (cLower.contains('infertility') || cLower.contains('बाँझोपन') || cLower.contains('निःसन्तान')) {
            return rLower.contains('infertility') || rLower.contains('निःसन्तान') || rLower.contains('बाँझोपन');
          }
          if (cLower.contains('checkup') || cLower.contains('routine') || cLower.contains('जाँच')) {
            return rLower.contains('checkup') || rLower.contains('routine') || rLower.contains('जाँच');
          }
          return false;
        });
        if (!matchesComplaint) return false;
      }

      // Clinical Intake
      if (filters.clinicalIntake != null && filters.clinicalIntake != 'all') {
        if (filters.clinicalIntake == 'completed' && !p.hasClinicalVisit) return false;
        if (filters.clinicalIntake == 'pending' && p.hasClinicalVisit) return false;
        if (filters.clinicalIntake == 'followup' && !p.isFollowUp) return false;
      }

      // 4. Doctor Filter — match strictly by attending/primary doctor when visit exists
      if (filters.doctor != null && filters.doctor != 'all' && filters.doctor!.trim().isNotEmpty) {
        final docFilter = filters.doctor!;

        bool docNamesMatch(String a, String b) {
          final cleanA = a.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim().toLowerCase();
          final cleanB = b.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim().toLowerCase();
          if (cleanA.isEmpty || cleanB.isEmpty) return false;
          return cleanA == cleanB || cleanA.contains(cleanB) || cleanB.contains(cleanA);
        }

        final primaryMatch = p.primaryDoctorName != null && docNamesMatch(p.primaryDoctorName!, docFilter);
        final attendingMatch = p.attendingDoctorNames.any((d) => docNamesMatch(d, docFilter));

        if (p.hasClinicalVisit) {
          // Patient has been examined: clinical accountability rests solely on the examining doctor
          if (!primaryMatch && !attendingMatch) return false;
        } else {
          // Patient registered but not yet examined:
          // If the camp has only a single doctor assigned, the patient belongs to that doctor's queue
          final campDocs = (filters.campDoctorsMap[p.campId] ?? const [])
              .map((d) => d.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim())
              .where((d) => d.isNotEmpty)
              .toList();

          if (campDocs.length == 1 && docNamesMatch(campDocs.first, docFilter)) {
            // Belongs to the solo doctor queue for this camp
          } else {
            return false;
          }
        }
      }

      // 5. Nurse Filter — visit-based only (no solo-doctor-queue fallback)
      if (filters.nurse != null && filters.nurse != 'all' && filters.nurse!.trim().isNotEmpty) {
        final nurseFilter = filters.nurse!;

        bool nurseNamesMatch(String a, String b) {
          final cleanA = NurseProfile.stripPrefixes(a).toLowerCase();
          final cleanB = NurseProfile.stripPrefixes(b).toLowerCase();
          if (cleanA.isEmpty || cleanB.isEmpty) return false;
          return cleanA == cleanB || cleanA.contains(cleanB) || cleanB.contains(cleanA);
        }

        final primaryMatch = p.primaryNurseName != null && nurseNamesMatch(p.primaryNurseName!, nurseFilter);
        final attendingMatch = p.attendingNurseNames.any((n) => nurseNamesMatch(n, nurseFilter));

        if (!primaryMatch && !attendingMatch) return false;
      }

      return true;
    }).toList();
  }
}

final patientListProvider = StateNotifierProvider<PatientListViewModel, PatientListState>((ref) {
  final repo = ref.watch(patientRepositoryProvider);
  return PatientListViewModel(repo);
});
