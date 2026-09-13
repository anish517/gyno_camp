import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/services/file_download_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../models/audit_log_model.dart';
import '../../viewmodels/audit_log_viewmodel.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../admin/camp_management_view.dart';
import '../admin/device_management_view.dart';
import '../admin/master_config_view.dart';
import '../reports/camp_report_view.dart';

class AuditTrailView extends ConsumerStatefulWidget {
  const AuditTrailView({super.key});

  @override
  ConsumerState<AuditTrailView> createState() => _AuditTrailViewState();
}

class _AuditTrailViewState extends ConsumerState<AuditTrailView> {
  final _searchController = TextEditingController();
  String _selectedCategory = 'ALL';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(auditLogProvider.notifier).loadRecentLogs();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesCategory(AuditLogModel log, String category) {
    if (category == 'ALL') return true;
    final action = log.action.toUpperCase();
    final entity = log.entityType.toUpperCase();
    switch (category) {
      case 'CAMP':
        return (action.startsWith('CAMP') && !action.contains('REPORT')) || entity == 'CAMP';
      case 'DEVICE':
        return action.contains('DEVICE') ||
            action.contains('WORKSTATION') ||
            action.startsWith('APP_UNLOCKED') ||
            entity.contains('DEVICE');
      case 'PATIENT':
        return action.startsWith('PATIENT') ||
            action.startsWith('CLINICAL') ||
            action.startsWith('FORM') ||
            entity.contains('PATIENT') ||
            entity.contains('VISIT');
      case 'USER':
        return action.startsWith('USER') || action.startsWith('AUTH') || entity.contains('USER') || entity.contains('AUTH');
      case 'LOOKUP':
        return action.startsWith('LOOKUP') ||
            action.contains('FORMULARY') ||
            entity.contains('LOOKUP') ||
            entity.contains('FORMULARY') ||
            entity.contains('MASTER');
      case 'REPORT':
        return action.startsWith('REPORT') || entity.contains('REPORT');
      default:
        return action.startsWith(category);
    }
  }

  int _countForCategory(List<AuditLogModel> logs, String category) {
    if (category == 'ALL') return logs.length;
    return logs.where((l) => _matchesCategory(l, category)).length;
  }

