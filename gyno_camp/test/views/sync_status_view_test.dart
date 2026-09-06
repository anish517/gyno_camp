import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/services/network_connectivity_service.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/sync_payload_model.dart';
import 'package:gyno_camp/repositories/sync_repository.dart';
import 'package:gyno_camp/viewmodels/sync_viewmodel.dart';
import 'package:gyno_camp/views/sync/sync_status_view.dart';

class FakeSyncRepository implements ISyncRepository {
  int pendingPatients = 0;
  int pendingVisits = 0;
  DateTime? lastSync;
  final List<SyncHistoryItem> history = [];

  @override
  Future<Map<String, int>> getPendingCounts() async {
    return {
      'patients': pendingPatients,
      'visits': pendingVisits,
      'total': pendingPatients + pendingVisits,
    };
  }

  @override
  Future<SyncPushResponse> pushDelta({required String deviceId, required String userId}) async {
    return SyncPushResponse(success: true, serverTimestamp: DateTime.now());
  }

  @override
  Future<SyncPullResponse> pullDelta({required String deviceId, required String userId}) async {
    return SyncPullResponse(success: true, serverTimestamp: DateTime.now());
  }

  @override
  Future<SyncHistoryItem> executeFullSyncCycle({
    required String deviceId,
    required String userId,
  }) async {
    pendingPatients = 0;
    pendingVisits = 0;
    lastSync = DateTime.now();
    final item = SyncHistoryItem(
      id: 'item-01',
      timestamp: lastSync!,
      patientsPushed: 1,
      visitsPushed: 0,
      auditLogsPushed: 1,
      campsPulled: 1,
      isSuccess: true,
    );
    history.insert(0, item);
    return item;
  }

  @override
  Future<List<SyncHistoryItem>> getSyncHistory() async => history;

  @override
  Future<DateTime?> getLastSyncedAt() async => lastSync;
}

void main() {
  group('SyncStatusView Widget Tests', () {
    late FakeSyncRepository fakeSyncRepo;
    late NetworkConnectivityService connectivityService;

    setUp(() {
      fakeSyncRepo = FakeSyncRepository();
      connectivityService = NetworkConnectivityService(initialOnline: true);
    });

    tearDown(() {
      connectivityService.dispose();
    });

    testWidgets('renders connectivity status, pending counters, and sync button', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkConnectivityProvider.overrideWithValue(connectivityService),
            syncRepositoryProvider.overrideWithValue(fakeSyncRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const SyncStatusView(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Offline Sync Manager'), findsOneWidget);
      expect(find.text('Online (अनलाइन)'), findsOneWidget);
      expect(find.text('Unsynchronized Field Records'), findsOneWidget);
      expect(find.text('ALL SYNCED'), findsOneWidget);
      expect(find.text('Synchronize Now (अहिले सिंक गर्नुहोस्)'), findsOneWidget);
    });

    testWidgets('toggling switch simulates offline mode and updates UI badge', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkConnectivityProvider.overrideWithValue(connectivityService),
            syncRepositoryProvider.overrideWithValue(fakeSyncRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const SyncStatusView(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Offline (अफलाइन)'), findsOneWidget);
      expect(find.text('Cannot Sync (Device is Offline)'), findsOneWidget);
    });

    testWidgets('displays pending count when unsynced records exist and syncNow clears it', (WidgetTester tester) async {
      fakeSyncRepo.pendingPatients = 1;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkConnectivityProvider.overrideWithValue(connectivityService),
            syncRepositoryProvider.overrideWithValue(fakeSyncRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const SyncStatusView(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('1 PENDING'), findsOneWidget);

      final syncBtnFinder = find.text('Synchronize Now (अहिले सिंक गर्नुहोस्)');
      expect(syncBtnFinder, findsOneWidget);
      await tester.tap(syncBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('ALL SYNCED'), findsOneWidget);
      expect(find.text('Two-way sync completed successfully!'), findsOneWidget);
    });
  });
}
