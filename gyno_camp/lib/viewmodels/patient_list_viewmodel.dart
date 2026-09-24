import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      (clinicalIntake != null && clinicalIntake != 'all');

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
    if (!silent) {
      state = state.copyWith(isLoading: true, errorMessage: null);
    }
    try {
      final list = await _patientRepository.getPatientsByCamp(campId);
      if (!mounted) return;
      final filtered = _filterList(list, state.searchQuery, state.filters);
      state = state.copyWith(
        isLoading: false,
        hasLoaded: true,
        loadedCampId: campId,
        rawPatients: list,
        patients: filtered,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        hasLoaded: true,
        loadedCampId: campId,
        errorMessage: 'Failed to load patients: $e',
      );
    }
  }

  Future<void> search(String? campId, String query) async {
    if (state.rawPatients.isEmpty || (campId != null && state.loadedCampId != campId)) {
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
    const defaultFilters = PatientFilterCriteria();
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
      if (filters.disease != null && filters.disease!.trim().isNotEmpty) {
        final dLower = filters.disease!.trim().toLowerCase();
        final matchesDisease = p.diagnoses.any((d) => d.toLowerCase().contains(dLower));
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

      // Chief complaint
      if (filters.chiefComplaint != null && filters.chiefComplaint!.trim().isNotEmpty) {
        final cLower = filters.chiefComplaint!.trim().toLowerCase();
        final matchesComplaint = p.reasonsForVisit.any((r) => r.toLowerCase() == cLower);
        if (!matchesComplaint) return false;
      }

      // Clinical Intake
      if (filters.clinicalIntake != null && filters.clinicalIntake != 'all') {
        if (filters.clinicalIntake == 'completed' && !p.hasClinicalVisit) return false;
        if (filters.clinicalIntake == 'pending' && p.hasClinicalVisit) return false;
        if (filters.clinicalIntake == 'followup' && !p.isFollowUp) return false;
      }

      return true;
    }).toList();
  }
}

final patientListProvider = StateNotifierProvider<PatientListViewModel, PatientListState>((ref) {
  final repo = ref.watch(patientRepositoryProvider);
  return PatientListViewModel(repo);
});
