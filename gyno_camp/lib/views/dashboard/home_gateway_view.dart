import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database_service.dart';
import '../../core/services/file_download_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../models/audit_log_model.dart';
import '../../models/user_model.dart';
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
import '../admin/user_management_view.dart';
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
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. EXECUTIVE COMMAND HEADER WITH LIVE PULSE & QUICK ACTIONS
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF042F2E), Color(0xFF0F766E), Color(0xFF134E4A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF042F2E).withValues(alpha: 0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Sub-Row: Live Status Pulse + Tenant Badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fiber_manual_record, color: Color(0xFF34D399), size: 10),
                              SizedBox(width: 6),
                              Text(
                                'SECURE ROOT SESSION ACTIVE',
                                style: TextStyle(
                                  color: Color(0xFF6EE7B7),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${campState.activeCamp?.organizationName ?? user?.tenantName ?? "Nepal Health Outreach"} • Tenant: ${user?.tenantId ?? "tenant_default"}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Middle Main Row: User Identity & Action Buttons
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF14B8A6), Color(0xFF0D9488)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                          ),
                          child: const Icon(Icons.shield_outlined, color: Colors.white, size: 30),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      user?.name ?? 'System Administrator',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: -0.4,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: Color(0xFF5EEAD4), size: 18),
                                    tooltip: 'Edit SaaS Profile & Organization',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _showEditProfileDialog(context, ref, user),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'Super Admin Command Console • Field Operations & Clinical Governance',
                                style: TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF14B8A6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 2,
                              ),
                              icon: const Icon(Icons.add_location_alt_rounded, size: 17),
                              label: const Text('New Camp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const CampManagementView()),
                                );
                              },
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.4), width: 1.2),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                              label: const Text('Switch Camp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                              onPressed: () => _showQuickCampSwitchDialog(context, ref),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 2. ACTION REQUIRED ALERT (IF FIELD DEVICES ARE PENDING REVIEW)
              if (deviceMgmt.pendingCount > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFCD34D), width: 1.3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.devices_other_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${deviceMgmt.pendingCount} Field Tablet${deviceMgmt.pendingCount > 1 ? "s" : ""} Awaiting Hardware Whitelist Approval',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF78350F)),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'New field workstations have submitted OTP verification challenges. Review hardware signatures before intake begins.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD97706),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 1,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const DeviceManagementView()),
                          );
                        },
                        child: const Text('Review Devices', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // 3. EXECUTIVE TELEMETRY & KPI METRICS (RESPONSIVE GRID)
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final isWide = constraints.maxWidth > 850;
                  final isMedium = constraints.maxWidth > 550;
                  final cardWidth = isWide
                      ? (constraints.maxWidth - 48) / 4
                      : isMedium
                          ? (constraints.maxWidth - 16) / 2
                          : constraints.maxWidth;

                  return Wrap(
                    spacing: 16,
                    runSpacing: 14,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: _buildExecutiveMetricCard(
                          label: 'Camp Operations',
                          value: campState.hasActiveCamp ? '1 Live Active' : '0 Live Open',
                          subtitle: '${campState.camps.length} total scheduled camps',
                          icon: Icons.campaign_rounded,
                          accentColor: const Color(0xFF0F766E),
                          trailingBadge: campState.hasActiveCamp
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFA7F3D0)),
                                  ),
                                  child: const Text('LIVE', style: TextStyle(color: Color(0xFF059669), fontSize: 10, fontWeight: FontWeight.bold)),
                                )
                              : null,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const CampManagementView()),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildExecutiveMetricCard(
                          label: 'Hardware Security',
                          value: '${deviceMgmt.approvedCount} Authorized',
                          subtitle: deviceMgmt.pendingCount > 0
                              ? '${deviceMgmt.pendingCount} device(s) pending review'
                              : 'All hardware whitelisted',
                          icon: Icons.devices_rounded,
                          accentColor: const Color(0xFF4338CA),
                          trailingBadge: deviceMgmt.pendingCount > 0
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFFCD34D)),
                                  ),
                                  child: Text('${deviceMgmt.pendingCount} PENDING', style: const TextStyle(color: Color(0xFFB45309), fontSize: 9.5, fontWeight: FontWeight.bold)),
                                )
                              : null,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const DeviceManagementView()),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildExecutiveMetricCard(
                          label: 'Intake Throughput',
                          value: '${patientState.patients.length} Registered',
                          subtitle: campState.hasActiveCamp
                              ? 'Active camp patient roll'
                              : '${patientState.patients.length} historical records',
                          icon: Icons.people_alt_rounded,
                          accentColor: const Color(0xFF0D9488),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const PatientListView()),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildExecutiveMetricCard(
                          label: 'Cryptographic Ledger',
                          value: 'SHA-256 Verified',
                          subtitle: '${auditLogs.logs.length} chained blocks anchored',
                          icon: Icons.verified_user_rounded,
                          accentColor: const Color(0xFF10B981),
                          trailingBadge: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFA7F3D0)),
                            ),
                            child: const Text('OK', style: TextStyle(color: Color(0xFF059669), fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const AuditTrailView()),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // 4. ACTIVE CAMP SPOTLIGHT & SUPERVISOR FIELD WORKSTATION HUB
              _buildActiveCampSpotlight(context, ref, campState, patientState),
              const SizedBox(height: 28),

              // 5. ADMINISTRATIVE CONTROL MODULES (2-COLUMN / 3-COLUMN GRID)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Administrative Governance & Master Controls',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: -0.2),
                  ),
                  Text(
                    '6 System Modules Active',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              LayoutBuilder(
                builder: (ctx, constraints) {
                  final isWide = constraints.maxWidth > 750;
                  final itemWidth = isWide ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth;

                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: itemWidth,
                        child: _buildAdminModuleCard(
                          context: context,
                          icon: Icons.calendar_month_rounded,
                          title: 'Camp Lifecycle & Interactive Calendar',
                          description: 'Schedule outreach camps, enforce single-active camp sessions, view monthly calendar & assign staff rosters.',
                          badgeText: campState.hasActiveCamp ? 'Active: ${campState.activeCamp!.campCode}' : '${campState.camps.length} Camps',
                          badgeColor: const Color(0xFF0F766E),
                          accentColor: const Color(0xFF0F766E),
                          actionPrompt: 'Manage Camp Roster',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const CampManagementView()),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _buildAdminModuleCard(
                          context: context,
                          icon: Icons.devices_rounded,
                          title: 'Field Hardware Whitelist & Terminal Security',
                          description: 'Deterministic SHA-256 hardware signatures, 6-digit cryptographic OTP verification & terminal app lockouts.',
                          badgeText: deviceMgmt.pendingCount > 0 ? '${deviceMgmt.pendingCount} PENDING' : '${deviceMgmt.approvedCount} Active Tablets',
                          badgeColor: deviceMgmt.pendingCount > 0 ? const Color(0xFFD97706) : const Color(0xFF4338CA),
                          accentColor: const Color(0xFF4338CA),
                          actionPrompt: 'Manage Whitelist',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const DeviceManagementView()),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _buildAdminModuleCard(
                          context: context,
                          icon: Icons.badge_rounded,
                          title: 'Staff & Personnel Directory (RBAC)',
                          description: 'Provision staff credentials, station role permissions, password/PIN resets & camp roster assignments.',
                          badgeText: 'RBAC Active',
                          badgeColor: const Color(0xFF0D9488),
                          accentColor: const Color(0xFF0D9488),
                          actionPrompt: 'Staff Directory',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const UserManagementView()),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _buildAdminModuleCard(
                          context: context,
                          icon: Icons.tune_rounded,
                          title: 'Clinical Master Data & Formulary',
                          description: 'Dynamic diagnoses, Yellow Form dropdown values, medicine formulary & referral hospital directories with EN/NE bilingual support.',
                          badgeText: 'Bilingual Formulary',
                          badgeColor: const Color(0xFF0284C7),
                          accentColor: const Color(0xFF0284C7),
                          actionPrompt: 'Configure Formularies',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const MasterConfigView()),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _buildAdminModuleCard(
                          context: context,
                          icon: Icons.analytics_rounded,
                          title: 'Executive Reports & Cohort Analytics',
                          description: 'POP prolapse staging breakdown, cervical inspection metrics, 1-tap branded PDF clinical summary & full dataset Excel export.',
                          badgeText: 'PDF & Excel Ready',
                          badgeColor: const Color(0xFF7E22CE),
                          accentColor: const Color(0xFF7E22CE),
                          actionPrompt: 'Generate Reports',
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
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _buildAdminModuleCard(
                          context: context,
                          icon: Icons.lock_clock_rounded,
                          title: 'Tamper-Evident System Audit Ledger',
                          description: 'Cryptographically chained event ledger, immutable SHA-256 verification & downloadable JSON compliance proof.',
                          badgeText: '${auditLogs.logs.length} Chained Blocks',
                          badgeColor: const Color(0xFF334155),
                          accentColor: const Color(0xFF334155),
                          actionPrompt: 'Inspect Audit Log',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const AuditTrailView()),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),

              // 6. DISASTER RECOVERY & 1-TAP SYSTEM ACTIONS DOCK
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.storage_rounded, color: Color(0xFF334155), size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Disaster Recovery & Data Export Operations',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Safeguard clinical records with 1-tap local database snapshots and proof-of-work audit exports.',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0F766E),
                            side: const BorderSide(color: Color(0xFF0F766E)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.download_rounded, size: 16),
                          label: const Text('Export Audit Log', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                          onPressed: () => _exportAuditLogs(context, auditLogs.logs),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.backup_table_rounded, size: 16),
                          label: const Text('Database Backup', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                          onPressed: () => _exportDatabaseBackup(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // 7. LIVE AUDIT ACTIVITY FEED
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Live System Activity & Cryptographic Log',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
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
              const SizedBox(height: 10),
              _buildAuditFeedCard(context, auditLogs.logs),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // SUPER ADMIN HELPER WIDGETS & METHODS
  // ==========================================
  Widget _buildActiveCampSpotlight(
    BuildContext context,
    WidgetRef ref,
    CampState campState,
    PatientListState patientState,
  ) {
    if (!campState.hasActiveCamp) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.campaign_outlined, color: Colors.amber.shade900, size: 28),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Active Clinical Camp Session In Progress',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Activate a scheduled camp session from your roster to begin recording patient intake and clinical exams.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: const Text('Open Camp Session'),
              onPressed: () => _showQuickCampSwitchDialog(context, ref),
            ),
          ],
        ),
      );
    }

    final camp = campState.activeCamp!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Code + Live Badge + Switch action
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F766E), Color(0xFF134E4A)],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      camp.campCode,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.fiber_manual_record, color: Color(0xFF059669), size: 10),
                        SizedBox(width: 5),
                        Text(
                          'LIVE OPERATIONAL STATION',
                          style: TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.w700, fontSize: 10.5, letterSpacing: 0.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F766E),
                  side: const BorderSide(color: Color(0xFF0F766E)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.swap_horiz_rounded, size: 15),
                label: const Text('Switch Camp', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: () => _showQuickCampSwitchDialog(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Camp Name
          Text(
            camp.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: -0.3),
          ),
          const SizedBox(height: 8),

          // Location & logistics pills
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on_rounded, size: 15, color: Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Text(
                    '${camp.venue}, Ward ${camp.ward}, ${camp.municipality.isNotEmpty ? "${camp.municipality}, " : ""}${camp.district}',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.date_range_rounded, size: 15, color: Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Text(
                    '${_formatDate(camp.startDate)} – ${_formatDate(camp.endDate)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.badge_rounded, size: 15, color: Color(0xFF0F766E)),
                  const SizedBox(width: 4),
                  Text(
                    '${camp.assignedStaffIds.length} Staff Assigned',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF0F766E), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 16),

          // Sub-Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Clinical Field Workstations (Supervisor Access)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155), letterSpacing: 0.2),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${patientState.patients.length} Intakes Recorded',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3 Field Workstation Action Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildSupervisorActionCard(
                    context: context,
                    width: isWide ? (constraints.maxWidth - 24) / 3 : constraints.maxWidth,
                    icon: Icons.person_add_alt_1_rounded,
                    iconColor: const Color(0xFF0F766E),
                    iconBgColor: const Color(0xFFCCFBF1),
                    badgeText: 'STATION 1: INTAKE',
                    badgeColor: const Color(0xFF0F766E),
                    title: 'Register Patient',
                    description: 'Demographics, triage vitals & official barcode token slip generation',
                    onTap: () {
                      if (!campState.hasActiveCamp) {
                        _showNoCampAlert(context);
                        return;
                      }
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PatientRegistrationView()));
                    },
                  ),
                  _buildSupervisorActionCard(
                    context: context,
                    width: isWide ? (constraints.maxWidth - 24) / 3 : constraints.maxWidth,
                    icon: Icons.document_scanner_rounded,
                    iconColor: const Color(0xFF4338CA),
                    iconBgColor: const Color(0xFFE0E7FF),
                    badgeText: 'AI SCAN ENGINE',
                    badgeColor: const Color(0xFF4338CA),
                    title: 'Scan Yellow Form',
                    description: 'Dual-page camera OCR & OMR checkbox auto-digitization for Page 1 & 2',
                    onTap: () {
                      if (!campState.hasActiveCamp) {
                        _showNoCampAlert(context);
                        return;
                      }
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const FormScanView()));
                    },
                  ),
                  _buildSupervisorActionCard(
                    context: context,
                    width: isWide ? (constraints.maxWidth - 24) / 3 : constraints.maxWidth,
                    icon: Icons.assignment_ind_rounded,
                    iconColor: const Color(0xFF7E22CE),
                    iconBgColor: const Color(0xFFF3E8FF),
                    badgeText: 'CHARTS & QUEUE',
                    badgeColor: const Color(0xFF7E22CE),
                    title: 'Patient Roll & Charts',
                    description: '6-station clinical exam records, POP-Q staging & PDF follow-up slips',
                    onTap: () {
                      if (!campState.hasActiveCamp) {
                        _showNoCampAlert(context);
                        return;
                      }
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PatientListView()));
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildExecutiveMetricCard({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    VoidCallback? onTap,
    Widget? trailingBadge,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.1),
      ),
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: accentColor, size: 20),
                  ),
                  if (trailingBadge != null)
                    trailingBadge
                  else
                    Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.grey.shade400),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF94A3B8),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminModuleCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required String badgeText,
    required Color badgeColor,
    required Color accentColor,
    required String actionPrompt,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
      ),
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: accentColor.withValues(alpha: 0.03),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [accentColor.withValues(alpha: 0.18), accentColor.withValues(alpha: 0.08)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: accentColor.withValues(alpha: 0.25)),
                        ),
                        child: Icon(icon, color: accentColor, size: 24),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: badgeColor.withValues(alpha: 0.28)),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF64748B),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    actionPrompt,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 14, color: accentColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuickCampSwitchDialog(BuildContext context, WidgetRef ref) {
    final campState = ref.read(campStateProvider);
    final user = ref.read(authStateProvider).currentUser;
    final deviceState = ref.read(deviceSecurityProvider);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryTeal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.swap_horiz_rounded, color: AppTheme.primaryTeal),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Switch Active Field Camp', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Activates the selected camp for all staff intake sessions', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: campState.camps.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No camps configured yet. Please schedule a new camp first.'),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: campState.camps.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (dialogCtx, index) {
                      final camp = campState.camps[index];
                      final isCurrent = camp.id == campState.activeCamp?.id;
                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isCurrent ? AppTheme.primaryTeal : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            camp.campCode,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: isCurrent ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        title: Text(camp.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('${camp.venue}, Ward ${camp.ward}, ${camp.district}', style: const TextStyle(fontSize: 11)),
                        trailing: isCurrent
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.successGreen.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppTheme.successGreen.withValues(alpha: 0.3)),
                                ),
                                child: const Text(
                                  'ACTIVE',
                                  style: TextStyle(color: AppTheme.successGreen, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              )
                            : OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  final success = await ref.read(campStateProvider.notifier).openCamp(
                                        camp.id,
                                        adminUserId: user?.id ?? 'admin-root',
                                        deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                                      );
                                  if (context.mounted && success) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Switched active camp to "${camp.name}" (${camp.campCode})'),
                                        backgroundColor: AppTheme.successGreen,
                                      ),
                                    );
                                  }
                                },
                                child: const Text('Set Active', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAuditFeedCard(BuildContext context, List<AuditLogModel> logs) {
    if (logs.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        color: Colors.white,
        child: const Padding(
          padding: EdgeInsets.all(24.0),
          child: Center(child: Text('No system audit events recorded yet.')),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: Colors.white,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: logs.take(4).length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
        itemBuilder: (context, index) {
          final log = logs[index];
          final categoryColor = _getAuditCategoryColor(log.action);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.history_rounded, size: 18, color: categoryColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: categoryColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _extractCategoryTag(log.action),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: categoryColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              log.action,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'By: ${log.userName} • ${log.timestamp.hour.toString().padLeft(2, "0")}:${log.timestamp.minute.toString().padLeft(2, "0")} (${_formatDate(log.timestamp)})',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    log.logHash.length >= 8 ? log.logHash.substring(0, 8) : log.logHash,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _getAuditCategoryColor(String action) {
    final upper = action.toUpperCase();
    if (upper.contains('CAMP')) return const Color(0xFF0F766E);
    if (upper.contains('DEVICE') || upper.contains('SECURITY') || upper.contains('LOCK')) return const Color(0xFF4338CA);
    if (upper.contains('USER') || upper.contains('STAFF')) return const Color(0xFF0D9488);
    if (upper.contains('PATIENT') || upper.contains('INTAKE') || upper.contains('ASSESSMENT')) return const Color(0xFF10B981);
    if (upper.contains('REPORT') || upper.contains('EXPORT')) return const Color(0xFF7E22CE);
    return const Color(0xFF64748B);
  }

  String _extractCategoryTag(String action) {
    final upper = action.toUpperCase();
    if (upper.contains('CAMP')) return 'CAMP';
    if (upper.contains('DEVICE') || upper.contains('SECURITY')) return 'SECURITY';
    if (upper.contains('USER') || upper.contains('STAFF')) return 'STAFF';
    if (upper.contains('PATIENT') || upper.contains('INTAKE')) return 'CLINICAL';
    if (upper.contains('REPORT') || upper.contains('EXPORT')) return 'REPORT';
    return 'SYSTEM';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _exportDatabaseBackup(BuildContext context) async {
    try {
      final snapshot = await DatabaseService().exportDatabaseSnapshot();
      final jsonString = const JsonEncoder.withIndent('  ').convert(snapshot);
      final bytes = utf8.encode(jsonString);
      final dateStr = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final filename = 'gynocamp_backup_$dateStr.json';
      await FileDownloadHelper.saveAndDownloadFile(
        bytes: bytes,
        filename: filename,
        mimeType: 'application/json',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Database backup exported successfully: $filename'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup failed: $e'),
            backgroundColor: AppTheme.dangerRose,
          ),
        );
      }
    }
  }

  Future<void> _exportAuditLogs(BuildContext context, List<AuditLogModel> logs) async {
    if (logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No audit logs available to export.')),
      );
      return;
    }
    try {
      final list = logs.map((l) => l.toMap()).toList();
      final jsonString = const JsonEncoder.withIndent('  ').convert(list);
      final bytes = utf8.encode(jsonString);
      final dateStr = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final filename = 'audit_trail_export_$dateStr.json';
      await FileDownloadHelper.saveAndDownloadFile(
        bytes: bytes,
        filename: filename,
        mimeType: 'application/json',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Audit trail exported successfully: $filename'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppTheme.dangerRose,
          ),
        );
      }
    }
  }

  // ==========================================
  // 2. DATA TAKER (FIELD NURSE / CLERK) DASHBOARD
  // ==========================================
  Widget _buildDataTakerDashboard(BuildContext context, WidgetRef ref) {
    final campState = ref.watch(campStateProvider);
    final syncState = ref.watch(syncStateProvider);
    final patientState = ref.watch(patientListProvider);
    final user = ref.watch(authStateProvider).currentUser;

    final isSuperAdmin = user?.role == UserRole.superAdmin;
    final isCampAssigned = campState.hasActiveCamp &&
        (isSuperAdmin ||
            (user != null &&
                (campState.activeCamp!.isStaffAssigned(user.id) ||
                    user.assignedCampIds.contains(campState.activeCamp!.id))));

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
                    // Dynamic Organization / Tenant Badge
                    Row(
                      children: [
                        const Icon(Icons.corporate_fare_rounded, color: Colors.tealAccent, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${campState.activeCamp?.organizationName ?? user?.tenantName ?? "Community Health Outreach"} • Tenant: ${user?.tenantId ?? "tenant_default"}',
                            style: const TextStyle(
                              color: Colors.tealAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
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
                                decoration: BoxDecoration(
                                  color: campState.hasActiveCamp ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
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
                      campState.activeCamp?.name ?? 'No Active Field Camp In Session',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (!campState.hasActiveCamp) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'There is currently no open clinical camp scheduled for patient intake. Please contact your Camp Supervisor or Super Admin to activate a camp session.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                    if (campState.hasActiveCamp && !isCampAssigned) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade900.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.gpp_maybe_rounded, color: Colors.amberAccent, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Access Restricted: Your staff account is not assigned to this field camp roster (${campState.activeCamp!.campCode}). Contact your Camp Lead to update roster assignment before recording data.',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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
                            'Staff: ${user?.name ?? "Field Staff"}',
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
                  user?.name ?? 'Data Analyst',
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

  Widget _buildSupervisorActionCard({
    required BuildContext context,
    required double width,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String badgeText,
    required Color badgeColor,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: iconColor.withValues(alpha: 0.22), width: 1.2),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  iconBgColor.withValues(alpha: 0.20),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: iconBgColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: iconColor, size: 22),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: badgeColor.withValues(alpha: 0.3), width: 0.8),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                    height: 1.35,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Launch Station',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: iconColor),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNoCampAlert(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.campaign_outlined, color: AppTheme.warningAmber, size: 40),
        title: const Text('No Active Camp Open'),
        content: const Text(
          'Direct supervisor clinical intake requires an active camp station. Please open or schedule a camp from the Camp Lifecycle management view.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Go to Camp Management'),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CampManagementView()),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context, WidgetRef ref, UserModel? user) {
    if (user == null) return;
    final nameCtrl = TextEditingController(text: user.name);
    final tenantCtrl = TextEditingController(text: user.tenantName);
    final phoneCtrl = TextEditingController(text: user.phone);
    final deviceState = ref.read(deviceSecurityProvider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.business_center_outlined, color: Color(0xFF0F766E), size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('SaaS Profile & Tenant Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Configure your admin identity & organization details', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Administrator / User Name *',
                    hintText: 'e.g. System Administrator or Dr. Jane Doe',
                    prefixIcon: Icon(Icons.person_outline, size: 18),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: tenantCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Organization / Tenant Name *',
                    hintText: 'e.g. Nepal Health Outreach Network',
                    prefixIcon: Icon(Icons.corporate_fare_outlined, size: 18),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Contact Phone Number',
                    hintText: 'e.g. 9851000001',
                    prefixIcon: Icon(Icons.phone_outlined, size: 18),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Color(0xFF16A34A)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tenant ID: ${user.tenantId} • Role: ${user.role.displayNameEn}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              final newTenant = tenantCtrl.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter an administrator name.')),
                );
                return;
              }
              final updated = user.copyWith(
                name: newName,
                tenantName: newTenant.isNotEmpty ? newTenant : user.tenantName,
                phone: phoneCtrl.text.trim(),
              );

              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);

              final success = await ref.read(authStateProvider.notifier).updateProfile(
                updatedUser: updated,
                deviceId: deviceState.device?.deviceId ?? 'dev-admin',
              );

              if (success) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Updated profile to "$newName" ($newTenant).')),
                );
              }
            },
            child: const Text('Save Profile'),
          ),
        ],
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
