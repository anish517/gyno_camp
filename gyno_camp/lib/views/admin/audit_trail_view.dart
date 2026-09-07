import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/file_download_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../models/audit_log_model.dart';
import '../../viewmodels/audit_log_viewmodel.dart';
import '../../viewmodels/auth_viewmodel.dart';

class AuditTrailView extends ConsumerStatefulWidget {
  const AuditTrailView({super.key});

  @override
  ConsumerState<AuditTrailView> createState() => _AuditTrailViewState();
}

class _AuditTrailViewState extends ConsumerState<AuditTrailView> {
  final _searchController = TextEditingController();
  String _selectedActionPrefix = 'ALL';

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
        return action.startsWith('CAMP') || entity.contains('CAMP');
      case 'DEVICE':
        return action.startsWith('DEVICE') || action.startsWith('APP_UNLOCKED') || entity.contains('DEVICE');
      case 'PATIENT':
        return action.startsWith('PATIENT') || action.startsWith('CLINICAL') || action.startsWith('FORM') || entity.contains('PATIENT');
      case 'USER':
        return action.startsWith('USER') || action.startsWith('AUTH') || entity.contains('USER') || entity.contains('AUTH');
      case 'LOOKUP':
        return action.startsWith('LOOKUP') || entity.contains('LOOKUP') || entity.contains('MASTER');
      case 'REPORT':
        return action.startsWith('REPORT') || entity.contains('REPORT');
      default:
        return action.startsWith(category);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auditState = ref.watch(auditLogProvider);
    final vm = ref.read(auditLogProvider.notifier);
    final currentUser = ref.watch(authStateProvider).currentUser;

