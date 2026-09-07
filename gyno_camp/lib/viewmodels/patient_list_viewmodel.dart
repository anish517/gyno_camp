import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/patient_model.dart';
import '../repositories/patient_repository.dart';
import 'patient_registration_viewmodel.dart';

class PatientListState {
  final bool isLoading;
  final bool hasLoaded;
  final String? loadedCampId;
  final String? errorMessage;
  final String searchQuery;
  final List<PatientModel> patients;

  const PatientListState({
    this.isLoading = false,
    this.hasLoaded = false,
    this.loadedCampId,
    this.errorMessage,
    this.searchQuery = '',
    this.patients = const [],
  });

  PatientListState copyWith({
    bool? isLoading,
    bool? hasLoaded,
    String? loadedCampId,
    String? errorMessage,
    String? searchQuery,
    List<PatientModel>? patients,
  }) {
    return PatientListState(
      isLoading: isLoading ?? this.isLoading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      loadedCampId: loadedCampId ?? this.loadedCampId,
      errorMessage: errorMessage,
      searchQuery: searchQuery ?? this.searchQuery,
      patients: patients ?? this.patients,
    );
  }
}

class PatientListViewModel extends StateNotifier<PatientListState> {
  final IPatientRepository _patientRepository;

  PatientListViewModel(this._patientRepository) : super(const PatientListState());

  Future<void> loadPatients(String campId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final list = await _patientRepository.getPatientsByCamp(campId);
      state = state.copyWith(
        isLoading: false,
        hasLoaded: true,
        loadedCampId: campId,
        patients: list,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        hasLoaded: true,
        loadedCampId: campId,
        errorMessage: 'Failed to load patients: $e',
      );
    }
  }

  Future<void> search(String campId, String query) async {
    state = state.copyWith(searchQuery: query);
    if (query.trim().isEmpty) {
      await loadPatients(campId);
      return;
    }

    state = state.copyWith(isLoading: true);
    try {
      final results = await _patientRepository.searchPatients(campId: campId, query: query);
      state = state.copyWith(isLoading: false, patients: results);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Search failed: $e');
    }
  }
}

final patientListProvider = StateNotifierProvider<PatientListViewModel, PatientListState>((ref) {
  final repo = ref.watch(patientRepositoryProvider);
  return PatientListViewModel(repo);
});
