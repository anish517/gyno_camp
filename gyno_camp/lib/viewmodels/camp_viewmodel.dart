import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/session_service.dart';
import '../models/camp_model.dart';
import '../repositories/camp_repository.dart';

class CampState {
  final List<CampModel> camps;
  final CampModel? activeCamp; // Current open camp for data entry
  final CampModel? selectedCamp;
  final bool isLoading;
  final String? errorMessage;

  const CampState({
    this.camps = const [],
    this.activeCamp,
    this.selectedCamp,
    this.isLoading = false,
    this.errorMessage,
  });

  bool get hasActiveCamp => activeCamp != null;

  CampState copyWith({
    List<CampModel>? camps,
    CampModel? activeCamp,
    CampModel? selectedCamp,
    bool? isLoading,
    String? errorMessage,
    bool clearActiveCamp = false,
    bool clearError = false,
  }) {
    return CampState(
      camps: camps ?? this.camps,
      activeCamp: clearActiveCamp ? null : (activeCamp ?? this.activeCamp),
      selectedCamp: selectedCamp ?? this.selectedCamp,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class CampViewModel extends StateNotifier<CampState> {
  final ICampRepository _campRepository;

  CampViewModel(this._campRepository) : super(const CampState()) {
    loadCamps();
  }

  Future<void> loadCamps() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final camps = await _campRepository.getAllCamps();
      var active = await _campRepository.getActiveCamp();

      // If no camp is open in DB, check if the saved active camp from session is still open
      if (active == null && SessionService.current != null) {
        final savedCampId = SessionService.current!.getSavedActiveCampId();
        if (savedCampId != null) {
          final matched = camps.where((c) => c.id == savedCampId && c.status == CampStatus.open).toList();
          if (matched.isNotEmpty) {
            active = matched.first;
          }
        }
      }

      if (active != null) {
        await SessionService.current?.saveActiveCampId(active.id);
      } else {
        await SessionService.current?.clearActiveCampId();
      }

      state = state.copyWith(
        camps: camps,
        activeCamp: active,
        clearActiveCamp: active == null,
        selectedCamp: active ?? (camps.isNotEmpty ? camps.first : null),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load camps: $e',
      );
    }
  }

  void selectCamp(CampModel camp) {
    final isOpen = camp.status == CampStatus.open;
    state = state.copyWith(
      selectedCamp: camp,
      activeCamp: isOpen ? camp : (state.activeCamp?.status == CampStatus.open ? state.activeCamp : null),
      clearActiveCamp: !isOpen && (state.activeCamp == null || state.activeCamp?.id == camp.id),
    );
    if (isOpen) {
      SessionService.current?.saveActiveCampId(camp.id);
    }
  }

  void setActiveCamp(CampModel camp) {
    final isOpen = camp.status == CampStatus.open;
    state = state.copyWith(
      activeCamp: isOpen ? camp : null,
      selectedCamp: camp,
      clearActiveCamp: !isOpen,
    );
    if (isOpen) {
      SessionService.current?.saveActiveCampId(camp.id);
    } else {
      SessionService.current?.clearActiveCampId();
    }
  }

  Future<bool> createCamp(CampModel camp, {required String adminUserId, required String deviceId}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final created = await _campRepository.createCamp(
        camp,
        createdByUserId: adminUserId,
        deviceId: deviceId,
      );
      final updatedList = [created, ...state.camps];
      state = state.copyWith(camps: updatedList, isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Create camp failed: $e');
      return false;
    }
  }

  Future<bool> openCamp(String campId, {required String adminUserId, required String deviceId}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final success = await _campRepository.openCamp(
        campId,
        adminUserId: adminUserId,
        deviceId: deviceId,
      );
      if (success) {
        await loadCamps();
        return true;
      }
      state = state.copyWith(isLoading: false, errorMessage: 'Unable to open camp.');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Open camp error: $e');
      return false;
    }
  }

  Future<bool> closeCamp(String campId, {required String adminUserId, required String deviceId}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final success = await _campRepository.closeCamp(
        campId,
        adminUserId: adminUserId,
        deviceId: deviceId,
      );
      if (success) {
        if (SessionService.current?.getSavedActiveCampId() == campId) {
          await SessionService.current?.clearActiveCampId();
        }
        await loadCamps();
        return true;
      }
      state = state.copyWith(isLoading: false, errorMessage: 'Unable to close camp.');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Close camp error: $e');
      return false;
    }
  }

  Future<bool> archiveCamp(String campId, {required String adminUserId, required String deviceId}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final success = await _campRepository.archiveCamp(
        campId,
        adminUserId: adminUserId,
        deviceId: deviceId,
      );
      if (success) {
        if (SessionService.current?.getSavedActiveCampId() == campId) {
          await SessionService.current?.clearActiveCampId();
        }
        await loadCamps();
        return true;
      }
      state = state.copyWith(isLoading: false, errorMessage: 'Unable to archive camp.');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Archive camp error: $e');
      return false;
    }
  }

  Future<bool> updateCamp(CampModel camp, {required String adminUserId, required String deviceId}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _campRepository.updateCamp(
        camp,
        adminUserId: adminUserId,
        deviceId: deviceId,
      );
      await loadCamps();
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Update camp error: $e');
      return false;
    }
  }

  Future<bool> deleteCamp(String campId, {required String adminUserId, required String deviceId}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final success = await _campRepository.deleteCamp(
        campId,
        adminUserId: adminUserId,
        deviceId: deviceId,
      );
      if (success) {
        if (SessionService.current?.getSavedActiveCampId() == campId) {
          await SessionService.current?.clearActiveCampId();
        }
        await loadCamps();
        return true;
      }
      state = state.copyWith(isLoading: false, errorMessage: 'Unable to delete camp.');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Delete camp error: $e');
      return false;
    }
  }

  Future<bool> assignStaff(String campId, List<String> staffIds, {required String adminUserId, required String deviceId}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final success = await _campRepository.assignStaff(
        campId,
        staffIds,
        adminUserId: adminUserId,
        deviceId: deviceId,
      );
      if (success) {
        await loadCamps();
        return true;
      }
      state = state.copyWith(isLoading: false, errorMessage: 'Unable to assign staff.');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Assign staff error: $e');
      return false;
    }
  }
}

final campRepositoryProvider = Provider<ICampRepository>((ref) {
  return CampRepository();
});

final campStateProvider = StateNotifierProvider<CampViewModel, CampState>((ref) {
  final repository = ref.watch(campRepositoryProvider);
  return CampViewModel(repository);
});
