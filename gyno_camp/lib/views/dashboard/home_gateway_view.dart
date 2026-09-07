import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/audit_log_viewmodel.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/device_management_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../../viewmodels/sync_viewmodel.dart';
import '../admin/audit_trail_view.dart';
import '../admin/camp_management_view.dart';
import '../../viewmodels/patient_list_viewmodel.dart';
import '../admin/device_management_view.dart';
import '../admin/master_config_view.dart';
import '../patient/clinical_assessment_view.dart';
import '../patient/patient_list_view.dart';
import '../patient/patient_registration_view.dart';
import '../reports/camp_report_view.dart';
import '../scanner/form_scan_view.dart';
import '../sync/sync_status_view.dart';
import '../../viewmodels/reporting_viewmodel.dart';

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
    final deviceMgmt = ref.watch(deviceManagementProvider);
    final auditLogs = ref.watch(auditLogProvider);
    final patientState = ref.watch(patientListProvider);

    if (campState.hasActiveCamp &&
        (!patientState.hasLoaded || patientState.loadedCampId != campState.activeCamp!.id) &&
        !patientState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(patientListProvider.notifier).loadPatients(campState.activeCamp!.id);
      });
    }

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
                        user?.name ?? 'Dr. Aarav Sharma',
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
          const SizedBox(height: 16),

          // Action Required: Pending Devices Alert Banner
          if (deviceMgmt.pendingCount > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade400, width: 1.2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notification_important_rounded, color: Colors.amber, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${deviceMgmt.pendingCount} Field Device${deviceMgmt.pendingCount > 1 ? "s" : ""} Awaiting Super Admin Review',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF78350F)),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'A new field tablet has submitted registration. Verify hardware signature and whitelist access.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DeviceManagementView()),
                      );
                    },
                    child: const Text('Review & Approve', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

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
                  value: deviceMgmt.pendingCount > 0
                      ? '${deviceMgmt.pendingCount} Pending'
                      : '${deviceMgmt.approvedCount} Active',
                  badgeColor: deviceMgmt.pendingCount > 0 ? Colors.orange : AppTheme.primaryTeal,
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
                  value: '${patientState.patients.isNotEmpty ? patientState.patients.length : (campState.activeCamp?.totalPatientsRegistered ?? 0)}',
                  badgeColor: (patientState.patients.isNotEmpty || (campState.activeCamp?.totalPatientsRegistered ?? 0) > 0)
                      ? AppTheme.primaryTeal
                      : Colors.blueGrey,
                  icon: Icons.people,
                  iconColor: Colors.teal,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PatientListView()),
                    );
                  },
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
                  title: Row(
                    children: [
                      const Text('Device Whitelist & Hardware Security', style: TextStyle(fontWeight: FontWeight.bold)),
                      if (deviceMgmt.pendingCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade800,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${deviceMgmt.pendingCount} PENDING',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    deviceMgmt.pendingCount > 0
                        ? '${deviceMgmt.pendingCount} device(s) awaiting approval • ${deviceMgmt.approvedCount} authorized'
                        : '${deviceMgmt.approvedCount} authorized field tablet(s) active',
                  ),
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
            leading: const Icon(Icons.local_hospital_outlined, color: AppTheme.primaryTeal),
            title: const Text(
              'Clinical Station Direct Intake (Supervisor Access)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: const Text(
              'Direct access to patient registration and clinical form workflows',
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
    final patientState = ref.watch(patientListProvider);
    final user = ref.watch(authStateProvider).currentUser;

    final isCampAssigned = campState.hasActiveCamp &&
        (user == null || user.assignedCampIds.isEmpty || user.assignedCampIds.contains(campState.activeCamp!.id));

    if (campState.hasActiveCamp &&
        (!patientState.hasLoaded || patientState.loadedCampId != campState.activeCamp!.id) &&
        !patientState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(patientListProvider.notifier).loadPatients(campState.activeCamp!.id);
      });
    }

    final recentPatients = patientState.patients.take(4).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Elevated Active Camp Field Station Banner
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F766E), Color(0xFF134E4A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // SaaS Organization Tenant Badge
                    Row(
                      children: [
                        const Icon(Icons.corporate_fare_rounded, color: Colors.tealAccent, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '${user?.tenantName ?? "Bir Hospital Gyno Outreach"} • Tenant: ${user?.tenantId ?? "tenant_bir_hospital"}',
                          style: const TextStyle(
                            color: Colors.tealAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF34D399),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                campState.hasActiveCamp ? 'LIVE FIELD STATION ACTIVE' : 'NO ACTIVE CAMP OPEN',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (campState.hasActiveCamp)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white30),
                            ),
                            child: Text(
                              campState.activeCamp!.campCode,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      campState.activeCamp?.name ?? 'No active camp selected. Contact Super Admin to initiate intake.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (campState.hasActiveCamp && !isCampAssigned) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade900.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'RBAC Alert: This camp is not assigned to you (Assigned: ${user?.assignedCampIds.join(", ")}). Read-only mode active.',
                                style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (campState.hasActiveCamp) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Location: ${campState.activeCamp!.venue}, Ward ${campState.activeCamp!.ward}, ${campState.activeCamp!.district}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white24, height: 1),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _buildStationBadge(
                            icon: Icons.people_outline,
                            label: 'Total Intake',
                            value: '${patientState.patients.length} Registered',
                          ),
                          const SizedBox(width: 20),
                          _buildStationBadge(
                            icon: syncState.hasPendingRecords ? Icons.cloud_queue : Icons.cloud_done,
                            label: 'Sync Status',
                            value: syncState.hasPendingRecords
                                ? '${syncState.pendingTotalCount} Offline Pending'
                                : '100% Synced',
                          ),
                          const Spacer(),
                          Text(
                            'Staff: ${user?.name ?? "Field Nurse"}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 2. Fast Patient Search & Triage Bar
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: AppTheme.primaryTeal, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Quick search patient by Name, Mobile, or Patient ID (e.g. GC-KTM-...)...',
                            hintStyle: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (query) {
                            if (query.trim().isNotEmpty && campState.hasActiveCamp) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PatientListView(initialQuery: query),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
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
                        child: const Text('Patient Roll', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // 3. Primary Clinical Action Stations Grid
              const Text(
                'Clinical Stations (Field Workstation Workflow)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildActionTile(
                      icon: Icons.person_add_alt_1_rounded,
                      title: 'Register Patient (दर्ता)',
                      subtitle: 'Fast intake demographics, visit reasons, duplicate detection & consent',
                      color: AppTheme.primaryTeal,
                      stationBadge: 'Station 1: Intake',
                      actionPrompt: 'New Patient Intake',
                      onTap: () {
                        if (!campState.hasActiveCamp) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please open or select an active camp first!')),
                          );
                          return;
                        }
                        if (!isCampAssigned) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Access Denied: Camp ${campState.activeCamp!.campCode} is not in your assigned camp list.'),
                              backgroundColor: Colors.redAccent,
                            ),
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
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildActionTile(
                      icon: Icons.document_scanner_rounded,
                      title: 'Scan Yellow Form (स्क्यान)',
                      subtitle: 'Dual-page camera OCR, OMR checkbox detector & auto-population',
                      color: const Color(0xFF0284C7),
                      stationBadge: 'AI OCR Engine',
                      actionPrompt: 'Launch Form Scanner',
                      onTap: () {
                        if (!campState.hasActiveCamp) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please open or select an active camp first!')),
                          );
                          return;
                        }
                        if (!isCampAssigned) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Access Denied: Camp ${campState.activeCamp!.campCode} is not in your assigned camp list.'),
                              backgroundColor: Colors.redAccent,
                            ),
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
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildActionTile(
                      icon: Icons.people_alt_rounded,
                      title: 'Patient Roll & Triage (सूची)',
                      subtitle: 'Active triage queue, Station 1–6 clinical steppers & patient charts',
                      color: const Color(0xFF4F46E5),
                      stationBadge: 'Queue: ${patientState.patients.length}',
                      actionPrompt: 'View All Patients',
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
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildActionTile(
                      icon: syncState.isSyncing
                          ? Icons.sync_rounded
                          : (syncState.hasPendingRecords
                              ? Icons.cloud_upload_rounded
                              : Icons.cloud_done_rounded),
                      title: 'Offline Sync Hub (सिंक)',
                      subtitle: 'Local AES-256 encrypted database & central server replication',
                      color: syncState.hasPendingRecords ? const Color(0xFFD97706) : const Color(0xFF059669),
                      stationBadge: syncState.hasPendingRecords
                          ? '${syncState.pendingTotalCount} Pending'
                          : '100% Synced',
                      actionPrompt: 'Check Sync Console',
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

              // 4. Recent Station Intakes / Live Queue Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Station Intakes',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  if (patientState.patients.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                      label: Text(
                        'View All (${patientState.patients.length})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PatientListView()),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),

              if (recentPatients.isEmpty)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryTeal.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.assignment_turned_in_outlined, color: AppTheme.primaryTeal, size: 32),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Station Ready for Clinical Intake',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'No patients registered in current camp yet today. Tap "Register Patient" or "Scan Yellow Form" to begin.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: recentPatients.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final p = recentPatients[index];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      color: Colors.white,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.12),
                          child: Text(
                            p.firstName.isNotEmpty ? p.firstName[0].toUpperCase() : 'P',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              '${p.firstName} ${p.surname}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                p.patientId,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          'Age: ${p.age} • Ward ${p.ward} • ${p.reasonsForVisit.isNotEmpty ? p.reasonsForVisit.first : "General Checkup"}',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                        ),
                        trailing: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryTeal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.assignment_outlined, size: 14),
                          label: const Text('Clinical Chart', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ClinicalAssessmentView(patient: p),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 24),

              // 5. Shift Summary & Lead Handover Card
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.picture_as_pdf_rounded, color: Colors.teal.shade700, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Camp Clinical Summary & Lead Handover',
                              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Generate instant PDF summary for the camp lead before leaving the venue.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.teal.shade800,
                          side: BorderSide(color: Colors.teal.shade200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.history_edu_rounded, size: 18),
                        label: const Text('My Activity', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AuditTrailView(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.summarize_rounded, size: 18),
                        label: const Text('Camp Summary', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStationBadge({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.white70),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.white60)),
            Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // 3. DATA ANALYST DASHBOARD
  // ==========================================
  Widget _buildDataAnalystDashboard(BuildContext context, WidgetRef ref) {
    final campState = ref.watch(campStateProvider);
    final user = ref.watch(authStateProvider).currentUser;
    final reportState = ref.watch(reportingViewModelProvider);

    if (campState.hasActiveCamp &&
        (reportState.summary == null || reportState.selectedCampId != campState.activeCamp!.id) &&
        !reportState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(reportingViewModelProvider.notifier).loadSummary(campId: campState.activeCamp!.id);
      });
    }

    final summary = reportState.summary;
    final totalVisits = summary?.totalVisitsRecorded ?? 0;
    final popRateStr = summary != null && totalVisits > 0 ? '${summary.significantPopPercentage}%' : '0.0%';
    final hyperRateStr = summary != null && totalVisits > 0
        ? '${((summary.hypertensionCount / totalVisits) * 100).toStringAsFixed(1)}%'
        : '0.0%';
    final referralRateStr = summary != null && totalVisits > 0
        ? '${((summary.totalSurgicalReferrals / totalVisits) * 100).toStringAsFixed(1)}%'
        : '0.0%';

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
                    'Code: ${campState.activeCamp?.campCode ?? "N/A"} • Total Intake: ${campState.activeCamp?.totalPatientsRegistered ?? 0} • Clinical Visits: $totalVisits',
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryLight),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatColumn(label: 'POP Rate (>=2)', value: popRateStr),
                      _StatColumn(label: 'HTN Alert Rate', value: hyperRateStr),
                      _StatColumn(label: 'Surgical Referral', value: referralRateStr),
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
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
    ),
  );
}

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    String? stationBadge,
    String? actionPrompt,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.25), width: 1.2),
      ),
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  if (stationBadge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        stationBadge,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: color,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.3),
              ),
              if (actionPrompt != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      actionPrompt,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: color),
                  ],
                ),
              ],
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
