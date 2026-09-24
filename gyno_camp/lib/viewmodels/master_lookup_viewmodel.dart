import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/lookup_item_model.dart';
import '../repositories/lookup_repository.dart';
import 'auth_viewmodel.dart';

class MasterLookupState {
  final List<LookupItemModel> diagnoses;
  final List<LookupItemModel> medicines;
  final List<LookupItemModel> referralHospitals;
  final List<LookupItemModel> visitReasons;
  final List<LookupItemModel> chiefComplaints;
  final String selectedCategory;
  final String searchQuery;
  final String? selectedCampId;
  final List<LookupItemModel> excludedFromCurrentCamp;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const MasterLookupState({
    this.diagnoses = const [],
    this.medicines = const [],
    this.referralHospitals = const [],
    this.visitReasons = const [],
    this.chiefComplaints = const [],
    this.excludedFromCurrentCamp = const [],
    this.selectedCategory = 'diagnosis',
    this.searchQuery = '',
    this.selectedCampId,
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

  List<LookupItemModel> get activeDiagnoses => diagnoses.where((d) => d.isActive).toList();
  List<LookupItemModel> get activeMedicines => medicines.where((m) => m.isActive).toList();
  List<LookupItemModel> get activeReferralHospitals => referralHospitals.where((h) => h.isActive).toList();
  List<LookupItemModel> get activeReferrals => activeReferralHospitals;
  List<LookupItemModel> get activeVisitReasons => visitReasons.where((r) => r.isActive).toList();
  List<LookupItemModel> get activeChiefComplaints => chiefComplaints.where((c) => c.isActive).toList();

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

  List<LookupItemModel> get filteredVisitReasons {
    if (searchQuery.trim().isEmpty) return visitReasons;
    final q = searchQuery.toLowerCase().trim();
    return visitReasons.where((r) => r.labelEn.toLowerCase().contains(q) || r.labelNe.toLowerCase().contains(q)).toList();
  }

  List<LookupItemModel> get filteredChiefComplaints {
    if (searchQuery.trim().isEmpty) return chiefComplaints;
    final q = searchQuery.toLowerCase().trim();
    return chiefComplaints.where((c) => c.labelEn.toLowerCase().contains(q) || c.labelNe.toLowerCase().contains(q)).toList();
  }

  MasterLookupState copyWith({
    List<LookupItemModel>? diagnoses,
    List<LookupItemModel>? medicines,
    List<LookupItemModel>? referralHospitals,
    List<LookupItemModel>? visitReasons,
    List<LookupItemModel>? chiefComplaints,
    List<LookupItemModel>? excludedFromCurrentCamp,
    String? selectedCategory,
    String? searchQuery,
    String? selectedCampId,
    bool clearCampId = false,
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
      visitReasons: visitReasons ?? this.visitReasons,
      chiefComplaints: chiefComplaints ?? this.chiefComplaints,
      excludedFromCurrentCamp: excludedFromCurrentCamp ?? this.excludedFromCurrentCamp,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCampId: clearCampId ? null : (selectedCampId ?? this.selectedCampId),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
    );
  }
}

class MasterLookupViewModel extends StateNotifier<MasterLookupState> {
  final ILookupRepository _repository;
  String _tenantId;
  String? _campId;

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

  void setCampScope(String? campId) {
    final cleanCampId = (campId == null || campId == 'all' || campId.trim().isEmpty) ? null : campId.trim();
    if (cleanCampId != _campId) {
      _campId = cleanCampId;
      state = state.copyWith(selectedCampId: cleanCampId, clearCampId: cleanCampId == null);
      loadAll();
    }
  }

  Future<void> loadAll({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    }
    try {
      await _repository.ensureDefaultsSeeded(tenantId: _tenantId);
      final diag = await _repository.getItemsByCategory('diagnosis', tenantId: _tenantId, campId: _campId);
      final med = await _repository.getItemsByCategory('medicine', tenantId: _tenantId, campId: _campId);
      final hosp = await _repository.getItemsByCategory('referral_hospital', tenantId: _tenantId, campId: _campId);
      final reasons = await _repository.getItemsByCategory('visit_reason', tenantId: _tenantId, campId: _campId);
      final complaints = await _repository.getItemsByCategory('chief_complaint', tenantId: _tenantId, campId: _campId);

      List<LookupItemModel> excluded = [];
      if (_campId != null) {
        final all = await _repository.getAllItems(tenantId: _tenantId);
        excluded = all.where((i) => i.excludedCampIds.contains(_campId)).toList();
      }

      if (!mounted) return;
      state = state.copyWith(
        diagnoses: diag,
        medicines: med,
        referralHospitals: hosp,
        visitReasons: reasons,
        chiefComplaints: complaints,
        excludedFromCurrentCamp: excluded,
        selectedCampId: _campId,
        clearCampId: _campId == null,
        isLoading: false,
      );
    } catch (e) {
      if (!mounted) return;
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
          ? item.copyWith(tenantId: _tenantId, campId: item.campId ?? _campId)
          : item.copyWith(campId: item.campId ?? _campId);
      await _repository.addItem(itemToSave, userId: userId, userName: userName, deviceId: deviceId);
      await loadAll();
      if (!mounted) return true;
      state = state.copyWith(successMessage: 'Added "${item.labelEn}" successfully');
      return true;
    } catch (e) {
      if (!mounted) return false;
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
      if (!mounted) return true;
      state = state.copyWith(successMessage: 'Updated "${item.labelEn}"');
      return true;
    } catch (e) {
      if (!mounted) return false;
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
    String? campId,
  }) async {
    state = state.copyWith(clearError: true, clearSuccess: true);
    try {
      final effectiveCampId = campId ?? _campId;
      final success = await _repository.toggleItemStatus(
        id,
        isActive,
        userId: userId,
        userName: userName,
        deviceId: deviceId,
        campId: effectiveCampId,
      );
      if (success) {
        await loadAll();
        if (!mounted) return true;
        state = state.copyWith(
          successMessage: effectiveCampId != null && !isActive
              ? 'Item disabled for this camp'
              : (isActive ? 'Item activated' : 'Item deactivated'),
        );
        return true;
      }
      return false;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(errorMessage: 'Failed to toggle status: $e');
      return false;
    }
  }

  Future<bool> deleteItem(
    String id, {
    required String userId,
    required String userName,
    required String deviceId,
    String? campId,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      final effectiveCampId = campId ?? _campId;
      final success = await _repository.deleteItem(
        id,
        userId: userId,
        userName: userName,
        deviceId: deviceId,
        campId: effectiveCampId,
      );
      if (success) {
        await loadAll();
        if (!mounted) return true;
        state = state.copyWith(
          successMessage: effectiveCampId != null ? 'Item removed from this camp' : 'Item deleted permanently',
        );
        return true;
      }
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, errorMessage: 'Item not found');
      return false;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to delete item: $e');
      return false;
    }
  }

  Future<bool> restoreItemToCamp(
    String id, {
    required String userId,
    required String userName,
    required String deviceId,
  }) async {
    if (_campId == null) return false;
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      final success = await _repository.restoreItemToCamp(
        id,
        campId: _campId!,
        userId: userId,
        userName: userName,
        deviceId: deviceId,
      );
      if (success) {
        await loadAll();
        if (!mounted) return true;
        state = state.copyWith(successMessage: 'Item restored to this camp');
        return true;
      }
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to restore item');
      return false;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to restore item: $e');
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

final activeVisitReasonsProvider = Provider<List<LookupItemModel>>((ref) {
  return ref.watch(masterLookupProvider).activeVisitReasons;
});

final activeChiefComplaintsProvider = Provider<List<LookupItemModel>>((ref) {
  return ref.watch(masterLookupProvider).activeChiefComplaints;
});