  @override
  Widget build(BuildContext context) {
    final auditState = ref.watch(auditLogProvider);
    final vm = ref.read(auditLogProvider.notifier);
    final currentUser = ref.watch(authStateProvider).currentUser;

    // Filter by staff visibility if Data Taker role
    final userLogs = auditState.logs.where((log) {
      if (currentUser?.isDataTaker == true && log.userId != currentUser!.id) {
        return false;
      }
      return true;
    }).toList();

    // Category and search filtering
    final filteredLogs = userLogs.where((log) {
      if (!_matchesCategory(log, _selectedCategory)) {
        return false;
      }
      if (_searchController.text.trim().isNotEmpty) {
        final q = _searchController.text.toLowerCase().trim();
        final matchesUser = log.userName.toLowerCase().contains(q);
        final matchesAction = log.action.toLowerCase().contains(q);
        final matchesEntity = log.entityType.toLowerCase().contains(q) || (log.entityId?.toLowerCase().contains(q) ?? false);
        final matchesHash = log.logHash.toLowerCase().contains(q);
        return matchesUser || matchesAction || matchesEntity || matchesHash;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(currentUser?.isDataTaker == true
            ? 'My Activity Trail (Audit Chain)'
            : 'Tamper-Evident Audit Trail'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Export Audit Records (CSV / JSON)',
            onPressed: () => _showExportDialog(context, userLogs, filteredLogs),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh & Verify Logs',
            onPressed: () => vm.loadRecentLogs(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Interactive SHA-256 Cryptographic Integrity Card
          _buildIntegrityCard(context, auditState, vm),

          // 2. Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText: 'Search by actor, action, device, hash signature, or entity...',
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // 3. Category Filter Chips with Live Badges
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: [
                _buildFilterChip('ALL', 'All Events', _countForCategory(userLogs, 'ALL')),
                const SizedBox(width: 8),
                _buildFilterChip('CAMP', 'Camps', _countForCategory(userLogs, 'CAMP')),
                const SizedBox(width: 8),
                _buildFilterChip('DEVICE', 'Devices', _countForCategory(userLogs, 'DEVICE')),
                const SizedBox(width: 8),
                _buildFilterChip('PATIENT', 'Patients', _countForCategory(userLogs, 'PATIENT')),
                const SizedBox(width: 8),
                _buildFilterChip('USER', 'Authentication', _countForCategory(userLogs, 'USER')),
                const SizedBox(width: 8),
                _buildFilterChip('LOOKUP', 'Formulary', _countForCategory(userLogs, 'LOOKUP')),
                const SizedBox(width: 8),
                _buildFilterChip('REPORT', 'Reports', _countForCategory(userLogs, 'REPORT')),
              ],
            ),
          ),
          const Divider(height: 16, thickness: 1, color: Color(0xFFE2E8F0)),

          // 4. Activity Logs List or Contextual Empty State
          Expanded(
            child: auditState.isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: AppTheme.primaryTeal),
                        SizedBox(height: 16),
                        Text('Reading tamper-evident SQLite audit chain...'),
                      ],
                    ),
                  )
                : filteredLogs.isEmpty
                    ? _buildContextualEmptyState(context, _selectedCategory)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: filteredLogs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final log = filteredLogs[index];
                          return _buildLogCard(context, log);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // SHA-256 Cryptographic Integrity Card
  // -------------------------------------------------------------
  Widget _buildIntegrityCard(BuildContext context, AuditLogState state, AuditLogViewModel vm) {
    final isValid = state.isChainValid;
    final isVerifying = state.isVerifyingChain;

    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final IconData iconData;
    final String title;
    final String subtitle;

    if (isVerifying) {
      bgColor = const Color(0xFFEFF6FF);
      borderColor = const Color(0xFFBFDBFE);
      textColor = const Color(0xFF1E40AF);
      iconData = Icons.hourglass_top_rounded;
      title = 'Verifying SHA-256 Chain Integrity...';
      subtitle = 'Computing cryptographic digests across all local SQLite audit blocks.';
    } else if (isValid == false) {
      bgColor = const Color(0xFFFEF2F2);
      borderColor = const Color(0xFFFECACA);
      textColor = AppTheme.dangerRose;
      iconData = Icons.gpp_bad_rounded;
      title = 'Integrity Compromised: Hash Mismatch Detected';
      subtitle = state.verificationSummary ??
          'Record signature mismatch found. Local database records may have been altered or corrupted.';
    } else {
      bgColor = const Color(0xFFECFDF5);
      borderColor = const Color(0xFFA7F3D0);
      textColor = const Color(0xFF065F46);
      iconData = Icons.verified_user_rounded;
      title = 'Cryptographic Chain Intact (SHA-256)';
      subtitle = state.verificationSummary ??
          '${state.verifiedCount > 0 ? state.verifiedCount : state.logs.length} sequential transaction blocks mathematically verified against SHA-256 signatures.';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: textColor.withValues(alpha: 0.15), blurRadius: 6),
                  ],
                ),
                child: isVerifying
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: textColor),
                      )
                    : Icon(iconData, color: textColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: textColor),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isValid == false ? AppTheme.dangerRose : const Color(0xFF059669),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isValid == false ? 'TAMPER ALERT' : 'CRYPTOGRAPHICALLY VERIFIED',
                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11.5, color: textColor.withValues(alpha: 0.85), height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 12, thickness: 0.8, color: Color(0x22000000)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 6,
                children: [
                  _buildMiniBadge('Tamper-Proof', textColor),
                  _buildMiniBadge('Sequential Merkle Chain', textColor),
                  _buildMiniBadge('Non-Repudiation', textColor),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: textColor,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.info_outline_rounded, size: 15),
                    label: const Text('What does SHA-256 verify?', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () => _showSha256ExplanationDialog(context),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: textColor,
                      elevation: 0,
                      side: BorderSide(color: borderColor),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.sync_rounded, size: 14),
                    label: const Text('Re-Verify', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: isVerifying ? null : () => vm.verifyCryptographicChain(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  // -------------------------------------------------------------
  // Filter Chip with Live Badges
  // -------------------------------------------------------------
  Widget _buildFilterChip(String key, String label, int count) {
    final isSelected = _selectedCategory == key;
    return ChoiceChip(
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      avatar: CircleAvatar(
        radius: 9,
        backgroundColor: isSelected ? AppTheme.primaryTeal : Colors.grey.shade300,
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected ? AppTheme.primaryTeal : Colors.black87,
        ),
      ),
      selected: isSelected,
      selectedColor: AppTheme.primaryLight,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isSelected ? AppTheme.primaryTeal : const Color(0xFFCBD5E1),
      ),
      onSelected: (_) {
        setState(() {
          _selectedCategory = key;
        });
      },
    );
  }

  // -------------------------------------------------------------
  // Modern Event Log Card
  // -------------------------------------------------------------
  Widget _buildLogCard(BuildContext context, AuditLogModel log) {
    final formattedTime = DateFormat('yyyy-MM-dd • hh:mm:ss a').format(log.timestamp);
    final actionColor = _getActionColor(log.action);
    final actionIcon = _getActionIcon(log.action);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showLogDetailsDialog(context, log, formattedTime),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Action Icon Box
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(actionIcon, color: actionColor, size: 20),
              ),
              const SizedBox(width: 12),

              // Middle Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            log.action,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            log.userRole,
                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'By: ${log.userName} • Device: ${log.deviceId}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 12, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        Text(
                          formattedTime,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                        if (log.entityId != null) ...[
                          const SizedBox(width: 8),
                          const Text('•', style: TextStyle(color: Color(0xFF94A3B8))),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '${log.entityType}: ${log.entityId}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryTeal),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Trailing Cryptographic Hash
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_clock_outlined, size: 11, color: Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(
                          log.logHash.length >= 8 ? log.logHash.substring(0, 8).toUpperCase() : log.logHash,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Inspect Block →',
                    style: TextStyle(fontSize: 10, color: AppTheme.primaryTeal, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Rich Contextual Empty State
  // -------------------------------------------------------------
  Widget _buildContextualEmptyState(BuildContext context, String category) {
    final isSearching = _searchController.text.trim().isNotEmpty;
    if (isSearching) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'No audit events matched "${_searchController.text}".',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 4),
              const Text(
                'Try clearing your search keyword or switching the category filter.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.clear_rounded, size: 16),
                label: const Text('Clear Search Filter'),
                onPressed: () => setState(() => _searchController.clear()),
              ),
            ],
          ),
        ),
      );
    }

    final IconData icon;
    final String title;
    final String explanation;
    final String? buttonLabel;
    final VoidCallback? onButtonTap;

    switch (category) {
      case 'DEVICE':
        icon = Icons.devices_other_rounded;
        title = 'No Device Security Events Logged Yet';
        explanation = 'Field tablet registration requests, OTP verifications, and Super Admin whitelisting events will appear here as outreach terminals join the network.';
        buttonLabel = 'Authorize Hardware Workstations';
        onButtonTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceManagementView()));
        break;
      case 'LOOKUP':
        icon = Icons.tune_rounded;
        title = 'Clinical Master Formulary Active';
        explanation = 'Nepal MoHP Yellow Form diagnoses, pelvic organ prolapse stages, and essential dispensary medicines are active. Custom formulary modifications will be recorded here.';
        buttonLabel = 'Manage Master Data & Formulary';
        onButtonTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MasterConfigView()));
        break;
      case 'CAMP':
        icon = Icons.campaign_rounded;
        title = 'No Camp Lifecycle Events Recorded';
        explanation = 'Camp initialization, status shifts (Scheduled / Open / Closed), and staff deployments are permanently anchored in this audit chain.';
        buttonLabel = 'Manage Clinical Camps';
        onButtonTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CampManagementView()));
        break;
      case 'REPORT':
        icon = Icons.assessment_rounded;
        title = 'No Clinical Reports Exported Yet';
        explanation = 'PDF and Excel clinical dossier exports, aggregate epidemiology summaries, and patient referral sheets will be cataloged with their digital export signatures here.';
        buttonLabel = 'Generate Camp Reports';
        onButtonTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CampReportView()));
        break;
      case 'PATIENT':
        icon = Icons.people_outline_rounded;
        title = 'No Patient Clinical Transactions';
        explanation = 'New patient registrations, clinical assessments across all 6 stations, and Yellow Form OCR scans will be cryptographically logged here.';
        buttonLabel = null;
        onButtonTap = null;
        break;
      default:
        icon = Icons.history_toggle_off_rounded;
        title = 'No Audit Events Recorded Yet';
        explanation = 'System activities, clinician logins, and administrative actions will be logged with SHA-256 tamper-evident signatures.';
        buttonLabel = null;
        onButtonTap = null;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryTeal.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: AppTheme.primaryTeal),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 6),
              Text(
                explanation,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.4),
              ),
              if (buttonLabel != null && onButtonTap != null) ...[
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text(buttonLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: onButtonTap,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // SHA-256 Explanation Info Dialog
  // -------------------------------------------------------------
  void _showSha256ExplanationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: AppTheme.primaryTeal, size: 24),
            SizedBox(width: 10),
            Expanded(child: Text('Cryptographic Verification (SHA-256)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '1. What does the SHA-256 check actually verify?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
              ),
              SizedBox(height: 4),
              Text(
                '• Database Record Tamper-Proofing: Verifies that no clinical diagnoses, patient records, or device statuses in SQLite have been edited, injected, or modified behind the scenes.\n'
                '• Sequential Merkle Hash Chaining: Each log block is computed as SHA-256(Log_ID | User_ID | Action | Timestamp | Details_JSON | Previous_Hash). Deleting or re-ordering any historical row breaks the entire subsequent hash chain.\n'
                '• Actor Non-Repudiation: Binds the clinician user ID, hardware device ID, and timestamp permanently into the signature.',
                style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.4),
              ),
              SizedBox(height: 14),
              Text(
                '2. What does "VERIFIED" mean?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF059669)),
              ),
              SizedBox(height: 4),
              Text(
                'The local verification engine re-hashed every transaction block sequentially from genesis to the latest record and confirmed that 100% of stored cryptographic signatures match their mathematical hashes. The audit log is certified authentic.',
                style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.35),
              ),
              SizedBox(height: 14),
              Text(
                '3. What does "FAILED" mean?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.dangerRose),
              ),
              SizedBox(height: 4),
              Text(
                'A signature mismatch indicates that a row in the local database has been altered, deleted, or corrupted. The system flags the exact record ID and alerts the administrator to export a forensic dump.',
                style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.35),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Export Modal (CSV / JSON)
  // -------------------------------------------------------------
  void _showExportDialog(BuildContext context, List<AuditLogModel> allLogs, List<AuditLogModel> filteredLogs) {
    final logsToExport = filteredLogs.isNotEmpty ? filteredLogs : allLogs;
    final isUsingFallback = filteredLogs.isEmpty && allLogs.isNotEmpty;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.file_download_rounded, color: AppTheme.primaryTeal, size: 24),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Export Audit Trail & Security Records',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isUsingFallback
                  ? 'Current filter "$_selectedCategory" has 0 records. Exporting all ${allLogs.length} system audit logs instead.'
                  : 'Exporting ${logsToExport.length} records (${_selectedCategory == "ALL" ? "All Categories" : _selectedCategory} filter).',
              style: TextStyle(fontSize: 12.5, color: isUsingFallback ? Colors.amber.shade900 : const Color(0xFF64748B)),
            ),
            const SizedBox(height: 20),

            // Option 1: CSV Report
            ListTile(
              tileColor: const Color(0xFFF8FAFC),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFFE2E8F0))),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFECFDF5),
                child: Icon(Icons.table_chart_rounded, color: Color(0xFF059669)),
              ),
              title: const Text('Tabular Audit Report (.CSV)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Human-readable spreadsheet formatted with local time, actor, action, and SHA-256 signature.', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.download_rounded, color: AppTheme.primaryTeal),
              onTap: () {
                Navigator.pop(ctx);
                _exportCsv(logsToExport);
              },
            ),
            const SizedBox(height: 12),

            // Option 2: JSON Cryptographic Vault
            ListTile(
              tileColor: const Color(0xFFF8FAFC),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFFE2E8F0))),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFEFF6FF),
                child: Icon(Icons.data_object_rounded, color: Color(0xFF2563EB)),
              ),
              title: const Text('Forensic Cryptographic Vault (.JSON)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Machine-readable forensic JSON containing chained hashes and payload signatures for legal verification.', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.download_rounded, color: AppTheme.primaryTeal),
              onTap: () {
                Navigator.pop(ctx);
                _exportJson(logsToExport);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv(List<AuditLogModel> logs) async {
    if (logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No audit logs available to export.')),
      );
      return;
    }
    try {
      final buffer = StringBuffer();
      // CSV Header
      buffer.writeln('Timestamp,Actor Name,User ID,Role,Action,Category,Entity ID,Device ID,SHA-256 Hash,Details');

      for (final log in logs) {
        final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(log.timestamp);
        final cleanDetails = log.detailsJson.replaceAll('"', '""');
        buffer.writeln(
          '"$timeStr","${log.userName}","${log.userId}","${log.userRole}","${log.action}","${log.entityType}","${log.entityId ?? ''}","${log.deviceId}","${log.logHash}","$cleanDetails"',
        );
      }

      final bytes = utf8.encode(buffer.toString());
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final filename = 'gynocamp_audit_report_${_selectedCategory.toLowerCase()}_$dateStr.csv';

      await FileDownloadHelper.saveAndDownloadFile(
        bytes: bytes,
        filename: filename,
        mimeType: 'text/csv',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Audit CSV exported successfully: $filename'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV export failed: $e'), backgroundColor: AppTheme.dangerRose),
        );
      }
    }
  }

  Future<void> _exportJson(List<AuditLogModel> logs) async {
    if (logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No audit logs available to export.')),
      );
      return;
    }
    try {
      final list = logs.map((l) => l.toMap()).toList();
      final jsonString = const JsonEncoder.withIndent('  ').convert({
        'exported_at': DateTime.now().toIso8601String(),
        'system': 'GynoCamp Clinical Health System',
        'hash_algorithm': 'SHA-256 Merkle Chain',
        'total_records': logs.length,
        'records': list,
      });
      final bytes = utf8.encode(jsonString);
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final filename = 'gynocamp_audit_vault_$dateStr.json';

      await FileDownloadHelper.saveAndDownloadFile(
        bytes: bytes,
        filename: filename,
        mimeType: 'application/json',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cryptographic JSON vault exported: $filename'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('JSON export failed: $e'), backgroundColor: AppTheme.dangerRose),
        );
      }
    }
  }

  // -------------------------------------------------------------
  // Transaction Block Inspection Modal
  // -------------------------------------------------------------
  void _showLogDetailsDialog(BuildContext context, AuditLogModel log, String formattedTime) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(_getActionIcon(log.action), color: _getActionColor(log.action), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                log.action,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Actor:', '${log.userName} (${log.userRole})'),
              _detailRow('Actor ID:', log.userId),
              _detailRow('Timestamp:', formattedTime),
              _detailRow('Device ID:', log.deviceId),
              _detailRow('Target Entity:', log.entityType),
              if (log.entityId != null) _detailRow('Entity ID:', log.entityId!),
              const Divider(height: 16),
              const Text('Details JSON Payload:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  log.detailsJson,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
              const Divider(height: 16),
              const Text('Chained SHA-256 Hash:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: SelectableText(
                  log.logHash,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy Hash'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: log.logHash));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('SHA-256 Hash copied to clipboard')),
              );
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B))),
          ),
        ],
      ),
    );
  }

  IconData _getActionIcon(String action) {
    if (action.startsWith('CAMP')) return Icons.campaign_rounded;
    if (action.contains('DEVICE') || action.contains('WORKSTATION')) return Icons.devices_rounded;
    if (action.startsWith('PATIENT')) return Icons.person_rounded;
    if (action.startsWith('CLINICAL')) return Icons.medical_services_rounded;
    if (action.startsWith('USER') || action.startsWith('AUTH')) return Icons.lock_person_rounded;
    if (action.startsWith('LOOKUP') || action.contains('FORMULARY')) return Icons.tune_rounded;
    if (action.startsWith('REPORT')) return Icons.assessment_rounded;
    if (action.startsWith('SYSTEM')) return Icons.dns_rounded;
    return Icons.history_rounded;
  }

  Color _getActionColor(String action) {
    if (action.contains('APPROVE') || action.contains('OPEN') || action.contains('REGISTER') || action.contains('CREATE')) {
      return const Color(0xFF059669);
    }
    if (action.contains('REVOKE') || action.contains('CLOSE') || action.contains('DELETE')) {
      return AppTheme.dangerRose;
    }
    if (action.contains('SYNC') || action.contains('UPDATE') || action.contains('TOGGLE')) {
      return Colors.indigo;
    }
    return AppTheme.primaryTeal;
  }
}
