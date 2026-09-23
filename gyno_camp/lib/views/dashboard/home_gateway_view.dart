import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database_service.dart';
import '../../core/database/database_tables.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/services/file_download_helper.dart';
import '../../core/services/session_service.dart';
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
import '../../models/camp_model.dart';
import '../../models/camp_report_summary_model.dart';
import '../../models/clinical_visit_model.dart';
import '../../models/patient_model.dart';
import '../reports/camp_report_view.dart';
import '../scanner/form_scan_view.dart';
import '../sync/sync_status_view.dart';
import '../../viewmodels/reporting_viewmodel.dart';
import '../../viewmodels/patient_registration_viewmodel.dart';

class HomeGatewayView extends ConsumerWidget {
  const HomeGatewayView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.currentUser;
    final deviceState = ref.watch(deviceSecurityProvider);

    if (authState.isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.primaryTeal),
              SizedBox(height: 16),
              Text(
                'Verifying authorized role terminal...',
                style: TextStyle(color: AppTheme.textSecondaryLight, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // Guard: Prevent premature dashboard render or flash during session termination
    if (!authState.isAuthenticated || user == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user.name.isNotEmpty ? user.name : 'Gynocamp System',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            Text(
              '${user.role.displayNameEn} • ${deviceState.device?.deviceName ?? "Authorized Device"}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
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
            tooltip: 'Logout / Sign Out',
            icon: const Icon(Icons.logout),
            onPressed: () {
              showDialog(
                context: context,
                builder: (dialogCtx) => AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.logout, color: AppTheme.dangerRose),
                      SizedBox(width: 8),
                      Text('Confirm Sign Out'),
                    ],
                  ),
                  content: Text(
                    'Are you sure you want to sign out of "${user.name}"? This will terminate your active clinical session and return to the Staff Login screen.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.dangerRose,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        // 1. Dismiss confirmation dialog
                        Navigator.pop(dialogCtx);

                        // 2. Pop any nested/pushed routes back to the root SecurityGatewayView
                        if (context.mounted) {
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        }

                        // 3. Clear session and update authStateProvider to unauthenticated
                        await ref.read(authStateProvider.notifier).logout(
                              deviceId: deviceState.device?.deviceId ?? 'dev-local',
                            );

                        // SecurityGatewayView is the reactive root of MaterialApp.
                        // When authState.isAuthenticated is false, it automatically renders
                        // LoginView smoothly without route duplication or glitch animations.
                      },
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: switch (user.role) {
        UserRole.superAdmin => _buildSuperAdminDashboard(context, ref),
        UserRole.dataAnalyst => _buildDataAnalystDashboard(context, ref),
        UserRole.dataTaker => _buildDataTakerDashboard(context, ref),
      },
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
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
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
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
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
                              Flexible(
                                child: Text(
                                  'SECURE ROOT SESSION ACTIVE',
                                  style: TextStyle(
                                    color: Color(0xFF6EE7B7),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            final savedOrg = SessionService.current?.getOrganizationName();
                            final tenantName = (savedOrg != null && savedOrg.trim().isNotEmpty)
                                ? savedOrg
                                : user?.tenantName;
                            final orgName = (tenantName != null &&
                                    tenantName.trim().isNotEmpty &&
                                    tenantName != 'Outreach Health Center')
                                ? tenantName
                                : (campState.activeCamp?.organizationName ?? 'Nepal Health Outreach Network');
                            return Text(
                              orgName,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Middle Main Row: User Identity & Action Buttons (Responsive)
                    LayoutBuilder(
                      builder: (ctx, constraints) {
                        final isCompact = constraints.maxWidth < 680;
                        final actionButtons = Wrap(
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
                        );

                        if (isCompact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
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
                                    child: const Icon(Icons.shield_outlined, color: Colors.white, size: 26),
                                  ),
                                  const SizedBox(width: 12),
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
                                                  fontSize: 19,
                                                  fontWeight: FontWeight.w900,
                                                  color: Colors.white,
                                                  letterSpacing: -0.4,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              icon: const Icon(Icons.edit_outlined, color: Color(0xFF5EEAD4), size: 18),
                                              tooltip: 'Edit SaaS Profile & Organization',
                                              visualDensity: VisualDensity.compact,
                                              onPressed: () => _showEditProfileDialog(context, ref, user),
                                            ),
                                          ],
                                        ),
                                        const Text(
                                          'Super Admin Command Console',
                                          style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              actionButtons,
                            ],
                          );
                        }

                        return Row(
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
                            const SizedBox(width: 16),
                            actionButtons,
                          ],
                        );
                      },
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
                  child: LayoutBuilder(
                    builder: (ctx, constraints) {
                      final isCompact = constraints.maxWidth < 580;
                      final reviewBtn = ElevatedButton(
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
                      );

                      if (isCompact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF59E0B),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.devices_other_rounded, color: Colors.white, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${deviceMgmt.pendingCount} Field Tablet${deviceMgmt.pendingCount > 1 ? "s" : ""} Awaiting Whitelist',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF78350F)),
                                      ),
                                      const SizedBox(height: 2),
                                      const Text(
                                        'Review hardware signatures before intake begins.',
                                        style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(width: double.infinity, child: reviewBtn),
                          ],
                        );
                      }

                      return Row(
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
                          reviewBtn,
                        ],
                      );
                    },
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
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
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
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final isCompact = constraints.maxWidth < 680;
                    final actionButtons = Wrap(
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
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4338CA),
                            side: const BorderSide(color: Color(0xFF4338CA)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.settings_backup_restore_rounded, size: 16),
                          label: const Text('Restore Database', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                          onPressed: () => _showRestoreDatabaseDialog(context, ref),
                        ),
                      ],
                    );

                    if (isCompact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE2E8F0),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.storage_rounded, color: Color(0xFF334155), size: 22),
                              ),
                              const SizedBox(width: 12),
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
                                      'Safeguard clinical records with 1-tap local snapshots and proof-of-work exports.',
                                      style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          actionButtons,
                        ],
                      );
                    }

                    return Row(
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
                        actionButtons,
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),

              // 7. LIVE AUDIT ACTIVITY FEED
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Live System Activity & Cryptographic Log',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        ),
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final isCompact = constraints.maxWidth < 600;
            final openCampBtn = ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: const Text('Open Camp Session'),
              onPressed: () => _showQuickCampSwitchDialog(context, ref),
            );

            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.campaign_outlined, color: Colors.amber.shade900, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No Active Clinical Camp Session In Progress',
                              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Activate a scheduled camp session from your roster to begin recording patient intake and clinical exams.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: openCampBtn),
                ],
              );
            }

            return Row(
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
                openCampBtn,
              ],
            );
          },
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
          // Header: Code + Live Badge + Switch action (Responsive Wrap)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fiber_manual_record, color: Color(0xFF059669), size: 10),
                    SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'LIVE OPERATIONAL STATION',
                        style: TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.w700, fontSize: 10.5, letterSpacing: 0.3),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
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
                  Flexible(
                    child: Text(
                      '${camp.venue}, Ward ${camp.ward}, ${camp.municipality.isNotEmpty ? "${camp.municipality}, " : ""}${camp.district}',
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.date_range_rounded, size: 15, color: Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${_formatDate(camp.startDate)} – ${_formatDate(camp.endDate)}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.badge_rounded, size: 15, color: Color(0xFF0F766E)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${camp.assignedStaffIds.length} Staff Assigned',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF0F766E), fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
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
              const Expanded(
                child: Text(
                  'Active Camp Operations & Roster Governance',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155), letterSpacing: 0.2),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
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

          // 4 Operational Governance & Intelligence Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              final cardWidth = isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildSupervisorActionCard(
                    context: context,
                    width: cardWidth,
                    icon: Icons.assignment_ind_rounded,
                    iconColor: const Color(0xFF0F766E),
                    iconBgColor: const Color(0xFFCCFBF1),
                    badgeText: 'STAFF ROSTER',
                    badgeColor: const Color(0xFF0F766E),
                    title: 'Camp Staff Assignments',
                    description: 'Provision field nurses, gynecologists & assign clinical roles to ${camp.campCode}',
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CampManagementView()));
                    },
                  ),
                  _buildSupervisorActionCard(
                    context: context,
                    width: cardWidth,
                    icon: Icons.devices_other_rounded,
                    iconColor: const Color(0xFF4338CA),
                    iconBgColor: const Color(0xFFE0E7FF),
                    badgeText: 'SECURITY WHITELIST',
                    badgeColor: const Color(0xFF4338CA),
                    title: 'Authorize Camp Hardware',
                    description: 'Manage SHA-256 hardware fingerprints & active field tablets for this camp',
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceManagementView()));
                    },
                  ),
                  _buildSupervisorActionCard(
                    context: context,
                    width: cardWidth,
                    icon: Icons.tune_rounded,
                    iconColor: const Color(0xFF7E22CE),
                    iconBgColor: const Color(0xFFF3E8FF),
                    badgeText: 'FORMULARY & CONFIG',
                    badgeColor: const Color(0xFF7E22CE),
                    title: 'Clinical Protocols & Master Data',
                    description: 'Configure standard medication formularies, wards, and diagnosis dropdowns',
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const MasterConfigView()));
                    },
                  ),
                  _buildSupervisorActionCard(
                    context: context,
                    width: cardWidth,
                    icon: Icons.analytics_rounded,
                    iconColor: const Color(0xFF0D9488),
                    iconBgColor: const Color(0xFFCCFBF1),
                    badgeText: 'EPIDEMIOLOGY & CHARTS',
                    badgeColor: const Color(0xFF0D9488),
                    title: 'Data Analyst Workstation',
                    description: 'Cross-camp POP staging charts, chief complaint ranking, age demographics & clinical dossiers',
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const DataAnalystWorkstationPage()));
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final isCompact = constraints.maxWidth < 520;
                final overrideBtn = TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('Clinical Override', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _showSupervisorClinicalOverrideDialog(context, campState),
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.verified_user_outlined, size: 18, color: Color(0xFF64748B)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Clinical Intake & OCR Scanner are restricted to designated Data Taker consoles.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: overrideBtn,
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 18, color: Color(0xFF64748B)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Clinical Intake & OCR Scanner are restricted to designated Data Taker consoles.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ),
                    overrideBtn,
                  ],
                );
              },
            ),
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
                      const SizedBox(width: 8),
                      Flexible(
                        child: Container(
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
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
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
                  Flexible(
                    child: Text(
                      actionPrompt,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
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
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SizedBox(
              width: double.maxFinite,
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

  void _showRestoreDatabaseDialog(BuildContext context, WidgetRef ref) {
    final jsonCtrl = TextEditingController();
    Map<String, dynamic>? parsedSnapshot;
    String? validationError;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final tables = parsedSnapshot?['tables'] as Map<String, dynamic>?;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4338CA).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.settings_backup_restore_rounded, color: Color(0xFF4338CA)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Restore Database Snapshot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('Merge / restore offline clinical records from backup JSON', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 550),
              child: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Paste the JSON content of a previously exported "gynocamp_backup_*.json" file below:',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: jsonCtrl,
                      maxLines: 7,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      decoration: InputDecoration(
                        hintText: '{\n  "exported_at": "...",\n  "tables": {\n    "camps": [...],\n    "patients": [...]\n  }\n}',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        errorText: validationError,
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          try {
                            if (val.trim().isEmpty) {
                              parsedSnapshot = null;
                              validationError = null;
                              return;
                            }
                            final decoded = jsonDecode(val.trim());
                            if (decoded is Map<String, dynamic> && decoded.containsKey('tables') && decoded['tables'] is Map) {
                              parsedSnapshot = decoded;
                              validationError = null;
                            } else {
                              parsedSnapshot = null;
                              validationError = 'Invalid backup format: Missing "tables" object.';
                            }
                          } catch (e) {
                            parsedSnapshot = null;
                            validationError = 'Invalid JSON: ${e.toString().split(":").last}';
                          }
                        });
                      },
                    ),
                    if (parsedSnapshot != null && tables != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFC7D2FE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.verified_outlined, size: 16, color: Color(0xFF4338CA)),
                                const SizedBox(width: 6),
                                Text(
                                  'Backup Verified • Exported: ${parsedSnapshot!['exported_at'] ?? 'Unknown'}',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF3730A3)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Tables detected: ${tables.entries.map((e) => '${e.key} (${(e.value as List).length})').join(', ')}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF4338CA)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4338CA),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: const Text('Restore Records'),
                onPressed: parsedSnapshot == null
                    ? null
                    : () async {
                        Navigator.pop(dialogCtx);
                        try {
                          final results = await DatabaseService().restoreDatabaseSnapshot(parsedSnapshot!);
                          final totalRestored = results.values.fold<int>(0, (sum, count) => sum + count);

                          await ref.read(campStateProvider.notifier).loadCamps();
                          final activeCamp = ref.read(campStateProvider).activeCamp;
                          if (activeCamp != null) {
                            await ref.read(patientListProvider.notifier).loadPatients(activeCamp.id);
                          }
                          await ref.read(auditLogProvider.notifier).loadRecentLogs();

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Database restored successfully: $totalRestored records merged across ${results.length} tables.'),
                                backgroundColor: AppTheme.successGreen,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Restore failed: $e'),
                                backgroundColor: AppTheme.dangerRose,
                              ),
                            );
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
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


    final recentPatients = patientState.patients.take(4).toList();
    final now = DateTime.now();
    final sessionTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final totalRegistered = patientState.patients.length;
    final pendingSync = syncState.pendingTotalCount;
    final syncedCount = (totalRegistered - pendingSync).clamp(0, totalRegistered);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Elevated Active Camp Field Station Banner
              Builder(
                builder: (context) {
                  final colorScheme = Theme.of(context).colorScheme;
                  final orgName = (campState.activeCamp?.organizationName ?? user?.tenantName ?? 'Community Health Outreach');
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colorScheme.primary, colorScheme.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Organization Badge (no tenant ID)
                        Row(
                          children: [
                            const Icon(Icons.corporate_fare_rounded, color: Colors.white70, size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                orgName,
                                style: const TextStyle(
                                  color: Colors.white,
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

                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
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
                              Flexible(
                                child: Text(
                                  campState.hasActiveCamp ? 'LIVE FIELD STATION ACTIVE' : 'NO ACTIVE CAMP OPEN',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
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
                      LayoutBuilder(
                        builder: (ctx, constraints) {
                          final isCompact = constraints.maxWidth < 520;
                          if (isCompact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 10,
                                  children: [
                                    _buildStationBadge(
                                      icon: Icons.people_outline,
                                      label: 'Total Intake',
                                      value: '${patientState.patients.length} Registered',
                                    ),
                                    _buildStationBadge(
                                      icon: syncState.hasPendingRecords ? Icons.cloud_queue : Icons.cloud_done,
                                      label: 'Sync Status',
                                      value: syncState.hasPendingRecords
                                          ? '${syncState.pendingTotalCount} Offline Pending'
                                          : '100% Synced',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Icon(Icons.person_pin_rounded, color: Colors.white70, size: 15),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Staff: ${user?.name ?? "Field Staff"} • Session: $sessionTime',
                                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          }
                          return Row(
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
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    user?.name ?? 'Field Staff',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'Session: $sessionTime',
                                    style: const TextStyle(color: Colors.white60, fontSize: 10),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      const Divider(color: Colors.white12, height: 1),
                      const SizedBox(height: 12),
                      // TODAY'S SHIFT STATS ROW (Responsive Wrap)
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          _buildShiftStatChip(
                            icon: Icons.person_add_rounded,
                            label: 'Registered',
                            value: totalRegistered.toString(),
                            accent: const Color(0xFF34D399),
                          ),
                          _buildShiftStatChip(
                            icon: Icons.cloud_done_rounded,
                            label: 'Synced',
                            value: syncedCount.toString(),
                            accent: const Color(0xFF60A5FA),
                          ),
                          _buildShiftStatChip(
                            icon: Icons.cloud_queue_rounded,
                            label: 'Pending',
                            value: pendingSync.toString(),
                            accent: pendingSync > 0 ? const Color(0xFFFBBF24) : const Color(0xFF34D399),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
                },
              ),
              const SizedBox(height: 18),

              // 2. Fast Patient Search & Triage Bar (Live Search)
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
                            hintText: 'Search by Name, Mobile, or Patient ID (e.g. GC-KTM-...)...',
                            hintStyle: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                            border: InputBorder.none,
                          ),
                          onChanged: (query) {
                            // Live search: navigate with query as soon as user types 3+ chars
                            if (query.trim().length >= 3 && campState.hasActiveCamp) {
                              // Debounce via postFrameCallback to avoid navigating mid-keystroke
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (query.trim().length >= 3) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PatientListView(initialQuery: query.trim()),
                                    ),
                                  );
                                }
                              });
                            }
                          },
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
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final isCompact = constraints.maxWidth < 620;
                  final tile1 = _buildActionTile(
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
                  );

                  final tile2 = _buildActionTile(
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
                  );

                  final tile3 = _buildActionTile(
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
                  );

                  final tile4 = _buildActionTile(
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
                  );

                  if (isCompact) {
                    return Column(
                      children: [
                        tile1,
                        const SizedBox(height: 12),
                        tile2,
                        const SizedBox(height: 12),
                        tile3,
                        const SizedBox(height: 12),
                        tile4,
                      ],
                    );
                  }

                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: tile1),
                          const SizedBox(width: 14),
                          Expanded(child: tile2),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(child: tile3),
                          const SizedBox(width: 14),
                          Expanded(child: tile4),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // 4. Recent Station Intakes / Live Queue Section
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Recent Station Intakes',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                      if (patientState.patients.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryTeal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Showing 4 of ${patientState.patients.length}',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
                          ),
                        ),
                      ],
                    ],
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
                      child: LayoutBuilder(
                        builder: (ctx, itemConstraints) {
                          final isNarrowItem = itemConstraints.maxWidth < 480;
                          if (isNarrowItem) {
                            return InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ClinicalAssessmentView(patient: p),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.12),
                                          child: Text(
                                            p.firstName.isNotEmpty ? p.firstName[0].toUpperCase() : 'P',
                                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      '${p.firstName} ${p.surname}',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
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
                                              const SizedBox(height: 2),
                                              Text(
                                                'Age: ${p.age} • Ward ${p.ward} • ${p.reasonsForVisit.isNotEmpty ? p.reasonsForVisit.first : "General Checkup"}',
                                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryTeal,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 8),
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
                                  ],
                                ),
                              ),
                            );
                          }

                          return ListTile(
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
                                Flexible(
                                  child: Text(
                                    '${p.firstName} ${p.surname}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
                              overflow: TextOverflow.ellipsis,
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
                          );
                        },
                      ),
                    );
                  },
                ),
              const SizedBox(height: 24),

              // 5. Shift Summary & Lead Handover Card (Responsive)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: LayoutBuilder(
                    builder: (ctx, constraints) {
                      final isCompact = constraints.maxWidth < 650;
                      final actionButtons = Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
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
                      );

                      if (isCompact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.picture_as_pdf_rounded, color: Colors.teal.shade700, size: 28),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Camp Clinical Summary & Lead Handover',
                                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Generate instant PDF summary for the camp lead before leaving the venue.',
                                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            actionButtons,
                          ],
                        );
                      }

                      return Row(
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
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Camp Clinical Summary & Lead Handover',
                                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Generate instant PDF summary for the camp lead before leaving the venue.',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          actionButtons,
                        ],
                      );
                    },
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

  /// Shift stats chip for the data taker session header.
  Widget _buildShiftStatChip({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 13, color: accent),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: accent, height: 1.0),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 9.5, color: Colors.white60, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 3. DATA ANALYST DASHBOARD
  // ==========================================
  Widget _buildDataAnalystDashboard(BuildContext context, WidgetRef ref) {
    return const _DataAnalystWorkstation();
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
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          stationBadge,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: color,
                            letterSpacing: 0.3,
                          ),
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
                    Flexible(
                      child: Text(
                        actionPrompt,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
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
                    const SizedBox(width: 6),
                    Flexible(
                      child: Container(
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
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
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

  void _showSupervisorClinicalOverrideDialog(BuildContext context, CampState campState) {
    if (!campState.hasActiveCamp) {
      _showNoCampAlert(context);
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        title: const Row(
          children: [
            Icon(Icons.medical_services_rounded, color: AppTheme.primaryTeal),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Supervisor Clinical Override',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: const Text(
          'You are launching field clinical entry from an administrative Super Admin console. Select the station you wish to access:',
          style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
            label: const Text('Station 1: Intake'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PatientRegistrationView()));
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.document_scanner_rounded, size: 16),
            label: const Text('Scan Form'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4338CA), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const FormScanView()));
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.assignment_ind_rounded, size: 16),
            label: const Text('Patient Roll'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7E22CE), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PatientListView()));
            },
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context, WidgetRef ref, UserModel? user) {
    if (user == null) return;
    final nameCtrl = TextEditingController(text: user.name);
    final savedOrg = SessionService.current?.getOrganizationName();
    final initialTenant = (savedOrg != null && savedOrg.trim().isNotEmpty)
        ? savedOrg
        : user.tenantName;
    final tenantCtrl = TextEditingController(text: initialTenant);
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
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SizedBox(
            width: double.maxFinite,
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
                if (newTenant.isNotEmpty) {
                  await SessionService.current?.saveOrganizationName(newTenant);
                  final activeCamp = ref.read(campStateProvider).activeCamp;
                  if (activeCamp != null) {
                    try {
                      final db = await DatabaseService().database;
                      await db.update(
                        DatabaseTables.tableCamps,
                        {'organization_name': newTenant},
                        where: 'id = ?',
                        whereArgs: [activeCamp.id],
                      );
                      await ref.read(campStateProvider.notifier).loadCamps();
                    } catch (_) {}
                  }
                  try {
                    final db = await DatabaseService().database;
                    await db.insert(
                      DatabaseTables.tableMetadata,
                      {
                        'key': 'saas_organization_name',
                        'value': newTenant,
                        'updated_at': DateTime.now().toIso8601String(),
                      },
                      conflictAlgorithm: ConflictAlgorithm.replace,
                    );
                    await db.insert(
                      DatabaseTables.tableMetadata,
                      {
                        'key': 'tenant_organization_name',
                        'value': newTenant,
                        'updated_at': DateTime.now().toIso8601String(),
                      },
                      conflictAlgorithm: ConflictAlgorithm.replace,
                    );
                  } catch (_) {}
                }
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

class DataAnalystWorkstationPage extends StatelessWidget {
  const DataAnalystWorkstationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Data Analyst Workstation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('Cross-Camp Epidemiology & Visual Analytics', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: const _DataAnalystWorkstation(),
    );
  }
}

class _DataAnalystWorkstation extends ConsumerStatefulWidget {
  const _DataAnalystWorkstation();

  @override
  ConsumerState<_DataAnalystWorkstation> createState() => _DataAnalystWorkstationState();
}

class _DataAnalystWorkstationState extends ConsumerState<_DataAnalystWorkstation> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCampId = 'all'; // 'all' or specific camp ID
  String _selectedPopStage = 'all'; // 'all', '0', '1', '2', '3', '4', 'significant'
  String _selectedComplaint = 'all'; // 'all', 'prolapse', 'discharge', 'urine', 'stool', 'pain', 'menstrual', 'infertility'
  String _selectedSurgery = 'all'; // 'all', 'yes', 'no', 'referral'
  String _selectedAgeBracket = 'all'; // 'all', '<20', '20-35', '36-50', '51-65', '>65'
  String _selectedIntakeStatus = 'all'; // 'all', 'completed', 'pending', 'followup'
  String _selectedDoctor = 'all'; // 'all' or doctor name
  bool _highBpOnly = false;
  String _activeTab = 'overview'; // 'overview', 'charts', 'patients', 'camps'
  bool _filtersExpanded = true;
  String? _exportingPatientId;
  int _registryPage = 0; // pagination: current page for patient registry
  final Map<String, ClinicalVisitModel> _patientVisits = {};
  bool _isLoadingVisits = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCampAndData();
    });
  }

  void _initCampAndData() {
    final campState = ref.read(campStateProvider);
    if (campState.activeCamp != null && _selectedCampId != 'all') {
      _selectedCampId = campState.activeCamp!.id;
    }
    _fetchDataForCamp(_selectedCampId);
  }

  void _fetchDataForCamp(String campId) {
    if (campId == 'all') {
      ref.read(patientListProvider.notifier).loadPatients(null);
      ref.read(reportingViewModelProvider.notifier).loadSummary(campId: null);
    } else {
      ref.read(patientListProvider.notifier).loadPatients(campId);
      ref.read(reportingViewModelProvider.notifier).loadSummary(campId: campId);
    }
  }

  void _onCampChanged(String? newCampId) {
    if (newCampId == null || newCampId == _selectedCampId) return;
    setState(() {
      _selectedCampId = newCampId;
    });
    final campState = ref.read(campStateProvider);
    if (newCampId != 'all') {
      try {
        final selected = campState.camps.firstWhere((c) => c.id == newCampId);
        ref.read(campStateProvider.notifier).selectCamp(selected);
      } catch (_) {}
    }
    _fetchDataForCamp(newCampId);
  }

  void _loadVisitsForPatients(List<PatientModel> patients) async {
    if (_isLoadingVisits) return;
    _isLoadingVisits = true;
    final repo = ref.read(patientRepositoryProvider);
    final Map<String, ClinicalVisitModel> loaded = {};
    for (final p in patients) {
      if (!_patientVisits.containsKey(p.patientId)) {
        try {
          final visit = await repo.getLatestClinicalVisit(p.patientId, patientUuid: p.id);
          if (visit != null) {
            loaded[p.patientId] = visit;
          }
        } catch (_) {}
      }
    }
    if (mounted && loaded.isNotEmpty) {
      setState(() {
        _patientVisits.addAll(loaded);
        _isLoadingVisits = false;
      });
    } else {
      _isLoadingVisits = false;
    }
  }

  int get _activeFilterCount {
    int count = 0;
    if (_selectedCampId != 'all') count++;
    if (_selectedPopStage != 'all') count++;
    if (_selectedComplaint != 'all') count++;
    if (_selectedSurgery != 'all') count++;
    if (_selectedAgeBracket != 'all') count++;
    if (_selectedIntakeStatus != 'all') count++;
    if (_selectedDoctor != 'all') count++;
    if (_highBpOnly) count++;
    if (_searchController.text.trim().isNotEmpty) count++;
    return count;
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _selectedPopStage = 'all';
      _selectedComplaint = 'all';
      _selectedSurgery = 'all';
      _selectedAgeBracket = 'all';
      _selectedIntakeStatus = 'all';
      _selectedDoctor = 'all';
      _highBpOnly = false;
      _registryPage = 0;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _exportPatientDossier(PatientModel patient) async {
    final user = ref.read(authStateProvider).currentUser;
    final deviceState = ref.read(deviceSecurityProvider);
    final campState = ref.read(campStateProvider);
    final targetCamp = campState.camps.isNotEmpty
        ? campState.camps.firstWhere((c) => c.id == patient.campId, orElse: () => campState.camps.first)
        : campState.selectedCamp ?? campState.activeCamp;

    setState(() {
      _exportingPatientId = patient.patientId;
    });

    try {
      final visit = _patientVisits[patient.patientId] ??
          await ref.read(patientRepositoryProvider).getLatestClinicalVisit(
                patient.patientId,
                patientUuid: patient.id,
              );

      final savedPath = await ref.read(reportingViewModelProvider.notifier).exportIndividualPatientPdf(
            patient: patient,
            visit: visit,
            camp: targetCamp,
            userId: user?.id ?? 'usr-analyst',
            userName: user?.name ?? 'Data Analyst',
            userRole: user?.role.toDbString() ?? 'DATA_ANALYST',
            deviceId: deviceState.device?.deviceId ?? 'dev-field',
          );

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        if (savedPath != null) {
          messenger.showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF0F766E),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Individual Dossier Saved: ${patient.fullName}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          savedPath,
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade700,
              content: Text('Failed to generate individual dossier for ${patient.fullName}.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('Error generating PDF: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _exportingPatientId = null;
        });
      }
    }
  }

  void _inspectPatientDossier(PatientModel patient) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PatientDossierInspectionSheet(
        patient: patient,
        cachedVisit: _patientVisits[patient.patientId],
        onExportPdf: () {
          Navigator.pop(ctx);
          _exportPatientDossier(patient);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).currentUser;
    final campState = ref.watch(campStateProvider);
    final reportingState = ref.watch(reportingViewModelProvider);
    final patientState = ref.watch(patientListProvider);

    final isSuperAdmin = user?.role == UserRole.superAdmin;
    final visibleCamps = !isSuperAdmin && user != null
        ? campState.camps.where((c) => user.assignedCampIds.contains(c.id)).toList()
        : campState.camps;

    final summary = reportingState.summary;
    final rawPatients = patientState.rawPatients.isNotEmpty ? patientState.rawPatients : patientState.patients;
    final allPatients = !isSuperAdmin && user != null
        ? rawPatients.where((p) => user.assignedCampIds.contains(p.campId)).toList()
        : rawPatients;

    // Collect all unique doctor names across visible camps for doctor filter dropdown
    final allDoctors = <String>{};
    for (final camp in visibleCamps) {
      if (camp.doctorNames.isNotEmpty) {
        allDoctors.addAll(camp.doctorNames);
      } else if (camp.doctorName.trim().isNotEmpty) {
        allDoctors.add(camp.doctorName.trim());
      }
    }

    // Seed visits from summary if available
    if (summary != null && summary.visits.isNotEmpty) {
      for (final v in summary.visits) {
        if (!_patientVisits.containsKey(v.patientId)) {
          _patientVisits[v.patientId] = v;
        }
      }
    }

    if (allPatients.isNotEmpty && _patientVisits.length < allPatients.length && !_isLoadingVisits) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadVisitsForPatients(allPatients);
      });
    }

    final query = _searchController.text.trim().toLowerCase();
    final filteredPatients = allPatients.where((p) {
      // 1. Camp filter
      if (_selectedCampId != 'all' && p.campId != _selectedCampId) return false;

      // 2. Query search
      if (query.isNotEmpty) {
        final matchesName = p.fullName.toLowerCase().contains(query);
        final matchesId = p.patientId.toLowerCase().contains(query);
        final matchesMobile = p.mobile.contains(query);
        final matchesWard = p.ward.contains(query);
        final matchesPalika = p.municipality.toLowerCase().contains(query);
        final matchesDistrict = p.district.toLowerCase().contains(query);
        final matchesCampCode = p.campCode.toLowerCase().contains(query);
        if (!matchesName && !matchesId && !matchesMobile && !matchesWard && !matchesPalika && !matchesDistrict && !matchesCampCode) {
          return false;
        }
      }

      final visit = _patientVisits[p.patientId];

      // 3. POP Stage filter
      final popStage = visit?.highestPopStage ?? p.highestPopStage ?? 0;
      if (_selectedPopStage == 'significant') {
        if (popStage < 2) return false;
      } else if (_selectedPopStage != 'all') {
        final targetStage = int.tryParse(_selectedPopStage);
        if (targetStage != null && popStage != targetStage) return false;
      }

      // 4. Complaint filter
      if (_selectedComplaint != 'all') {
        final reasons = p.reasonsForVisit.map((r) => r.toLowerCase()).toList();
        final anamnesis = visit?.anamnesisComplaints.toString().toLowerCase() ?? '';
        final combined = [...reasons, anamnesis].join(' ');
        switch (_selectedComplaint) {
          case 'prolapse':
            if (!combined.contains('hanging') && !combined.contains('prolapse') && !combined.contains('खस्ने')) return false;
            break;
          case 'discharge':
            if (!combined.contains('discharge') && !combined.contains('itching') && !combined.contains('सेतो') && !combined.contains('चिलाउने')) return false;
            break;
          case 'urine':
            if (!combined.contains('urine') && !combined.contains('dysuria') && !combined.contains('पिसाब')) return false;
            break;
          case 'stool':
            if (!combined.contains('stool') && !combined.contains('bowel') && !combined.contains('constipation') && !combined.contains('दिसा')) return false;
            break;
          case 'pain':
            if (!combined.contains('pain') && !combined.contains('दुख्ने') && !combined.contains('तल्लो पेट')) return false;
            break;
          case 'menstrual':
            if (!combined.contains('menstrual') && !combined.contains('महिनावारी') && !combined.contains('bleeding')) return false;
            break;
          case 'infertility':
            if (!combined.contains('infertility') && !combined.contains('निःसन्तान')) return false;
            break;
        }
      }

      // 5. Surgery filter
      if (_selectedSurgery == 'yes') {
        if (p.surgeryDone != true && (visit == null || visit.surgeryDone != true)) return false;
      } else if (_selectedSurgery == 'no') {
        if (p.surgeryDone == true || (visit != null && visit.surgeryDone == true)) return false;
      } else if (_selectedSurgery == 'referral') {
        if (visit == null || visit.surgicalReferral == null || visit.surgicalReferral!.trim().isEmpty) return false;
      }

      // 6. Age bracket filter
      if (_selectedAgeBracket == '<20' && p.age >= 20) return false;
      if (_selectedAgeBracket == '20-35' && (p.age < 20 || p.age > 35)) return false;
      if (_selectedAgeBracket == '36-50' && (p.age < 36 || p.age > 50)) return false;
      if (_selectedAgeBracket == '51-65' && (p.age < 51 || p.age > 65)) return false;
      if (_selectedAgeBracket == '>65' && p.age <= 65) return false;

      // 7. Clinical Intake status filter
      if (_selectedIntakeStatus == 'completed') {
        if (!p.hasClinicalVisit && visit == null) return false;
      } else if (_selectedIntakeStatus == 'pending') {
        if (p.hasClinicalVisit || visit != null) return false;
      } else if (_selectedIntakeStatus == 'followup') {
        if (!p.isFollowUp && !(visit?.isFollowUp ?? false)) return false;
      }

      // 8. High BP filter
      if (_highBpOnly) {
        if (visit == null) return false;
        final sys = visit.systolicBp ?? 0;
        final dia = visit.diastolicBp ?? 0;
        if (sys < 140 && dia < 90) return false;
      }

      // 9. Doctor filter — match by camp's doctorNames list
      if (_selectedDoctor != 'all') {
        final patientCamp = campState.camps.where((c) => c.id == p.campId).firstOrNull;
        if (patientCamp == null) return false;
        final campDoctors = patientCamp.doctorNames.isNotEmpty
            ? patientCamp.doctorNames
            : (patientCamp.doctorName.trim().isNotEmpty ? [patientCamp.doctorName.trim()] : <String>[]);
        if (!campDoctors.any((d) => d.toLowerCase() == _selectedDoctor.toLowerCase())) return false;
      }

      return true;
    }).toList();

    // Determine current camp display name
    String campDisplayName = 'All Camps (Cross-Camp Intelligence)';
    if (_selectedCampId != 'all') {
      try {
        final c = campState.camps.firstWhere((x) => x.id == _selectedCampId);
        campDisplayName = '${c.campCode} - ${c.name}';
      } catch (_) {
        campDisplayName = 'Selected Camp';
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. EXECUTIVE COMMAND HEADER
              _buildExecutiveCommandHeader(
                user: user,
                campState: campState,
                visibleCamps: visibleCamps,
                currentCampName: campDisplayName,
              ),

              const SizedBox(height: 18),

              // 2. REAL-TIME KPI METRICS (4 TELEMETRY CARDS)
              _buildKpiMetricsRow(
                summary: summary,
                allPatientsCount: allPatients.length,
                filteredPatientsCount: filteredPatients.length,
              ),

              const SizedBox(height: 18),

              // 3. MULTI-DIMENSIONAL ANALYTICS FILTER BAR
              _buildAnalyticsFilterBar(
                campState: campState,
                totalPatients: allPatients.length,
                filteredCount: filteredPatients.length,
                allDoctors: allDoctors.toList()..sort(),
              ),

              const SizedBox(height: 18),

              // 4. VIEW MODE TABS NAVIGATION
              _buildViewModeTabs(filteredCount: filteredPatients.length),

              const SizedBox(height: 16),

              // 5. VIEW CONTENT ACCORDING TO ACTIVE TAB
              if (_activeTab == 'overview' || _activeTab == 'charts') ...[
                // POP-Q Staging Spectrum Bar Chart
                _buildPopStagingBarChart(summary, filteredPatients),
                const SizedBox(height: 18),

                // Chief Clinical Complaints Distribution Chart
                _buildChiefComplaintsChart(filteredPatients),
                const SizedBox(height: 18),

                // Demographic Age Cohort Chart
                _buildAgeDistributionChart(summary, filteredPatients),
                const SizedBox(height: 18),

                // Clinical Interventions & Modalities Chart
                _buildTreatmentModalityChart(summary, filteredPatients),
                const SizedBox(height: 18),
              ],

              if (_activeTab == 'overview' || _activeTab == 'camps') ...[
                // Cross-Camp Comparison Chart
                _buildCampWiseComparisonChart(campState.camps, allPatients),
                const SizedBox(height: 18),
              ],

              if (_activeTab == 'overview' || _activeTab == 'patients') ...[
                // Camp-Wise Patients Registry with Individual Dossier Export
                _buildCampWisePatientRegistry(
                  filteredPatients: filteredPatients,
                  allPatientsCount: allPatients.length,
                  campState: campState,
                  currentPage: _registryPage,
                  onPageChanged: (p) => setState(() => _registryPage = p),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // COMPONENT 1: EXECUTIVE COMMAND HEADER
  // ==========================================
  Widget _buildExecutiveCommandHeader({
    required UserModel? user,
    required CampState campState,
    required List<CampModel> visibleCamps,
    required String currentCampName,
  }) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final secondary = theme.colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Badges & Tenant Info
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.analytics_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 5),
                      Text(
                        'CLINICAL DATA ANALYST WORKSTATION',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                '${user?.tenantName ?? "Nepal Health Outreach Network"} • Role: Data Analyst',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // User Identity & Camp Selector Row
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 650;
              final userProfile = Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0D9488), Color(0xFF042F2E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.teal.shade200, width: 1.5),
                    ),
                    child: const Icon(Icons.insights_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? 'Population Health Analyst',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Multi-station Epidemiology, POP-Q Triage & Clinical Dossiers',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final campDropdown = Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1E293B),
                    value: _selectedCampId,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                    items: [
                      DropdownMenuItem<String>(
                        value: 'all',
                        child: Row(
                          children: [
                            const Icon(Icons.public_rounded, color: Color(0xFF2DD4BF), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                (user?.role == UserRole.superAdmin)
                                    ? 'All Camps (Cross-Camp Intelligence)'
                                    : 'All Assigned Camps (${visibleCamps.length})',
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...visibleCamps.map((c) => DropdownMenuItem<String>(
                            value: c.id,
                            child: Row(
                              children: [
                                const Icon(Icons.location_on_outlined, color: Colors.white70, size: 16),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${c.campCode} - ${c.name}',
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                    onChanged: _onCampChanged,
                  ),
                ),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    userProfile,
                    const SizedBox(height: 12),
                    campDropdown,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: userProfile),
                  const SizedBox(width: 16),
                  SizedBox(width: 320, child: campDropdown),
                ],
              );
            },
          ),

          const SizedBox(height: 14),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),

          // Actions Row
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                label: const Text('Aggregate Camp Report (पिडिएफ)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CampReportView(
                        initialCampId: _selectedCampId == 'all' ? null : _selectedCampId,
                      ),
                    ),
                  );
                },
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.history_edu_rounded, size: 16),
                label: const Text('Audit Trail', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AuditTrailView()),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // COMPONENT 2: REAL-TIME KPI METRICS
  // ==========================================
  Widget _buildKpiMetricsRow({
    required CampReportSummaryModel? summary,
    required int allPatientsCount,
    required int filteredPatientsCount,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final totalReg = allPatientsCount;
        final totalExam = _patientVisits.length;
        final popSignificant = summary?.significantPopCount ??
            _patientVisits.values.where((v) => v.highestPopStage >= 2).length;
        final popPct = totalExam > 0 ? (popSignificant / totalExam * 100).toStringAsFixed(1) : '0.0';
        final referrals = summary?.totalSurgicalReferrals ??
            _patientVisits.values.where((v) => v.surgicalReferral != null && v.surgicalReferral!.isNotEmpty).length;
        final prescriptions = summary?.totalPrescriptionsCount ?? 0;

        final cards = [
          _buildTelemetryCard(
            title: 'Registered Cohort',
            value: '$totalReg',
            subtitle: 'Exams Completed: $totalExam',
            icon: Icons.people_alt_rounded,
            color: const Color(0xFF0D9488),
          ),
          _buildTelemetryCard(
            title: 'POP Grade II-IV',
            value: '$popPct%',
            subtitle: '$popSignificant High-Grade Prolapse',
            icon: Icons.healing_rounded,
            color: const Color(0xFFF59E0B),
          ),
          _buildTelemetryCard(
            title: 'Surgical Candidates',
            value: '$referrals',
            subtitle: 'Hospital Referrals',
            icon: Icons.local_hospital_rounded,
            color: const Color(0xFFF43F5E),
          ),
          _buildTelemetryCard(
            title: 'Prescriptions',
            value: '$prescriptions',
            subtitle: 'Pessaries Fitted: ${summary?.totalPessariesInserted ?? 0}',
            icon: Icons.medication_rounded,
            color: const Color(0xFF3B82F6),
          ),
        ];

        if (isWide) {
          return Row(
            children: cards
                .map((c) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: c,
                      ),
                    ))
                .toList(),
          );
        }

        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: constraints.maxWidth < 420 ? 1.3 : 1.6,
          children: cards,
        );
      },
    );
  }

  // ==========================================
  // COMPONENT 3: MULTI-DIMENSIONAL FILTER BAR
  // ==========================================
  Widget _buildAnalyticsFilterBar({
    required CampState campState,
    required int totalPatients,
    required int filteredCount,
    required List<String> allDoctors,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Filter Header & Toggle
            Row(
              children: [
                const Icon(Icons.filter_list_rounded, color: Color(0xFF0F766E), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Multi-Dimensional Analytics Filters',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                      ),
                      if (_activeFilterCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$_activeFilterCount Active',
                            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_activeFilterCount > 0)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                    label: const Text('Reset All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _resetFilters,
                  ),
                IconButton(
                  icon: Icon(_filtersExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _filtersExpanded = !_filtersExpanded),
                  tooltip: _filtersExpanded ? 'Collapse Filters' : 'Expand Filters',
                ),
              ],
            ),

            // Search Bar
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search cohort by Patient Name, ID (GC-...), Mobile, Ward, or Camp...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => setState(() => _searchController.clear()),
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (_) => setState(() {}),
            ),

            if (_filtersExpanded) ...[
              const SizedBox(height: 12),
              // Dropdowns Grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 700;

                  final popDropdown = DropdownButtonFormField<String>(
                    initialValue: _selectedPopStage,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'POP Severity',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All POP Stages', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: '0', child: Text('Stage 0 (Normal)', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: '1', child: Text('Stage I (Mild)', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: '2', child: Text('Stage II (Moderate)', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: '3', child: Text('Stage III (Severe)', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: '4', child: Text('Stage IV (Procidentia)', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: 'significant', child: Text('Stages II-IV (Significant POP)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold))),
                    ],
                    onChanged: (v) => setState(() => _selectedPopStage = v ?? 'all'),
                  );

                  final complaintDropdown = DropdownButtonFormField<String>(
                    initialValue: _selectedComplaint,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Chief Complaint',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Complaints', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: 'prolapse', child: Text('Prolapse / Something Hanging', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: 'discharge', child: Text('Discharge / Itching', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: 'urine', child: Text('Urinary Issues', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: 'stool', child: Text('Bowel / Stool Issues', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: 'pain', child: Text('Pelvic / Abdominal Pain', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: 'menstrual', child: Text('Menstrual Problems', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: 'infertility', child: Text('Infertility Issues', style: TextStyle(fontSize: 12.5))),
                    ],
                    onChanged: (v) => setState(() => _selectedComplaint = v ?? 'all'),
                  );

                  final surgeryDropdown = DropdownButtonFormField<String>(
                    initialValue: _selectedSurgery,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Surgery Status',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All / Any', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: 'yes', child: Text('Surgery Performed', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: 'no', child: Text('No Surgery', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: 'referral', child: Text('Hospital Referral', style: TextStyle(fontSize: 12.5))),
                    ],
                    onChanged: (v) => setState(() => _selectedSurgery = v ?? 'all'),
                  );

                  final ageDropdown = DropdownButtonFormField<String>(
                    initialValue: _selectedAgeBracket,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Age Cohort',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Age Cohorts', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: '<20', child: Text('< 20 Years', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: '20-35', child: Text('20 - 35 Years', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: '36-50', child: Text('36 - 50 Years', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: '51-65', child: Text('51 - 65 Years', style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(value: '>65', child: Text('> 65 Years', style: TextStyle(fontSize: 12.5))),
                    ],
                    onChanged: (v) => setState(() => _selectedAgeBracket = v ?? 'all'),
                  );

                  // Doctor filter dropdown (only shown if any doctors are defined)
                  final doctorDropdown = allDoctors.isEmpty
                      ? const SizedBox.shrink()
                      : DropdownButtonFormField<String>(
                          key: ValueKey('doctor_filter_$_selectedDoctor'),
                          initialValue: _selectedDoctor,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Attending Doctor',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                            prefixIcon: Icon(Icons.person_pin_rounded, size: 18),
                          ),
                          items: [
                            const DropdownMenuItem(value: 'all', child: Text('All Doctors', style: TextStyle(fontSize: 12.5))),
                            ...allDoctors.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 12.5)))),
                          ],
                          onChanged: (v) => setState(() {
                            _selectedDoctor = v ?? 'all';
                            _registryPage = 0;
                          }),
                        );

                  if (isWide) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: popDropdown),
                            const SizedBox(width: 8),
                            Expanded(child: complaintDropdown),
                            const SizedBox(width: 8),
                            Expanded(child: surgeryDropdown),
                            const SizedBox(width: 8),
                            Expanded(child: ageDropdown),
                          ],
                        ),
                        if (allDoctors.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(flex: 2, child: doctorDropdown),
                              const SizedBox(width: 8),
                              const Expanded(flex: 2, child: SizedBox.shrink()),
                            ],
                          ),
                        ],
                      ],
                    );
                  }

                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: popDropdown),
                          const SizedBox(width: 8),
                          Expanded(child: complaintDropdown),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: surgeryDropdown),
                          const SizedBox(width: 8),
                          Expanded(child: ageDropdown),
                        ],
                      ),
                      if (allDoctors.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        doctorDropdown,
                      ],
                    ],
                  );
                },
              ),

              const SizedBox(height: 10),

              // Filter Toggles Row
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: const Text('Hypertension Alert (HTN >= 140/90)', style: TextStyle(fontSize: 11.5)),
                    selected: _highBpOnly,
                    selectedColor: const Color(0xFFFEE2E2),
                    checkmarkColor: const Color(0xFFDC2626),
                    labelStyle: TextStyle(
                      color: _highBpOnly ? const Color(0xFFDC2626) : const Color(0xFF334155),
                      fontWeight: _highBpOnly ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (val) => setState(() => _highBpOnly = val),
                  ),
                  FilterChip(
                    label: const Text('Clinical Intake Completed', style: TextStyle(fontSize: 11.5)),
                    selected: _selectedIntakeStatus == 'completed',
                    selectedColor: const Color(0xFFCCFBF1),
                    checkmarkColor: const Color(0xFF0F766E),
                    labelStyle: TextStyle(
                      color: _selectedIntakeStatus == 'completed' ? const Color(0xFF0F766E) : const Color(0xFF334155),
                      fontWeight: _selectedIntakeStatus == 'completed' ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (val) => setState(() => _selectedIntakeStatus = val ? 'completed' : 'all'),
                  ),
                  FilterChip(
                    label: const Text('Intake Pending', style: TextStyle(fontSize: 11.5)),
                    selected: _selectedIntakeStatus == 'pending',
                    selectedColor: const Color(0xFFFEF3C7),
                    checkmarkColor: const Color(0xFFD97706),
                    labelStyle: TextStyle(
                      color: _selectedIntakeStatus == 'pending' ? const Color(0xFFD97706) : const Color(0xFF334155),
                      fontWeight: _selectedIntakeStatus == 'pending' ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (val) => setState(() => _selectedIntakeStatus = val ? 'pending' : 'all'),
                  ),
                  FilterChip(
                    label: const Text('Follow-Up Visits', style: TextStyle(fontSize: 11.5)),
                    selected: _selectedIntakeStatus == 'followup',
                    selectedColor: const Color(0xFFEDE9FE),
                    checkmarkColor: const Color(0xFF7C3AED),
                    labelStyle: TextStyle(
                      color: _selectedIntakeStatus == 'followup' ? const Color(0xFF7C3AED) : const Color(0xFF334155),
                      fontWeight: _selectedIntakeStatus == 'followup' ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (val) => setState(() => _selectedIntakeStatus = val ? 'followup' : 'all'),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 8),
            // Results Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Color(0xFF475569)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Displaying $filteredCount of $totalPatients registered cohort records',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w600),
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

  // ==========================================
  // COMPONENT 4: VIEW MODE TABS NAVIGATION
  // ==========================================
  Widget _buildViewModeTabs({required int filteredCount}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildNavTab(
            id: 'overview',
            label: 'All-In-One Dashboard',
            icon: Icons.dashboard_customize_rounded,
          ),
          const SizedBox(width: 8),
          _buildNavTab(
            id: 'charts',
            label: 'Epidemiological Charts',
            icon: Icons.bar_chart_rounded,
          ),
          const SizedBox(width: 8),
          _buildNavTab(
            id: 'patients',
            label: 'Camp-Wise Patients ($filteredCount)',
            icon: Icons.people_outline_rounded,
          ),
          const SizedBox(width: 8),
          _buildNavTab(
            id: 'camps',
            label: 'Cross-Camp Comparison',
            icon: Icons.map_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildNavTab({
    required String id,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _activeTab == id;
    return ChoiceChip(
      selected: isSelected,
      onSelected: (_) => setState(() => _activeTab = id),
      avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : const Color(0xFF475569)),
      label: Text(label),
      selectedColor: const Color(0xFF0F766E),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : const Color(0xFF334155),
        fontSize: 12.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? const Color(0xFF0F766E) : const Color(0xFFCBD5E1),
          width: 1,
        ),
      ),
    );
  }

  // ==========================================
  // CHART 1: POP-Q SEVERITY SPECTRUM
  // ==========================================
  Widget _buildPopStagingBarChart(CampReportSummaryModel? summary, List<PatientModel> patients) {
    // Calculate stage counts from visits or summary
    int st0 = 0, st1 = 0, st2 = 0, st3 = 0, st4 = 0;
    int totalExams = 0;

    if (summary != null && summary.totalVisitsRecorded > 0 && summary.highestPopStages.isNotEmpty) {
      st0 = summary.highestPopStages[0] ?? 0;
      st1 = summary.highestPopStages[1] ?? 0;
      st2 = summary.highestPopStages[2] ?? 0;
      st3 = summary.highestPopStages[3] ?? 0;
      st4 = summary.highestPopStages[4] ?? 0;
      totalExams = summary.totalVisitsRecorded;
    } else {
      for (final p in patients) {
        final v = _patientVisits[p.patientId];
        if (v != null || p.highestPopStage != null) {
          totalExams++;
          final s = v?.highestPopStage ?? p.highestPopStage ?? 0;
          if (s == 0) {
            st0++;
          } else if (s == 1) {
            st1++;
          } else if (s == 2) {
            st2++;
          } else if (s == 3) {
            st3++;
          } else if (s >= 4) {
            st4++;
          }
        }
      }
    }

    final significant = st2 + st3 + st4;
    final sigPct = totalExams > 0 ? (significant / totalExams * 100).toStringAsFixed(1) : '0.0';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.stacked_bar_chart_rounded, color: Color(0xFF0F766E), size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pelvic Organ Prolapse (POP-Q) Severity Spectrum',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        'Baden-Walker Classification across clinical examinations',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$totalExams Evaluated',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // POP-Q Stage Breakdown Cards (Responsive 4-column on desktop, 2x2 on mobile)
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 640;
                final cards = [
                  _buildPopStageGridCard('Stage 0 (Normal)', '$st0', const Color(0xFF10B981)),
                  _buildPopStageGridCard('Stage I (Mild)', '$st1', const Color(0xFF06B6D4)),
                  _buildPopStageGridCard('Stage II (Moderate)', '$st2', const Color(0xFFF59E0B)),
                  _buildPopStageGridCard('Stage III-IV (Severe)', '${st3 + st4}', const Color(0xFFEA580C)),
                ];

                if (isWide) {
                  return Row(
                    children: cards
                        .map((c) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: c,
                              ),
                            ))
                        .toList(),
                  );
                }

                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 8),
                        Expanded(child: cards[1]),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: cards[2]),
                        const SizedBox(width: 8),
                        Expanded(child: cards[3]),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),

            // Horizontal Distribution Bars
            _buildChartHorizontalBar(
              label: 'Stage 0 - Normal Anatomy (सामान्य)',
              subtitle: 'Leading edge above -1 cm • No prolapse',
              count: st0,
              total: totalExams,
              color: const Color(0xFF10B981),
            ),
            const SizedBox(height: 10),
            _buildChartHorizontalBar(
              label: 'Stage I - Mild Prolapse (हल्का)',
              subtitle: 'Leading edge > 1 cm above hymenal ring',
              count: st1,
              total: totalExams,
              color: const Color(0xFF06B6D4),
            ),
            const SizedBox(height: 10),
            _buildChartHorizontalBar(
              label: 'Stage II - Moderate Prolapse (मध्यम)',
              subtitle: 'Leading edge within 1 cm of hymen • Conservative / Pessary candidate',
              count: st2,
              total: totalExams,
              color: const Color(0xFFF59E0B),
            ),
            const SizedBox(height: 10),
            _buildChartHorizontalBar(
              label: 'Stage III - Severe Prolapse (गम्भीर)',
              subtitle: 'Leading edge > 1 cm below hymen, but < 2 cm less than TVL',
              count: st3,
              total: totalExams,
              color: const Color(0xFFEA580C),
            ),
            const SizedBox(height: 10),
            _buildChartHorizontalBar(
              label: 'Stage IV - Complete Procidentia (पूर्ण खसेको)',
              subtitle: 'Complete eversion of lower genital tract • Surgical candidate',
              count: st4,
              total: totalExams,
              color: const Color(0xFFDC2626),
            ),

            const SizedBox(height: 16),
            // Significant POP Summary Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Epidemiological Prolapse Burden: $sigPct% ($significant Patients) have Stage II-IV Prolapse requiring clinical intervention.',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
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

  // ==========================================
  // CHART 2: CHIEF CLINICAL COMPLAINTS
  // ==========================================
  Widget _buildChiefComplaintsChart(List<PatientModel> patients) {
    int prolapseCount = 0;
    int dischargeCount = 0;
    int urineCount = 0;
    int stoolCount = 0;
    int painCount = 0;
    int menstrualCount = 0;
    int infertilityCount = 0;
    int checkupCount = 0;

    final totalCohort = patients.length;

    for (final p in patients) {
      final reasons = p.reasonsForVisit.map((r) => r.toLowerCase()).toList();
      final visit = _patientVisits[p.patientId];
      final anamnesis = visit?.anamnesisComplaints.toString().toLowerCase() ?? '';
      final combined = [...reasons, anamnesis].join(' ');

      if (combined.contains('hanging') || combined.contains('prolapse') || combined.contains('खस्ने')) prolapseCount++;
      if (combined.contains('discharge') || combined.contains('itching') || combined.contains('सेतो') || combined.contains('चिलाउने')) dischargeCount++;
      if (combined.contains('urine') || combined.contains('dysuria') || combined.contains('पिसाब')) urineCount++;
      if (combined.contains('stool') || combined.contains('bowel') || combined.contains('constipation') || combined.contains('दिसा')) stoolCount++;
      if (combined.contains('pain') || combined.contains('दुख्ने') || combined.contains('तल्लो पेट')) painCount++;
      if (combined.contains('menstrual') || combined.contains('महिनावारी') || combined.contains('bleeding')) menstrualCount++;
      if (combined.contains('infertility') || combined.contains('निःसन्तान')) infertilityCount++;
      if (combined.contains('checkup') || combined.contains('routine') || combined.contains('जाँच')) checkupCount++;
    }

    final items = [
      {'label': 'Prolapse / Something Hanging Out (आङ खस्ने)', 'count': prolapseCount, 'color': const Color(0xFFE11D48)},
      {'label': 'White Discharge & Itching (सेतो पानी तथा चिलाउने)', 'count': dischargeCount, 'color': const Color(0xFF0284C7)},
      {'label': 'Urinary Problems (पिसाब सम्बन्धी / पोल्ने)', 'count': urineCount, 'color': const Color(0xFF7C3AED)},
      {'label': 'Pelvic / Lower Abdominal Pain (तल्लो पेट / कम्मर दुख्ने)', 'count': painCount, 'color': const Color(0xFFD97706)},
      {'label': 'Bowel / Stool Problems (दिसा सम्बन्धी / कब्जियत)', 'count': stoolCount, 'color': const Color(0xFF0D9488)},
      {'label': 'Menstrual Irregularities (महिनावारी गडबडी)', 'count': menstrualCount, 'color': const Color(0xFFDB2777)},
      {'label': 'Infertility / Subfertility (निःसन्तान सम्बन्धी)', 'count': infertilityCount, 'color': const Color(0xFF4F46E5)},
      {'label': 'Routine Health Checkup (सामान्य स्वास्थ्य जाँच)', 'count': checkupCount, 'color': const Color(0xFF10B981)},
    ]..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.leaderboard_rounded, color: Color(0xFF7C3AED), size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chief Clinical Complaints Frequency & Ranking',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        'Reported symptomatology ranked by cohort frequency',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...items.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final item = entry.value;
              final count = item['count'] as int;
              final color = item['color'] as Color;
              final label = item['label'] as String;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildRankedBarItem(
                  rank: idx,
                  label: label,
                  count: count,
                  total: totalCohort,
                  color: color,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // CHART 3: DEMOGRAPHIC AGE COHORT
  // ==========================================
  Widget _buildAgeDistributionChart(CampReportSummaryModel? summary, List<PatientModel> patients) {
    int under20 = 0, a20to35 = 0, a36to50 = 0, a51to65 = 0, over65 = 0;
    final totalPatients = patients.length;

    for (final p in patients) {
      if (p.age < 20) {
        under20++;
      } else if (p.age <= 35) {
        a20to35++;
      } else if (p.age <= 50) {
        a36to50++;
      } else if (p.age <= 65) {
        a51to65++;
      } else {
        over65++;
      }
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.cake_rounded, color: Color(0xFF0284C7), size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Demographic Age Cohort Distribution',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        'Age bracket breakdown across registered female population',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildChartHorizontalBar(
              label: '< 20 Years (युवा / किशोरावस्था)',
              subtitle: 'Early reproductive age group',
              count: under20,
              total: totalPatients,
              color: const Color(0xFF38BDF8),
            ),
            const SizedBox(height: 10),
            _buildChartHorizontalBar(
              label: '20 - 35 Years (प्रजनन उमेर समूह)',
              subtitle: 'Peak childbearing & post-partum cohort',
              count: a20to35,
              total: totalPatients,
              color: const Color(0xFF0D9488),
            ),
            const SizedBox(height: 10),
            _buildChartHorizontalBar(
              label: '36 - 50 Years (मध्यम उमेर समूह)',
              subtitle: 'Perimenopausal & multiparous cohort',
              count: a36to50,
              total: totalPatients,
              color: const Color(0xFFF59E0B),
            ),
            const SizedBox(height: 10),
            _buildChartHorizontalBar(
              label: '51 - 65 Years (प्रौढ उमेर समूह)',
              subtitle: 'Postmenopausal • High POP & pelvic tone laxity burden',
              count: a51to65,
              total: totalPatients,
              color: const Color(0xFFEA580C),
            ),
            const SizedBox(height: 10),
            _buildChartHorizontalBar(
              label: '> 65 Years (ज्येष्ठ नागरिक)',
              subtitle: 'Elderly population requiring conservative pessary management',
              count: over65,
              total: totalPatients,
              color: const Color(0xFF9333EA),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // CHART 4: TREATMENT & CLINICAL MODALITY
  // ==========================================
  Widget _buildTreatmentModalityChart(CampReportSummaryModel? summary, List<PatientModel> patients) {
    int surgicalCount = 0;
    int pessaryCount = 0;
    int prescriptionCount = 0;
    int counselingCount = 0;

    if (summary != null) {
      surgicalCount = summary.totalSurgicalReferrals;
      pessaryCount = summary.totalPessariesInserted;
      prescriptionCount = summary.totalPrescriptionsCount;
      counselingCount = summary.pelvicFloorCounselingCount;
    } else {
      for (final p in patients) {
        final v = _patientVisits[p.patientId];
        if (v != null) {
          if (v.surgicalReferral != null && v.surgicalReferral!.isNotEmpty) surgicalCount++;
          if (v.pessaryType != null && v.pessaryType!.isNotEmpty) pessaryCount++;
          if (v.medications.isNotEmpty) prescriptionCount++;
          if (v.counseling.isNotEmpty) counselingCount++;
        }
      }
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.medical_services_rounded, color: Color(0xFF10B981), size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Clinical Treatment & Management Modalities',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        'Distribution of surgical, mechanical & pharmacological care delivered',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 600;
                final items = [
                  _buildModalityCard(
                    title: 'Surgical Referrals',
                    count: '$surgicalCount',
                    desc: 'Tertiary Hospital Referrals',
                    icon: Icons.local_hospital_rounded,
                    color: const Color(0xFFDC2626),
                  ),
                  _buildModalityCard(
                    title: 'Pessary Fittings',
                    count: '$pessaryCount',
                    desc: 'Ring & Shelf Devices Inserted',
                    icon: Icons.donut_large_rounded,
                    color: const Color(0xFFF59E0B),
                  ),
                  _buildModalityCard(
                    title: 'Medications Dispensed',
                    count: '$prescriptionCount',
                    desc: 'Prescriptions Formulated',
                    icon: Icons.medication_rounded,
                    color: const Color(0xFF0D9488),
                  ),
                  _buildModalityCard(
                    title: 'Pelvic Floor Training',
                    count: '$counselingCount',
                    desc: 'Kegel & Lifestyle Guidance',
                    icon: Icons.fitness_center_rounded,
                    color: const Color(0xFF3B82F6),
                  ),
                ];

                if (isWide) {
                  return Row(
                    children: items
                        .map((it) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: it,
                              ),
                            ))
                        .toList(),
                  );
                }

                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.35,
                  children: items,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // CHART 5: CROSS-CAMP VOLUME & PREVALENCE COMPARISON
  // ==========================================
  Widget _buildCampWiseComparisonChart(List<CampModel> camps, List<PatientModel> allPatients) {
    if (camps.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4338CA).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.hub_rounded, color: Color(0xFF4338CA), size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cross-Camp Volume & Epidemiological Comparison',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        'Comparative patient registry and prolapse prevalence across camps',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE9FE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${camps.length} Camps',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4338CA)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            ...camps.map((camp) {
              final campPatients = allPatients.where((p) => p.campId == camp.id).toList();
              final exams = campPatients.where((p) => p.hasClinicalVisit || _patientVisits.containsKey(p.patientId)).length;
              final sigPop = campPatients.where((p) {
                final v = _patientVisits[p.patientId];
                return (v?.highestPopStage ?? p.highestPopStage ?? 0) >= 2;
              }).length;
              final sigPopPct = exams > 0 ? (sigPop / exams * 100).toStringAsFixed(1) : '0.0';
              final pctOfTotal = allPatients.isNotEmpty ? (campPatients.length / allPatients.length * 100).toStringAsFixed(1) : '0.0';

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${camp.name} (${camp.campCode})',
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${campPatients.length} Patients ($pctOfTotal%)',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${camp.district}, ${camp.municipality} • Venue: ${camp.venue}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 8),

                    // Progress Bar of volume
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: allPatients.isNotEmpty ? campPatients.length / allPatients.length : 0,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0D9488)),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Metrics Badges
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text('Exams: $exams', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                        const Text('•', style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1))),
                        Text('POP Stage II-IV: $sigPop ($sigPopPct%)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // COMPONENT 5: CAMP-WISE PATIENTS REGISTRY & DOSSIER HUB
  // ==========================================
  Widget _buildCampWisePatientRegistry({
    required List<PatientModel> filteredPatients,
    required int allPatientsCount,
    required CampState campState,
    required int currentPage,
    required ValueChanged<int> onPageChanged,
  }) {
    const int pageSize = 25;
    final int totalPages = (filteredPatients.length / pageSize).ceil().clamp(1, 9999);
    final int safePage = currentPage.clamp(0, totalPages - 1);
    final int startIdx = safePage * pageSize;
    final int endIdx = (startIdx + pageSize).clamp(0, filteredPatients.length);
    final pagePatients = filteredPatients.sublist(startIdx, endIdx);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.folder_shared_rounded, color: Color(0xFF0F766E), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Camp-Wise Individual Patient Clinical Dossiers (बिरामी कागजात)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${filteredPatients.length} patients${filteredPatients.length != allPatientsCount ? " (filtered from $allPatientsCount)" : ""} · Showing ${startIdx + 1}–$endIdx',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Patient List
            if (filteredPatients.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 36),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.person_search_rounded, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 10),
                    Text(
                      allPatientsCount == 0
                          ? 'No patients registered yet.'
                          : 'No patients match your search or filter criteria.',
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _resetFilters,
                      child: const Text('Reset All Filters'),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: pagePatients.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                itemBuilder: (context, index) {
                  final patient = pagePatients[index];
                  final visit = _patientVisits[patient.patientId];
                  final isExporting = _exportingPatientId == patient.patientId;

                  // Find camp name for this patient
                  String patientCampLabel = patient.campCode;
                  try {
                    final c = campState.camps.firstWhere((x) => x.id == patient.campId);
                    patientCampLabel = '${c.campCode} • ${c.name}';
                  } catch (_) {}

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: LayoutBuilder(
                      builder: (ctx, constraints) {
                        final isCompact = constraints.maxWidth < 640;

                        final avatar = CircleAvatar(
                          radius: 22,
                          backgroundColor: const Color(0xFF0F766E).withValues(alpha: 0.12),
                          child: Text(
                            patient.firstName.isNotEmpty ? patient.firstName[0].toUpperCase() : 'P',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E), fontSize: 16),
                          ),
                        );

                        final bioColumn = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    patient.fullName,
                                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    patient.patientId,
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Age: ${patient.age}y • Ward: ${patient.ward} • ${patient.municipality} • Mobile: ${patient.mobile.isNotEmpty ? patient.mobile : "N/A"}',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 4),
                            // Camp Badge & Clinical Badges
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  constraints: const BoxConstraints(maxWidth: 160),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0E7FF),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFC7D2FE)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.location_on, size: 10, color: Color(0xFF4338CA)),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          patientCampLabel,
                                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF4338CA)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (visit != null || patient.highestPopStage != null)
                                  _buildMiniBadge(
                                    text: 'POP Stage ${visit?.highestPopStage ?? patient.highestPopStage ?? 0}',
                                    color: (visit?.highestPopStage ?? patient.highestPopStage ?? 0) >= 2
                                        ? const Color(0xFFF59E0B)
                                        : const Color(0xFF10B981),
                                  ),
                                if (visit?.systolicBp != null && visit?.diastolicBp != null)
                                  _buildMiniBadge(
                                    text: 'BP ${visit!.systolicBp}/${visit.diastolicBp}',
                                    color: (visit.systolicBp! >= 140 || visit.diastolicBp! >= 90)
                                        ? const Color(0xFFEF4444)
                                        : const Color(0xFF3B82F6),
                                  ),
                                if (visit?.surgicalReferral != null && visit!.surgicalReferral!.isNotEmpty)
                                  _buildMiniBadge(
                                    text: 'Ref: ${visit.surgicalReferral}',
                                    color: const Color(0xFFDC2626),
                                  ),
                                if (patient.isFollowUp || (visit?.isFollowUp ?? false))
                                  _buildMiniBadge(
                                    text: 'Follow-Up',
                                    color: const Color(0xFF7C3AED),
                                  ),
                              ],
                            ),
                          ],
                        );

                        final inspectBtn = OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0F766E),
                            side: BorderSide(color: Colors.teal.shade200),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.visibility_outlined, size: 15),
                          label: const Text('Inspect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: () => _inspectPatientDossier(patient),
                        );

                        final dossierBtn = ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: isExporting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.picture_as_pdf_rounded, size: 15),
                          label: Text(
                            isExporting ? 'Exporting...' : 'PDF Dossier',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          onPressed: isExporting ? null : () => _exportPatientDossier(patient),
                        );

                        if (isCompact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  avatar,
                                  const SizedBox(width: 12),
                                  Expanded(child: bioColumn),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(child: inspectBtn),
                                  const SizedBox(width: 8),
                                  Expanded(child: dossierBtn),
                                ],
                              ),
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            avatar,
                            const SizedBox(width: 14),
                            Expanded(child: bioColumn),
                            const SizedBox(width: 10),
                            inspectBtn,
                            const SizedBox(width: 8),
                            dossierBtn,
                          ],
                        );
                      },
                    ),
                  );
                },
              ),

            // Pagination controls (only if more than one page)
            if (filteredPatients.length > pageSize) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F766E),
                      side: BorderSide(color: safePage > 0 ? const Color(0xFF0F766E) : Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Previous', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    onPressed: safePage > 0 ? () => onPageChanged(safePage - 1) : null,
                  ),
                  Column(
                    children: [
                      Text(
                        'Page ${safePage + 1} of $totalPages',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                      Text(
                        '${filteredPatients.length} total results',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F766E),
                      side: BorderSide(color: safePage < totalPages - 1 ? const Color(0xFF0F766E) : Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text('Next', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    onPressed: safePage < totalPages - 1 ? () => onPageChanged(safePage + 1) : null,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================
  // SHARED CHART & CARD HELPERS
  // ==========================================
  Widget _buildPopStageGridCard(String title, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              count,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartHorizontalBar({
    required String label,
    required String subtitle,
    required int count,
    required int total,
    required Color color,
  }) {
    final pctValue = total > 0 ? (count / total) : 0.0;
    final pctText = total > 0 ? (count / total * 100).toStringAsFixed(1) : '0.0';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$count ($pctText%)',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pctValue.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: const Color(0xFFF1F5F9),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildRankedBarItem({
    required int rank,
    required String label,
    required int count,
    required int total,
    required Color color,
  }) {
    final pctValue = total > 0 ? (count / total) : 0.0;
    final pctText = total > 0 ? (count / total * 100).toStringAsFixed(1) : '0.0';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '#$rank',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$count ($pctText%)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pctValue.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: const Color(0xFFF1F5F9),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildModalityCard({
    required String title,
    required String count,
    required String desc,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 20),
              Text(
                count,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            desc,
            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  title,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBadge({required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

class _PatientDossierInspectionSheet extends ConsumerStatefulWidget {
  final PatientModel patient;
  final ClinicalVisitModel? cachedVisit;
  final VoidCallback onExportPdf;

  const _PatientDossierInspectionSheet({
    required this.patient,
    this.cachedVisit,
    required this.onExportPdf,
  });

  @override
  ConsumerState<_PatientDossierInspectionSheet> createState() => _PatientDossierInspectionSheetState();
}

class _PatientDossierInspectionSheetState extends ConsumerState<_PatientDossierInspectionSheet> {
  ClinicalVisitModel? _visit;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _visit = widget.cachedVisit;
    if (_visit == null) {
      _loadVisit();
    }
  }

  void _loadVisit() async {
    setState(() => _isLoading = true);
    try {
      final v = await ref.read(patientRepositoryProvider).getLatestClinicalVisit(
            widget.patient.patientId,
            patientUuid: widget.patient.id,
          );
      if (mounted) {
        setState(() {
          _visit = v;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.patient;
    final v = _visit;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.fullName,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              p.patientId,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E), fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Age: ${p.age}y • Ward: ${p.ward} • Mobile: ${p.mobile.isNotEmpty ? p.mobile : "N/A"}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F766E)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Section 1: Obstetric History
                        _buildSectionHeader('1. Obstetric History (प्रसूति इतिहास)'),
                        _buildInfoGrid([
                          {'label': 'Parity / Deliveries', 'val': '${v?.deliveries ?? "Not recorded"}'},
                          {'label': 'Living Children', 'val': '${v?.livingChildren ?? "Not recorded"}'},
                          {'label': 'Abortions', 'val': '${v?.abortions ?? "0"}'},
                          {'label': 'Marital Status', 'val': p.maritalStatus},
                        ]),

                        const SizedBox(height: 16),

                        // Section 2: Vitals Screening
                        _buildSectionHeader('2. Triage & Vitals (शारीरिक परीक्षण)'),
                        _buildInfoGrid([
                          {
                            'label': 'Blood Pressure',
                            'val': v?.systolicBp != null ? '${v!.systolicBp}/${v.diastolicBp} mmHg' : 'N/A'
                          },
                          {'label': 'Pulse', 'val': v?.pulse != null ? '${v!.pulse} bpm' : 'N/A'},
                          {'label': 'SpO2', 'val': v?.spo2 != null ? '${v!.spo2}%' : 'N/A'},
                          {'label': 'Blood Glucose', 'val': v?.glucose != null ? '${v!.glucose} mg/dL' : 'N/A'},
                          {'label': 'Urine Test', 'val': v?.urineTest ?? 'N/A'},
                          {'label': 'Pregnancy Test', 'val': v?.pregnancyTest ?? 'N/A'},
                        ]),

                        const SizedBox(height: 16),

                        // Section 3: POP-Q Staging
                        _buildSectionHeader('3. Pelvic Organ Prolapse (Baden-Walker POP-Q)'),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildPopBox('Anterior', 'Stage ${v?.popAnteriorStage ?? 0}'),
                              _buildPopBox('Apical', 'Stage ${v?.popMiddleStage ?? 0}'),
                              _buildPopBox('Posterior', 'Stage ${v?.popPosteriorStage ?? 0}'),
                              _buildPopBox(
                                'Overall Highest',
                                'Stage ${v?.highestPopStage ?? 0}',
                                isHighlight: true,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Section 4: Diagnoses & Management
                        _buildSectionHeader('4. Diagnoses & Management (निदान तथा उपचार)'),
                        if (v != null && v.diagnoses.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: v.diagnoses
                                .map((d) => Chip(
                                      label: Text(d, style: const TextStyle(fontSize: 11)),
                                      backgroundColor: const Color(0xFFE0F2FE),
                                    ))
                                .toList(),
                          )
                        else
                          const Text('No diagnoses specified.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),

                        const SizedBox(height: 10),

                        _buildInfoGrid([
                          {'label': 'Pessary Fitted', 'val': v?.pessaryType != null ? '${v!.pessaryType} (${v.pessarySize ?? ""})' : 'None'},
                          {'label': 'Surgical Referral', 'val': v?.surgicalReferral ?? 'None'},
                          {'label': 'Follow-Up', 'val': v?.followUpDestination ?? 'Health Post'},
                        ]),

                        if (v != null && v.medications.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Text('Dispensed Medications:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                          const SizedBox(height: 4),
                          ...v.medications.map((m) => Text('• $m', style: const TextStyle(fontSize: 12, color: Color(0xFF475569)))),
                        ],
                      ],
                    ),
                  ),
          ),

          // Bottom Action
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                label: const Text(
                  'Download Individual Dossier PDF (पिडिएफ डाउनलोड)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                onPressed: widget.onExportPdf,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
      ),
    );
  }

  Widget _buildInfoGrid(List<Map<String, String>> items) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        children: items.map((it) {
          return SizedBox(
            width: 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it['label']!, style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                const SizedBox(height: 2),
                Text(
                  it['val']!,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPopBox(String label, String value, {bool isHighlight = false}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isHighlight ? const Color(0xFF0F766E) : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isHighlight ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }
}