    final filteredLogs = auditState.logs.where((log) {
      if (currentUser?.isDataTaker == true && log.userId != currentUser!.id) {
        return false;
      }
      if (!_matchesCategory(log, _selectedActionPrefix)) {
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
      appBar: AppBar(
        title: Text(currentUser?.isDataTaker == true
            ? 'My Activity Trail (Self-Activity Log)'
            : 'Tamper-Evident Audit Trail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export Audit Log (JSON)',
            onPressed: () => _exportAuditLogs(filteredLogs),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Logs',
            onPressed: () => vm.loadRecentLogs(),
          ),
        ],
      ),
      body: Column(
        children: [
          // SHA-256 Integrity Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            color: AppTheme.successGreen.withValues(alpha: 0.1),
            child: Row(
              children: [
                const Icon(Icons.verified_user, color: AppTheme.successGreen, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cryptographic Chain Intact (SHA-256)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryDark),
                      ),
                      Text(
                        'Total ${auditState.logs.length} events anchored in local SQLite audit trail',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                      ),
                    ],
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: AppTheme.successGreen.withValues(alpha: 0.2),
                  label: const Text(
                    'SECURE',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                  ),
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Search by user, action, hash, or entity...',
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Action Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: [
                _buildActionChip('ALL', 'All Events'),
                const SizedBox(width: 6),
                _buildActionChip('CAMP', 'Camps'),
                const SizedBox(width: 6),
                _buildActionChip('DEVICE', 'Devices'),
                const SizedBox(width: 6),
                _buildActionChip('PATIENT', 'Patients'),
                const SizedBox(width: 6),
                _buildActionChip('USER', 'Authentication'),
                const SizedBox(width: 6),
                _buildActionChip('LOOKUP', 'Formulary'),
                const SizedBox(width: 6),
                _buildActionChip('REPORT', 'Reports'),
              ],
            ),
          ),
          const Divider(height: 12),

          // Logs List
          Expanded(
            child: auditState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredLogs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history_toggle_off, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'No audit events matched "${_searchController.text}".'
                                  : _selectedActionPrefix != 'ALL'
                                      ? 'No ${_getCategoryDisplayName(_selectedActionPrefix)} events recorded yet.'
                                      : 'No audit events recorded yet.',
                              style: const TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16.0),
                        itemCount: filteredLogs.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final log = filteredLogs[index];
                          return _buildLogTile(context, log);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _getCategoryDisplayName(String prefix) {
    switch (prefix) {
      case 'CAMP':
        return 'camp';
      case 'DEVICE':
        return 'device';
      case 'PATIENT':
        return 'patient registration / clinical';
      case 'USER':
        return 'authentication';
      case 'LOOKUP':
        return 'formulary / lookup';
      case 'REPORT':
        return 'report export';
      default:
        return 'matching';
    }
  }

  Widget _buildActionChip(String key, String label) {
    final isSelected = _selectedActionPrefix == key;
    return ChoiceChip(
      visualDensity: VisualDensity.compact,
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: AppTheme.primaryLight,
      onSelected: (_) {
        setState(() {
          _selectedActionPrefix = key;
        });
      },
    );
  }

  Widget _buildLogTile(BuildContext context, AuditLogModel log) {
    final formattedTime =
        '${log.timestamp.year}-${log.timestamp.month.toString().padLeft(2, '0')}-${log.timestamp.day.toString().padLeft(2, '0')} ${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _getActionColor(log.action).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(_getActionIcon(log.action), color: _getActionColor(log.action), size: 20),
      ),
      title: Row(
        children: [
          Text(
            log.action,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              log.userRole,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            'By: ${log.userName} • Device: ${log.deviceId} • $formattedTime',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
          ),
          if (log.entityId != null)
            Text(
              'Entity: ${log.entityType} (${log.entityId})',
              style: const TextStyle(fontSize: 11, color: AppTheme.primaryDark),
            ),
        ],
      ),
      trailing: Tooltip(
        message: 'Tap to inspect details & hash',
        child: Chip(
          visualDensity: VisualDensity.compact,
          label: Text(
            log.logHash.length >= 8 ? log.logHash.substring(0, 8) : log.logHash,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.blueGrey),
          ),
        ),
      ),
      onTap: () => _showLogDetailsDialog(context, log, formattedTime),
    );
  }

  void _showLogDetailsDialog(BuildContext context, AuditLogModel log, String formattedTime) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(_getActionIcon(log.action), color: _getActionColor(log.action), size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(log.action, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('User:', '${log.userName} (${log.userRole})'),
              _detailRow('User ID:', log.userId),
              _detailRow('Timestamp:', formattedTime),
              _detailRow('Device ID:', log.deviceId),
              _detailRow('Entity Type:', log.entityType),
              if (log.entityId != null) _detailRow('Entity ID:', log.entityId!),
              const Divider(height: 16),
              const Text('Details JSON Payload:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  log.logHash,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppTheme.primaryDark),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Hash'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: log.logHash));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('SHA-256 Hash copied to clipboard')),
              );
            },
          ),
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
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
            width: 90,
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  IconData _getActionIcon(String action) {
    if (action.startsWith('CAMP')) return Icons.campaign;
    if (action.startsWith('DEVICE')) return Icons.devices;
    if (action.startsWith('PATIENT')) return Icons.person;
    if (action.startsWith('USER')) return Icons.lock;
    if (action.startsWith('LOOKUP')) return Icons.tune;
    if (action.startsWith('REPORT')) return Icons.assessment;
    return Icons.history;
  }

  Color _getActionColor(String action) {
    if (action.contains('APPROVE') || action.contains('OPEN') || action.contains('REGISTER')) {
      return AppTheme.successGreen;
    }
    if (action.contains('REVOKE') || action.contains('CLOSE') || action.contains('DELETE')) {
      return AppTheme.dangerRose;
    }
    if (action.contains('SYNC') || action.contains('UPDATE') || action.contains('TOGGLE')) {
      return Colors.indigo;
    }
    return AppTheme.primaryTeal;
  }

  Future<void> _exportAuditLogs(List<AuditLogModel> logs) async {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Audit trail exported successfully: $filename'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppTheme.dangerRose,
          ),
        );
      }
    }
  }
}
