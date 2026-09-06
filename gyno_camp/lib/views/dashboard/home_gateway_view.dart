import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/audit_log_viewmodel.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../../viewmodels/sync_viewmodel.dart';
import '../patient/patient_list_view.dart';
import '../patient/patient_registration_view.dart';
import '../sync/sync_status_view.dart';

class HomeGatewayView extends ConsumerWidget {
  const HomeGatewayView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.currentUser;
    final campState = ref.watch(campStateProvider);
    final campVm = ref.read(campStateProvider.notifier);
    final deviceState = ref.watch(deviceSecurityProvider);
    final auditLogs = ref.watch(auditLogProvider);
    final syncState = ref.watch(syncStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user?.name ?? 'Gynocamp Field System'),
            Text(
              'Role: ${user?.role.displayNameEn ?? "Staff"} | Device: ${deviceState.device?.deviceName ?? "Active"}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Lock App Session',
            icon: const Icon(Icons.lock_outline),
            onPressed: () {
              ref.read(deviceSecurityProvider.notifier).lockApp();
            },
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(authStateProvider.notifier).logout(
                    deviceId: deviceState.device?.deviceId ?? 'dev-local',
                  );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Active Camp Card
            Card(
              elevation: 2,
              color: campState.hasActiveCamp ? AppTheme.primaryLight.withValues(alpha: 0.4) : Colors.amber.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: campState.hasActiveCamp ? AppTheme.primaryTeal : Colors.amber.shade400,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              campState.hasActiveCamp ? Icons.campaign : Icons.warning_amber_rounded,
                              color: campState.hasActiveCamp ? AppTheme.primaryTeal : Colors.amber.shade800,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              campState.hasActiveCamp ? 'ACTIVE CAMP IN PROGRESS' : 'NO OPEN CAMP',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 0.8,
                                color: campState.hasActiveCamp ? AppTheme.primaryDark : Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                        if (campState.hasActiveCamp)
                          Chip(
                            label: Text(
                              campState.activeCamp!.campCode,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      campState.activeCamp?.name ?? 'Data entry requires an active, open camp.',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (campState.hasActiveCamp) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Location: ${campState.activeCamp!.venue}, Ward ${campState.activeCamp!.ward}, ${campState.activeCamp!.district}',
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryLight),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Registered Patients: ${campState.activeCamp!.totalPatientsRegistered}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primaryDark),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Role-Specific Sections:
            // 1. DATA TAKER ACTIONS
            if (user?.canEnterClinicalData == true) ...[
              const Text(
                'Field Data Collection (Offline Enabled)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildActionTile(
                      icon: Icons.person_add_alt_1,
                      title: 'Register Patient',
                      subtitle: 'Auto Patient ID',
                      color: AppTheme.primaryTeal,
                      onTap: () {
                        if (!campState.hasActiveCamp) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please open or select an active camp first!')),
                          );
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PatientRegistrationView()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionTile(
                      icon: Icons.document_scanner_outlined,
                      title: 'Scan Yellow Form',
                      subtitle: 'OCR & Auto-Fill',
                      color: AppTheme.accentCyan,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Scan & Auto-Fill scheduled for Phase 5')),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildActionTile(
                      icon: Icons.people_outline,
                      title: 'Patient Roll',
                      subtitle: 'View Camp Patients',
                      color: Colors.blueGrey,
                      onTap: () {
                        if (!campState.hasActiveCamp) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please open or select an active camp first!')),
                          );
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PatientListView()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionTile(
                      icon: syncState.isSyncing
                          ? Icons.sync
                          : (syncState.hasPendingRecords
                              ? Icons.cloud_upload_outlined
                              : Icons.cloud_done_outlined),
                      title: 'Sync Status',
                      subtitle: syncState.hasPendingRecords
                          ? '${syncState.pendingTotalCount} Pending Upload'
                          : 'Fully Synced',
                      color: syncState.hasPendingRecords
                          ? AppTheme.warningAmber
                          : AppTheme.successGreen,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SyncStatusView()),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // 2. SUPER ADMIN ACTIONS
            if (user?.isSuperAdmin == true) ...[
              const Text(
                'Super Admin Controls',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.campaign_outlined, color: AppTheme.primaryTeal),
                      title: const Text('Camp Lifecycle & Calendar'),
                      subtitle: Text('${campState.camps.length} camps configured'),
                      trailing: campState.hasActiveCamp
                          ? OutlinedButton(
                              onPressed: () {
                                campVm.closeCamp(
                                  campState.activeCamp!.id,
                                  adminUserId: user!.id,
                                  deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                                );
                              },
                              child: const Text('Close Camp'),
                            )
                          : ElevatedButton(
                              onPressed: () {
                                if (campState.camps.isNotEmpty) {
                                  campVm.openCamp(
                                    campState.camps.first.id,
                                    adminUserId: user!.id,
                                    deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                                  );
                                }
                              },
                              child: const Text('Open Camp'),
                            ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.devices, color: Colors.indigo),
                      title: const Text('Device Activations & Security'),
                      subtitle: const Text('Review OTP and approve field hardware'),
                      trailing: const Chip(
                        label: Text('1 Verified', style: TextStyle(fontSize: 11)),
                        backgroundColor: AppTheme.primaryLight,
                      ),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Device authorization active.')),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.edit_note, color: Colors.teal),
                      title: const Text('Custom Dropdowns & Medicine List'),
                      subtitle: const Text('Manage diagnoses, medicines, hospitals'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Dynamic Lookup Items ready.')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 3. DATA ANALYST & REPORTING
            if (user?.canExportReports == true) ...[
              const Text(
                'Reporting & Analytics',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('One-Tap PDF Report'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('One-Tap PDF Export engine scheduled for Phase 6')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.table_view),
                      label: const Text('Export Excel'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Excel summary generator scheduled for Phase 6')),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // Activity Audit Log Section (Tamper-evident log)
            const Text(
              'System Activity Log (Tamper-Evident)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: auditLogs.logs.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No activity recorded yet in local database.'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: auditLogs.logs.take(5).length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final log = auditLogs.logs[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.history, size: 20, color: AppTheme.primaryTeal),
                          title: Text(
                            log.action,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: Text(
                            'User: ${log.userName} • ${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, "0")}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Text(
                            log.logHash.substring(0, 8),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.grey),
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

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
