import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/audit_log_viewmodel.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../../viewmodels/sync_viewmodel.dart';
import '../admin/audit_trail_view.dart';
import '../admin/camp_management_view.dart';
import '../admin/device_management_view.dart';
import '../admin/master_config_view.dart';
import '../patient/patient_list_view.dart';
import '../patient/patient_registration_view.dart';
import '../reports/camp_report_view.dart';
import '../scanner/form_scan_view.dart';
import '../sync/sync_status_view.dart';

class HomeGatewayView extends ConsumerWidget {
  const HomeGatewayView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.currentUser;
    final deviceState = ref.watch(deviceSecurityProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user?.name ?? 'Gynocamp System'),
            Text(
              '${user?.role.displayNameEn ?? "Staff"} • ${deviceState.device?.deviceName ?? "Authorized Device"}',
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
      body: user?.isSuperAdmin == true
          ? _buildSuperAdminDashboard(context, ref)
          : user?.isDataAnalyst == true
              ? _buildDataAnalystDashboard(context, ref)
              : _buildDataTakerDashboard(context, ref),
    );
  }

  // ==========================================
  // 1. SUPER ADMIN DASHBOARD
  // ==========================================
  Widget _buildSuperAdminDashboard(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).currentUser;
    final campState = ref.watch(campStateProvider);
    final deviceState = ref.watch(deviceSecurityProvider);
    final auditLogs = ref.watch(auditLogProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Admin Welcome Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF134E4A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SUPER ADMIN COMMAND CENTER',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.name ?? 'Dr. Aruna Shrestha',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Full governance: Camp scheduling, device approvals & master data',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // High-Level Management KPI Cards
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  label: 'Camp Status',
                  value: campState.hasActiveCamp ? '1 Active' : '0 Open',
                  badgeColor: campState.hasActiveCamp ? AppTheme.successGreen : Colors.orange,
                  icon: Icons.campaign,
                  iconColor: AppTheme.primaryTeal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  label: 'Field Devices',
                  value: '1 Verified',
                  badgeColor: AppTheme.primaryTeal,
                  icon: Icons.devices,
                  iconColor: Colors.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  label: 'Patients Registered',
                  value: '${campState.activeCamp?.totalPatientsRegistered ?? 0}',
                  badgeColor: Colors.blueGrey,
                  icon: Icons.people,
                  iconColor: Colors.teal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  label: 'Audit Integrity',
                  value: 'SHA-256 OK',
                  badgeColor: AppTheme.successGreen,
                  icon: Icons.verified_user,
                  iconColor: AppTheme.successGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Primary Admin Management Modules
          const Text(
            'Administrative Controls',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.campaign_outlined, color: AppTheme.primaryTeal),
                  ),
                  title: const Text('Camp Lifecycle & Calendar', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    campState.hasActiveCamp
                        ? 'Active: ${campState.activeCamp!.name} (${campState.activeCamp!.campCode})'
                        : '${campState.camps.length} camps configured (No open camp)',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CampManagementView()),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.devices, color: Colors.indigo),
                  ),
                  title: const Text('Device Whitelist & Hardware Security', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Current Device: ${deviceState.device?.deviceName ?? "Tablet"} (Approved)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DeviceManagementView()),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.tune, color: Colors.teal),
                  ),
                  title: const Text('Clinical Master Data & Formulary', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Dynamic diagnoses, Yellow Form dropdowns, and medicine formulary'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MasterConfigView()),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.assessment_outlined, color: Colors.purple),
                  ),
                  title: const Text('Reports & Camp Aggregations', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('One-Tap PDF Camp Summary & Full Dataset Excel Export'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CampReportView(
                          initialCampId: campState.activeCamp?.id,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Secondary: Field Access Sandbox
          ExpansionTile(
            initiallyExpanded: false,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: Colors.white,
            collapsedBackgroundColor: Colors.white,
            leading: const Icon(Icons.science_outlined, color: Colors.blueGrey),
            title: const Text(
              'Field Station Simulation (Optional)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: const Text(
              'Access patient registration and clinical forms for verification',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.person_add),
                        label: const Text('Register Patient'),
                        onPressed: () {
                          if (!campState.hasActiveCamp) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please open a camp first')),
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
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.document_scanner_outlined),
                        label: const Text('Scan Form'),
                        onPressed: () {
                          if (!campState.hasActiveCamp) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please open a camp first')),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const FormScanView()),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.people_alt_outlined),
                        label: const Text('Patient Roll'),
                        onPressed: () {
                          if (!campState.hasActiveCamp) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please open a camp first')),
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
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Tamper-Evident System Audit Trail
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tamper-Evident System Audit Trail',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 14),
                label: Text(
                  '${auditLogs.logs.length} Events (View All)',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AuditTrailView()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: auditLogs.logs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No activity recorded yet.'),
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
                          'By: ${log.userName} • ${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, "0")}',
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
    );
  }

  // ==========================================
  // 2. DATA TAKER (FIELD NURSE / CLERK) DASHBOARD
  // ==========================================
  Widget _buildDataTakerDashboard(BuildContext context, WidgetRef ref) {
    final campState = ref.watch(campStateProvider);
    final syncState = ref.watch(syncStateProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Active Camp Field Banner
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
                            campState.hasActiveCamp ? 'CAMP FIELD STATION ACTIVE' : 'NO OPEN CAMP',
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
                    campState.activeCamp?.name ?? 'Please contact Super Admin to open a camp before intake.',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (campState.hasActiveCamp) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Location: ${campState.activeCamp!.venue}, Ward ${campState.activeCamp!.ward}, ${campState.activeCamp!.district}',
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryLight),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Patients Registered: ${campState.activeCamp!.totalPatientsRegistered}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Primary Clinical Action Grid
          const Text(
            'Field Operations (Offline Enabled)',
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
                    if (!campState.hasActiveCamp) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please open or select an active camp first!')),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const FormScanView()),
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
                  subtitle: 'Station Queue & Clinical',
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
                  color: syncState.hasPendingRecords ? AppTheme.warningAmber : AppTheme.successGreen,
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

          // Quick Camp Summary For Staff
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Camp Summary & Reports',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Generate instant PDF summary for the camp lead before leaving the venue.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('View Camp Summary'),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CampReportView(
                              initialCampId: campState.activeCamp?.id,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 3. DATA ANALYST DASHBOARD
  // ==========================================
  Widget _buildDataAnalystDashboard(BuildContext context, WidgetRef ref) {
    final campState = ref.watch(campStateProvider);
    final user = ref.watch(authStateProvider).currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Analyst Header Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF312E81), Color(0xFF4338CA)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.analytics_outlined, color: Colors.white, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'ANALYTICS & EPIDEMIOLOGY HUB',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  user?.name ?? 'Dr. Rajesh Kumar',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Statistical summaries, cross-camp disease prevalence & export engine',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Primary Export Center
          const Text(
            'Camp Export & Reports Engine',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('One-Tap PDF Report'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CampReportView(
                          initialCampId: campState.activeCamp?.id,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.table_view),
                  label: const Text('Export Excel Dataset'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CampReportView(
                          initialCampId: campState.activeCamp?.id,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Selected Camp Statistics Preview
          const Text(
            'Camp Indicators & Metrics',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    campState.activeCamp?.name ?? 'No active camp selected',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Code: ${campState.activeCamp?.campCode ?? "N/A"} • Total Intake: ${campState.activeCamp?.totalPatientsRegistered ?? 0}',
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryLight),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatColumn(label: 'POP Rate', value: '42.8%'),
                      _StatColumn(label: 'VIA+ Screen', value: '8.5%'),
                      _StatColumn(label: 'Surgical Referral', value: '14.2%'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SHARED REUSABLE COMPONENTS
  // ==========================================
  Widget _buildMetricCard({
    required String label,
    required String value,
    required Color badgeColor,
    required IconData icon,
    required Color iconColor,
  }) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ],
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

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;

  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
        ),
      ],
    );
  }
}
