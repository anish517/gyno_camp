import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/nepali_localization_service.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../../viewmodels/sync_viewmodel.dart';
import '../settings/postgres_settings_view.dart';

class SyncStatusView extends ConsumerStatefulWidget {
  const SyncStatusView({super.key});

  @override
  ConsumerState<SyncStatusView> createState() => _SyncStatusViewState();
}

class _SyncStatusViewState extends ConsumerState<SyncStatusView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncStateProvider.notifier).refreshPendingCounts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncStateProvider);
    final syncVm = ref.read(syncStateProvider.notifier);
    final authState = ref.watch(authStateProvider);
    final deviceState = ref.watch(deviceSecurityProvider);

    final deviceId = deviceState.device?.deviceId ?? 'dev-field';
    final userId = authState.currentUser?.id ?? 'usr-sync';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Sync Manager'),
        actions: [
          IconButton(
            tooltip: 'PostgreSQL Server Configuration',
            icon: const Icon(Icons.storage_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PostgresSettingsView()),
              );
            },
          ),
          IconButton(
            tooltip: 'Refresh Pending Counts',
            icon: const Icon(Icons.refresh),
            onPressed: () => syncVm.refreshPendingCounts(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Connectivity Status Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: syncState.isOnline ? AppTheme.successGreen : AppTheme.warningAmber,
                ),
              ),
              color: syncState.isOnline
                  ? AppTheme.successGreen.withValues(alpha: 0.08)
                  : AppTheme.warningAmber.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: syncState.isOnline ? AppTheme.successGreen : AppTheme.warningAmber,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        syncState.isOnline ? Icons.wifi : Icons.wifi_off,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            syncState.isOnline ? 'Online (अनलाइन)' : 'Offline (अफलाइन)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: syncState.isOnline ? AppTheme.successGreen : AppTheme.warningAmber,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            syncState.isOnline
                                ? 'Connected to Central Cloud. Auto-sync active.'
                                : 'Local SQLite Active. Records are safely stored in memory.',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
                          ),
                        ],
                      ),
                    ),
                    // Simulation toggle for field testing
                    Switch(
                      value: syncState.isOnline,
                      onChanged: (val) => syncVm.toggleConnectionSimulation(val),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Pending Records Counter Card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Unsynchronized Field Records',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: syncState.hasPendingRecords
                                ? AppTheme.warningAmber.withValues(alpha: 0.2)
                                : AppTheme.successGreen.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            syncState.hasPendingRecords
                                ? '${syncState.pendingTotalCount} PENDING'
                                : 'ALL SYNCED',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: syncState.hasPendingRecords
                                  ? AppTheme.warningAmber
                                  : AppTheme.successGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildCounterItem(
                          icon: Icons.person_outline,
                          count: syncState.pendingPatientsCount,
                          label: 'Patients',
                        ),
                        Container(height: 40, width: 1, color: AppTheme.borderLight),
                        _buildCounterItem(
                          icon: Icons.assignment_outlined,
                          count: syncState.pendingVisitsCount,
                          label: 'Clinical Visits',
                        ),
                        Container(height: 40, width: 1, color: AppTheme.borderLight),
                        _buildCounterItem(
                          icon: Icons.lock_outline,
                          count: syncState.pendingTotalCount,
                          label: 'Total Deltas',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 3. Action Buttons & Sync Trigger
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: syncState.isOnline ? AppTheme.primaryTeal : Colors.grey,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: syncState.isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(
                syncState.isSyncing
                    ? 'Synchronizing with Central Cloud...'
                    : syncState.isOnline
                        ? 'Synchronize Now (अहिले सिंक गर्नुहोस्)'
                        : 'Cannot Sync (Device is Offline)',
              ),
              onPressed: syncState.isSyncing || !syncState.isOnline
                  ? null
                  : () async {
                      final ok = await syncVm.syncNow(deviceId: deviceId, userId: userId);
                      if (context.mounted && ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Two-way sync completed successfully!'),
                            backgroundColor: AppTheme.successGreen,
                          ),
                        );
                      }
                    },
            ),

            if (syncState.errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.dangerRose.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.dangerRose),
                ),
                child: Text(
                  syncState.errorMessage!,
                  style: const TextStyle(color: AppTheme.dangerRose, fontSize: 13),
                ),
              ),
            ],

            if (syncState.lastSuccessMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.successGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.successGreen),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppTheme.successGreen, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        syncState.lastSuccessMessage!,
                        style: const TextStyle(color: AppTheme.successGreen, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // 4. Last Sync Metadata
            Card(
              child: ListTile(
                leading: const Icon(Icons.access_time, color: AppTheme.primaryTeal),
                title: const Text('Last Synchronization Timestamp', style: TextStyle(fontSize: 13)),
                subtitle: Text(
                  syncState.lastSyncedAt != null
                      ? NepaliLocalizationService.formatDualCalendarDate(syncState.lastSyncedAt!)
                      : 'Never synchronized yet on this device',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 5. Sync History Log
            const Text(
              'Sync History & Cloud Transmissions',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),

            syncState.history.isEmpty
                ? const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'No sync history recorded. Connect to network and tap "Synchronize Now".',
                        style: TextStyle(color: AppTheme.textSecondaryLight),
                      ),
                    ),
                  )
                : Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: syncState.history.take(5).length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = syncState.history[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            item.isSuccess ? Icons.cloud_done : Icons.cloud_off,
                            color: item.isSuccess ? AppTheme.successGreen : AppTheme.dangerRose,
                          ),
                          title: Text(
                            item.isSuccess
                                ? 'Uploaded ${item.totalPushed} records • Pulled ${item.campsPulled} updates'
                                : 'Sync Failed',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          subtitle: Text(
                            '${item.timestamp.hour}:${item.timestamp.minute.toString().padLeft(2, "0")} • ${item.errorMessage ?? "Success"}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildCounterItem({required IconData icon, required int count, required String label}) {
    return Column(
      children: [
        Icon(icon, size: 22, color: AppTheme.primaryTeal),
        const SizedBox(height: 6),
        Text(
          '$count',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
        ),
      ],
    );
  }
}
