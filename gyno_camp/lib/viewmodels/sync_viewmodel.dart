import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/central_api_service.dart';
import '../core/services/http_central_api_service.dart';
import '../core/services/network_connectivity_service.dart';
import '../core/services/session_service.dart';
import '../core/services/sse_sync_service.dart';
import '../models/sync_payload_model.dart';
import '../models/user_model.dart';
import '../repositories/ocr_repository.dart';
import '../repositories/sync_repository.dart';
import 'auth_viewmodel.dart';
import 'camp_viewmodel.dart';
import 'master_lookup_viewmodel.dart';
import 'ocr_scan_viewmodel.dart';
import 'patient_list_viewmodel.dart';

class SyncState {
  final bool isOnline;
  final bool isSyncing;
  final int pendingPatientsCount;
  final int pendingVisitsCount;
  final int pendingOfflineScansCount;
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
    this.pendingOfflineScansCount = 0,
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
    int? pendingOfflineScansCount,
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
      pendingOfflineScansCount: pendingOfflineScansCount ?? this.pendingOfflineScansCount,
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
  Timer? _periodicSyncTimer;
  final SseSyncService? _sseSyncService;

  String _lastKnownDeviceId =
      SessionService.current?.getRegisteredDeviceId() ?? 'dev-local';
  String _lastKnownUserId = 'usr-sync';

  final Ref? ref;

  SyncViewModel({
    required this.syncRepository,
    required INetworkConnectivityService connectivityService,
    this.ref,
    this._sseSyncService,
  })  : _connectivityService = connectivityService,
        super(SyncState(isOnline: connectivityService.isOnline)) {
    _init();
  }

