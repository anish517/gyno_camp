import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/lookup_item_model.dart';
import '../repositories/lookup_repository.dart';
import 'auth_viewmodel.dart';

class MasterLookupState {
  final List<LookupItemModel> diagnoses;
  final List<LookupItemModel> medicines;
  final List<LookupItemModel> referralHospitals;
  final String selectedCategory;
  final String searchQuery;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const MasterLookupState({
    this.diagnoses = const [],
    this.medicines = const [],
    this.referralHospitals = const [],
    this.selectedCategory = 'diagnosis',
    this.searchQuery = '',
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

  List<LookupItemModel> get activeDiagnoses => diagnoses.where((d) => d.isActive).toList();
  List<LookupItemModel> get activeMedicines => medicines.where((m) => m.isActive).toList();
  List<LookupItemModel> get activeReferralHospitals => referralHospitals.where((h) => h.isActive).toList();

  List<LookupItemModel> get filteredDiagnoses {
    if (searchQuery.trim().isEmpty) return diagnoses;
    final q = searchQuery.toLowerCase().trim();
    return diagnoses.where((d) => d.labelEn.toLowerCase().contains(q) || d.labelNe.toLowerCase().contains(q)).toList();
  }

  List<LookupItemModel> get filteredMedicines {
    if (searchQuery.trim().isEmpty) return medicines;
    final q = searchQuery.toLowerCase().trim();
    return medicines.where((m) => m.labelEn.toLowerCase().contains(q) || m.labelNe.toLowerCase().contains(q)).toList();
  }

  List<LookupItemModel> get filteredReferralHospitals {
    if (searchQuery.trim().isEmpty) return referralHospitals;
    final q = searchQuery.toLowerCase().trim();
    return referralHospitals.where((h) => h.labelEn.toLowerCase().contains(q) || h.labelNe.toLowerCase().contains(q)).toList();
  }

  MasterLookupState copyWith({
    List<LookupItemModel>? diagnoses,
    List<LookupItemModel>? medicines,
    List<LookupItemModel>? referralHospitals,
    String? selectedCategory,
    String? searchQuery,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    bool clearError = false,
    bool clearSuccess = false,
  }) {
    return MasterLookupState(
      diagnoses: diagnoses ?? this.diagnoses,
      medicines: medicines ?? this.medicines,
      referralHospitals: referralHospitals ?? this.referralHospitals,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
    );
  }
}

class MasterLookupViewModel extends StateNotifier<MasterLookupState> {
  final ILookupRepository _repository;
  String _tenantId;

  MasterLookupViewModel(this._repository, {String? tenantId})
      : _tenantId = tenantId ?? 'tenant_default',
        super(const MasterLookupState()) {
    loadAll();
  }

  void updateTenant(String? newTenantId) {
    final tid = newTenantId ?? 'tenant_default';
    if (tid != _tenantId) {
      _tenantId = tid;
      loadAll();
    }
  }

  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      await _repository.ensureDefaultsSeeded(tenantId: _tenantId);
      final diag = await _repository.getItemsByCategory('diagnosis', tenantId: _tenantId);
      final med = await _repository.getItemsByCategory('medicine', tenantId: _tenantId);
      final hosp = await _repository.getItemsByCategory('referral_hospital', tenantId: _tenantId);

      state = state.copyWith(
        diagnoses: diag,
        medicines: med,
        referralHospitals: hosp,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load master lookup data: $e',
      );
    }
  }

  void setCategory(String category) {
    state = state.copyWith(selectedCategory: category, searchQuery: '');
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  Future<bool> addItem(
    LookupItemModel item, {
    required String userId,
    required String userName,
    required String deviceId,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      final itemToSave = (item.tenantId.isEmpty || item.tenantId == 'tenant_default') && _tenantId != 'tenant_default'
          ? item.copyWith(tenantId: _tenantId)
          : item;
      await _repository.addItem(itemToSave, userId: userId, userName: userName, deviceId: deviceId);
      await loadAll();
      state = state.copyWith(successMessage: 'Added "${item.labelEn}" successfully');
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to add item: $e');
      return false;
    }
  }

  Future<bool> updateItem(
    LookupItemModel item, {
    required String userId,
    required String userName,
    required String deviceId,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      await _repository.updateItem(item, userId: userId, userName: userName, deviceId: deviceId);
      await loadAll();
      state = state.copyWith(successMessage: 'Updated "${item.labelEn}"');
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to update item: $e');
      return false;
    }
  }

  Future<bool> toggleItemStatus(
    String id,
    bool isActive, {
    required String userId,
    required String userName,
    required String deviceId,
  }) async {
    state = state.copyWith(clearError: true, clearSuccess: true);
    try {
      final success = await _repository.toggleItemStatus(
        id,
        isActive,
        userId: userId,
        userName: userName,
        deviceId: deviceId,
      );
      if (success) {
        await loadAll();
        state = state.copyWith(
          successMessage: isActive ? 'Item activated' : 'Item deactivated',
        );
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to toggle status: $e');
      return false;
    }
  }

  Future<bool> deleteItem(
    String id, {
    required String userId,
    required String userName,
    required String deviceId,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      final success = await _repository.deleteItem(
        id,
        userId: userId,
        userName: userName,
        deviceId: deviceId,
      );
      if (success) {
        await loadAll();
        state = state.copyWith(successMessage: 'Item deleted permanently');
        return true;
      }
      state = state.copyWith(isLoading: false, errorMessage: 'Item not found');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to delete item: $e');
      return false;
    }
  }
}

final lookupRepositoryProvider = Provider<ILookupRepository>((ref) {
  return LookupRepository();
});

final masterLookupProvider = StateNotifierProvider<MasterLookupViewModel, MasterLookupState>((ref) {
  final repo = ref.watch(lookupRepositoryProvider);
  final user = ref.watch(authStateProvider).currentUser;
  return MasterLookupViewModel(repo, tenantId: user?.tenantId);
});

final activeDiagnosesProvider = Provider<List<LookupItemModel>>((ref) {
  return ref.watch(masterLookupProvider).activeDiagnoses;
});

final activeMedicinesProvider = Provider<List<LookupItemModel>>((ref) {
  return ref.watch(masterLookupProvider).activeMedicines;
});

final activeReferralHospitalsProvider = Provider<List<LookupItemModel>>((ref) {
  return ref.watch(masterLookupProvider).activeReferralHospitals;
});
