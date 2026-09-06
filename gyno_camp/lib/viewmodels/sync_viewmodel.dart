import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/central_api_service.dart';
import '../core/services/network_connectivity_service.dart';
import '../models/sync_payload_model.dart';
import '../repositories/sync_repository.dart';

class SyncState {
  final bool isOnline;
  final bool isSyncing;
  final int pendingPatientsCount;
  final int pendingVisitsCount;
  final int pendingTotalCount;
  final DateTime? lastSyncedAt;
  final String? errorMessage;
  final String? lastSuccessMessage;
  final List<SyncHistoryItem> history;

  const SyncState({
    this.isOnline = true,
    this.isSyncing = false,
    this.pendingPatientsCount = 0,
    this.pendingVisitsCount = 0,
    this.pendingTotalCount = 0,
    this.lastSyncedAt,
    this.errorMessage,
    this.lastSuccessMessage,
    this.history = const [],
  });

  bool get hasPendingRecords => pendingTotalCount > 0;
  bool get isFullySynced => pendingTotalCount == 0 && !isSyncing;

  SyncState copyWith({
    bool? isOnline,
    bool? isSyncing,
    int? pendingPatientsCount,
    int? pendingVisitsCount,
    int? pendingTotalCount,
    DateTime? lastSyncedAt,
    String? errorMessage,
    String? lastSuccessMessage,
    List<SyncHistoryItem>? history,
    bool clearError = false,
  }) {
    return SyncState(
      isOnline: isOnline ?? this.isOnline,
      isSyncing: isSyncing ?? this.isSyncing,
      pendingPatientsCount: pendingPatientsCount ?? this.pendingPatientsCount,
      pendingVisitsCount: pendingVisitsCount ?? this.pendingVisitsCount,
      pendingTotalCount: pendingTotalCount ?? this.pendingTotalCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastSuccessMessage: lastSuccessMessage ?? this.lastSuccessMessage,
      history: history ?? this.history,
    );
  }
}

class SyncViewModel extends StateNotifier<SyncState> {
  final ISyncRepository syncRepository;
  final INetworkConnectivityService _connectivityService;
  StreamSubscription<bool>? _connectivitySub;

  String _lastKnownDeviceId = 'dev-field';
  String _lastKnownUserId = 'usr-sync';

  SyncViewModel({
    required this.syncRepository,
    required INetworkConnectivityService connectivityService,
  })  : _connectivityService = connectivityService,
        super(SyncState(isOnline: connectivityService.isOnline)) {
    _init();
  }

  void _init() {
    refreshPendingCounts();
    _connectivitySub = _connectivityService.onConnectivityChanged.listen((online) {
      final wasOffline = !state.isOnline;
      state = state.copyWith(isOnline: online);

      // Auto-trigger sync upon reconnecting to internet
      if (wasOffline && online) {
        syncNow(deviceId: _lastKnownDeviceId, userId: _lastKnownUserId);
      }
    });
  }

  Future<void> refreshPendingCounts() async {
    try {
      final counts = await syncRepository.getPendingCounts();
      final lastSync = await syncRepository.getLastSyncedAt();
      final hist = await syncRepository.getSyncHistory();

      if (!mounted) return;
      state = state.copyWith(
        pendingPatientsCount: counts['patients'] ?? 0,
        pendingVisitsCount: counts['visits'] ?? 0,
        pendingTotalCount: counts['total'] ?? 0,
        lastSyncedAt: lastSync,
        history: hist,
      );
    } catch (_) {}
  }

  Future<bool> syncNow({required String deviceId, required String userId}) async {
    _lastKnownDeviceId = deviceId;
    _lastKnownUserId = userId;

    if (!state.isOnline) {
      if (mounted) {
        state = state.copyWith(
          errorMessage: 'Cannot synchronize: Device is in offline mode.',
        );
      }
      return false;
    }

    if (state.isSyncing) return false;

    state = state.copyWith(isSyncing: true, clearError: true);

    try {
      final result = await syncRepository.executeFullSyncCycle(
        deviceId: deviceId,
        userId: userId,
      );

      final hist = await syncRepository.getSyncHistory();
      final counts = await syncRepository.getPendingCounts();

      if (!mounted) return true;
      state = state.copyWith(
        isSyncing: false,
        pendingPatientsCount: counts['patients'] ?? 0,
        pendingVisitsCount: counts['visits'] ?? 0,
        pendingTotalCount: counts['total'] ?? 0,
        lastSyncedAt: result.timestamp,
        history: hist,
        lastSuccessMessage: 'Synced ${result.totalPushed} records uploaded, ${result.campsPulled} updates received.',
      );

      return true;
    } catch (e) {
      final hist = await syncRepository.getSyncHistory();
      if (!mounted) return false;
      state = state.copyWith(
        isSyncing: false,
        errorMessage: 'Sync failed: $e',
        history: hist,
      );
      return false;
    }
  }

  void toggleConnectionSimulation(bool online) {
    _connectivityService.setOnline(online);
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }
}

// Providers
final networkConnectivityProvider = Provider<INetworkConnectivityService>((ref) {
  final service = NetworkConnectivityService();
  ref.onDispose(() => service.dispose());
  return service;
});

final centralApiServiceProvider = Provider<ICentralApiService>((ref) {
  return CentralApiService();
});

final syncRepositoryProvider = Provider<ISyncRepository>((ref) {
  final api = ref.watch(centralApiServiceProvider);
  return SyncRepository(centralApiService: api);
});

final syncStateProvider = StateNotifierProvider<SyncViewModel, SyncState>((ref) {
  final repo = ref.watch(syncRepositoryProvider);
  final net = ref.watch(networkConnectivityProvider);
  return SyncViewModel(syncRepository: repo, connectivityService: net);
});