  void _init() {
    refreshPendingCounts();
    _connectivitySub = _connectivityService.onConnectivityChanged.listen((online) {
      if (!mounted) return;
      final wasOffline = !state.isOnline;
      state = state.copyWith(
        isOnline: online,
        // Show a transient status message so the user knows what happened
        lastSuccessMessage: online
            ? (wasOffline ? '🟢 Reconnected — syncing data…' : null)
            : '🔴 Server offline — working locally.',
      );

      if (wasOffline && online) {
        debugPrint('[SyncVM] Network restored — triggering auto-sync.');
        // Cleanly reconnect the SSE stream (do NOT call dispose(), which permanently marks it disposed)
        _sseSyncService?.reconnect();
        // Fire a full sync cycle — this also refreshes camps/patients in UI
        syncNow(deviceId: _lastKnownDeviceId, userId: _lastKnownUserId);
      }
    });

    final isTesting = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTesting) {
      // Auto-trigger initial sync on app startup if connected
      if (state.isOnline) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted &&
              state.isOnline &&
              !state.isSyncing &&
              !HttpCentralApiService.hasActiveRequest) {
            syncNow(deviceId: _lastKnownDeviceId, userId: _lastKnownUserId);
          }
        });
      }

      // Periodic fallback sync every 15 seconds (skipped during active OCR/API requests)
      // SSE provides instant updates when available; this is the safety net
      _periodicSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted &&
            state.isOnline &&
            !state.isSyncing &&
            !HttpCentralApiService.hasActiveRequest) {
          syncNow(deviceId: _lastKnownDeviceId, userId: _lastKnownUserId);
        }
      });

      // Connect SSE for real-time push notifications
      _sseSyncService?.connect();
    }
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
        pendingOfflineScansCount: counts['offline_scans'] ?? 0,
        pendingTotalCount: counts['total'] ?? 0,
        lastSyncedAt: lastSync,
        history: hist,
      );
    } catch (e) {
      debugPrint('[SyncVM] refreshPendingCounts error: $e');
    }
  }

  String get lastKnownDeviceId => _lastKnownDeviceId;
  String get lastKnownUserId => _lastKnownUserId;

  void updateDeviceId(String deviceId) {
    final clean = deviceId.trim();
    if (clean.isEmpty || clean == _lastKnownDeviceId) return;
    _lastKnownDeviceId = clean;
    _sseSyncService?.updateDeviceId(clean);
  }

  Future<bool> syncNow({
    required String deviceId,
    required String userId,
    bool includeOfflineOcrQueue = false,
  }) async {
    _lastKnownDeviceId = deviceId;
    _lastKnownUserId = userId;
    _sseSyncService?.updateDeviceId(deviceId);

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
      // Queued Yellow Form OCR scans stay in the local queue until the operator
      // explicitly runs Bulk or One-by-One OCR sync (includeOfflineOcrQueue == true).
      int offlineScansSynced = 0;
      if (includeOfflineOcrQueue) {
        try {
          final ocrRepo = ref != null ? ref!.read(ocrRepositoryProvider) : OcrRepository();
          final pendingOffline = await ocrRepo.getPendingOfflineScanCount();
          if (pendingOffline > 0) {
            offlineScansSynced = await ocrRepo.syncAndProcessAllOfflineScans(
              defaultDeviceId: deviceId,
              defaultUserId: userId,
            );
            if (ref != null) {
              await ref!.read(ocrScanProvider.notifier).loadOfflineQueue();
            }
          }
        } catch (e) {
          debugPrint('[SyncVM] Offline scan queue sync note: $e');
        }
      }

      final result = await syncRepository.executeFullSyncCycle(
        deviceId: deviceId,
        userId: userId,
      );

      final hist = await syncRepository.getSyncHistory();
      final counts = await syncRepository.getPendingCounts();

      if (!mounted) return true;
      final offlineNote = offlineScansSynced > 0 ? ' ($offlineScansSynced offline scans extracted)' : '';
      state = state.copyWith(
        isSyncing: false,
        pendingPatientsCount: counts['patients'] ?? 0,
        pendingVisitsCount: counts['visits'] ?? 0,
        pendingOfflineScansCount: counts['offline_scans'] ?? 0,
        pendingTotalCount: counts['total'] ?? 0,
        lastSyncedAt: result.timestamp,
        history: hist,
        lastSuccessMessage:
            'Synced ${result.totalPushed} records uploaded, ${result.campsPulled} updates received.$offlineNote',
      );

      // Instantly refresh UI state across all screens silently without tearing down views
      final r = ref;
      if (r != null) {
        try {
          await r.read(campStateProvider.notifier).loadCamps(silent: true);
          final patientState = r.read(patientListProvider);
          final currentFilterCampId = patientState.filters.campId;
          final user = r.read(authStateProvider).currentUser;
          final isSuperAdmin = user != null &&
              (user.isSuperAdmin || user.role == UserRole.superAdmin);
          final visibleCampIds = !isSuperAdmin && user != null
              ? r
                  .read(campStateProvider)
                  .camps
                  .where((c) =>
                      c.isStaffAssigned(user.id) ||
                      user.assignedCampIds.contains(c.id))
                  .map((c) => c.id)
                  .toSet()
              : null;
          final activeCampId = isSuperAdmin
              ? (r.read(userActiveCampProvider)?.id ??
                  r.read(campStateProvider).activeCamp?.id)
              : r.read(userActiveCampProvider)?.id;

          final isFilterValid = currentFilterCampId != null &&
              currentFilterCampId.isNotEmpty &&
              (isSuperAdmin ||
                  (currentFilterCampId != 'all' &&
                      (visibleCampIds?.contains(currentFilterCampId) ?? false)));
          final isLoadedValid = patientState.loadedCampId != null &&
              patientState.loadedCampId!.isNotEmpty &&
              (isSuperAdmin ||
                  (visibleCampIds?.contains(patientState.loadedCampId!) ?? false));

          final campToReload = isFilterValid
              ? currentFilterCampId
              : (isLoadedValid ? patientState.loadedCampId : activeCampId);

          if (campToReload != null) {
            await r.read(patientListProvider.notifier).loadPatients(campToReload, true);
          }
          r.read(masterLookupProvider.notifier).loadAll(silent: true);
        } catch (_) {}
      }

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
    _periodicSyncTimer?.cancel();
    _connectivitySub?.cancel();
    _sseSyncService?.dispose();
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
  if (HttpCentralApiService.isServerConfigured) {
    return HttpCentralApiService();
  }
  return CentralApiService();
});

final syncRepositoryProvider = Provider<ISyncRepository>((ref) {
  final api = ref.watch(centralApiServiceProvider);
  return SyncRepository(centralApiService: api);
});

final syncStateProvider = StateNotifierProvider<SyncViewModel, SyncState>((ref) {
  final repo = ref.watch(syncRepositoryProvider);
  final net = ref.watch(networkConnectivityProvider);

  // Create SSE service that triggers instant sync on server events
  final initialDeviceId =
      SessionService.current?.getRegisteredDeviceId() ?? 'dev-local';
  late final SyncViewModel vm;
  final sseService = SseSyncService(
    apiService: HttpCentralApiService(),
    deviceId: initialDeviceId,
    onSyncEvent: (eventData) {
      debugPrint('[SyncVM] SSE event received, triggering instant sync...');
      vm.syncNow(deviceId: vm.lastKnownDeviceId, userId: vm.lastKnownUserId);
    },
  );

  vm = SyncViewModel(
    syncRepository: repo,
    connectivityService: net,
    ref: ref,
    sseSyncService: sseService,
  );

  ref.onDispose(() => sseService.dispose());
  return vm;
});
