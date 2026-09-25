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

  Future<void> loadCamps({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    try {
      final camps = await _campRepository.getAllCamps();

      // ── Active camp resolution (stable across syncs) ───────────────────
      // Priority 1: the camp the user explicitly chose (saved in session).
      //   This prevents sync from flipping the live station every 5 seconds
      //   just because a background update changed a camp's updatedAt.
      // Priority 2: the most recently CREATED open camp (first-time fallback).
      CampModel? active;
      final openCamps = camps.where((c) => c.status == CampStatus.open).toList();

      if (openCamps.isNotEmpty && SessionService.current != null) {
        final savedCampId = SessionService.current!.getSavedActiveCampId();
        if (savedCampId != null) {
          // Honour the user's explicit choice if it is still open
          final saved = openCamps.where((c) => c.id == savedCampId).toList();
          if (saved.isNotEmpty) active = saved.first;
        }
      }

      // Fallback: pick the most recently CREATED open camp (stable — createdAt never changes)
      if (active == null && openCamps.isNotEmpty) {
        active = openCamps.reduce((a, b) {
          final aTime = a.createdAt.toUtc();
          final bTime = b.createdAt.toUtc();
          return bTime.isAfter(aTime) ? b : a;
        });
      }

      if (active != null) {
        await SessionService.current?.saveActiveCampId(active.id);
      } else {
        await SessionService.current?.clearActiveCampId();
      }

      if (!mounted) return;
      state = state.copyWith(
        camps: camps,
        activeCamp: active,
        clearActiveCamp: active == null,
        selectedCamp: state.selectedCamp != null
            ? camps.firstWhere((c) => c.id == state.selectedCamp!.id, orElse: () => active ?? (camps.isNotEmpty ? camps.first : state.selectedCamp!))
            : (active ?? (camps.isNotEmpty ? camps.first : null)),
        isLoading: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load camps: $e',
      );
    }
  }

  /// Selects a camp for inspection/editing in the UI.
  /// Does NOT change activeCamp — multiple camps can be open simultaneously.
  void selectCamp(CampModel camp) {
    state = state.copyWith(selectedCamp: camp);
    // If the selected camp is open, promote it to activeCamp
    // so that patient registration defaults to this camp.
    if (camp.status == CampStatus.open) {
      state = state.copyWith(activeCamp: camp);
      SessionService.current?.saveActiveCampId(camp.id);
    }
  }

  /// Explicitly sets the active camp (e.g. after opening from the dialog).
  void setActiveCamp(CampModel camp) {
    state = state.copyWith(
      activeCamp: camp.status == CampStatus.open ? camp : state.activeCamp,
      selectedCamp: camp,
      clearActiveCamp: camp.status != CampStatus.open && state.activeCamp?.id == camp.id,
    );
    if (camp.status == CampStatus.open) {
      SessionService.current?.saveActiveCampId(camp.id);
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
      if (!mounted) return true;
      final updatedList = [created, ...state.camps];
      state = state.copyWith(
        camps: updatedList,
        isLoading: false,
        selectedCamp: created,
        activeCamp: created.status == CampStatus.open ? created : state.activeCamp,
      );
      if (created.status == CampStatus.open) {
        await SessionService.current?.saveActiveCampId(created.id);
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
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
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, errorMessage: 'Unable to open camp.');
      return false;
    } catch (e) {
      if (!mounted) return false;
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
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, errorMessage: 'Unable to close camp.');
      return false;
    } catch (e) {
      if (!mounted) return false;
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
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, errorMessage: 'Unable to archive camp.');
      return false;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, errorMessage: 'Archive camp error: $e');
      return false;
    }
  }

  Future<bool> updateCamp(CampModel camp, {required String adminUserId, required String deviceId}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final savedCamp = await _campRepository.updateCamp(
        camp,
        adminUserId: adminUserId,
        deviceId: deviceId,
      );
      if (!mounted) return true;
      // ✅ Optimistically update the in-memory list immediately so UI refreshes
      final updatedList = state.camps.map((c) {
        if (c.id == savedCamp.id) return savedCamp;
        if (savedCamp.status == CampStatus.open && c.status == CampStatus.open) {
          return c.copyWith(status: CampStatus.closed);
        }
        return c;
      }).toList();

      final newActive = savedCamp.status == CampStatus.open
          ? savedCamp
          : (state.activeCamp?.id == savedCamp.id ? null : state.activeCamp);

      state = state.copyWith(
        camps: updatedList,
        isLoading: false,
        activeCamp: newActive,
        clearActiveCamp: newActive == null,
        selectedCamp: state.selectedCamp?.id == savedCamp.id ? savedCamp : state.selectedCamp,
      );

      if (savedCamp.status == CampStatus.open) {
        await SessionService.current?.saveActiveCampId(savedCamp.id);
      } else if (state.activeCamp?.id == savedCamp.id) {
        await SessionService.current?.clearActiveCampId();
      }

      return true;
    } catch (e) {
      if (!mounted) return false;
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
        if (!mounted) return true;
        // ✅ Immediately remove from in-memory list so UI refreshes without DB round-trip
        final updatedList = state.camps.where((c) => c.id != campId).toList();
        state = state.copyWith(
          camps: updatedList,
          isLoading: false,
          clearActiveCamp: state.activeCamp?.id == campId,
          selectedCamp: state.selectedCamp?.id == campId
              ? (updatedList.isNotEmpty ? updatedList.first : null)
              : state.selectedCamp,
        );
        return true;
      }
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, errorMessage: 'Unable to delete camp.');
      return false;
    } catch (e) {
      if (!mounted) return false;
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
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, errorMessage: 'Unable to assign staff.');
      return false;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, errorMessage: 'Assign staff error: $e');
      return false;
    }
  }
}

final campRepositoryProvider = Provider<ICampRepository>((ref) {
  return CampRepository(enableCentralSync: true);
});

final campStateProvider = StateNotifierProvider<CampViewModel, CampState>((ref) {
  final repository = ref.watch(campRepositoryProvider);
  return CampViewModel(repository);
});
