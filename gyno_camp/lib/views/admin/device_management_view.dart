import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/device_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/device_management_viewmodel.dart';

class DeviceManagementView extends ConsumerStatefulWidget {
  const DeviceManagementView({super.key});

  @override
  ConsumerState<DeviceManagementView> createState() => _DeviceManagementViewState();
}

class _DeviceManagementViewState extends ConsumerState<DeviceManagementView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceState = ref.watch(deviceManagementProvider);
    final vm = ref.read(deviceManagementProvider.notifier);
    final user = ref.watch(authStateProvider).currentUser;

    // Filter devices based on status tab and search query
    final filteredDevices = deviceState.filteredDevices.where((d) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();
      final matchesName = d.deviceName.toLowerCase().contains(q);
      final matchesModel = d.model.toLowerCase().contains(q);
      final matchesFp = d.hardwareFingerprint.toLowerCase().contains(q);
      final matchesId = d.deviceId.toLowerCase().contains(q);
      final matchesStaff = (d.registeredByName ?? '').toLowerCase().contains(q);
      return matchesName || matchesModel || matchesFp || matchesId || matchesStaff;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device Whitelist & Hardware Security', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Cluster Whitelist & Field Hardware Authorization (उपकरण प्रमाणीकरण)', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Devices',
            onPressed: () => vm.loadDevices(),
          ),
        ],
      ),
      body: deviceState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // KPI Counters Banner
                      Row(
                        children: [
                          Expanded(
                            child: _buildCountCard(
                              label: 'Pending Approval',
                              nepaliLabel: 'अनुमोदन बाँकी',
                              count: deviceState.pendingCount,
                              color: AppTheme.warningAmber,
                              icon: Icons.hourglass_top_rounded,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildCountCard(
                              label: 'Authorized',
                              nepaliLabel: 'स्वीकृत उपकरण',
                              count: deviceState.approvedCount,
                              color: AppTheme.successGreen,
                              icon: Icons.verified_rounded,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildCountCard(
                              label: 'Revoked',
                              nepaliLabel: 'रद्द गरिएको',
                              count: deviceState.revokedCount,
                              color: AppTheme.dangerRose,
                              icon: Icons.block_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Real-time Search Toolbar
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.borderLight),
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search by device name, model, hardware ID, or staff...',
                            hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryLight),
                            prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Colors.blueGrey),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.grey),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip(ref, 'ALL', 'All Devices (${deviceState.devices.length})'),
                            const SizedBox(width: 8),
                            _buildFilterChip(ref, AppConstants.deviceStatusPendingApproval, 'Pending (${deviceState.pendingCount})'),
                            const SizedBox(width: 8),
                            _buildFilterChip(ref, AppConstants.deviceStatusApproved, 'Approved (${deviceState.approvedCount})'),
                            const SizedBox(width: 8),
                            _buildFilterChip(ref, AppConstants.deviceStatusRevoked, 'Revoked (${deviceState.revokedCount})'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Device Cards List or Empty States
                      if (filteredDevices.isEmpty)
                        Card(
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: AppTheme.borderLight),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF1F5F9),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.devices_other_rounded,
                                    size: 40,
                                    color: Colors.blueGrey.shade400,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'No devices match "$_searchQuery"'
                                      : 'No hardware devices found for this filter.',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'Try adjusting your search terms or clearing the filter.'
                                      : 'When tablets request registration in the field, they will appear here.',
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
                                  textAlign: TextAlign.center,
                                ),
                                if (_searchQuery.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.clear_rounded, size: 16),
                                    label: const Text('Clear Search'),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _searchQuery = '';
                                      });
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      else
                        ...filteredDevices.map(
                          (dev) => _buildDeviceCard(context, ref, dev, user?.id ?? 'admin-user'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildCountCard({
    required String label,
    required String nepaliLabel,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppTheme.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 13, color: color),
                ),
                const Spacer(),
                Text(
                  '$count',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
            ),
            Text(
              nepaliLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 8.5, color: AppTheme.textSecondaryLight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(WidgetRef ref, String statusKey, String label) {
    final currentFilter = ref.watch(deviceManagementProvider).filterStatus;
    final isSelected = currentFilter == statusKey;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : const Color(0xFF475569),
        ),
      ),
      selected: isSelected,
      selectedColor: AppTheme.primaryTeal,
      backgroundColor: Colors.white,
      side: BorderSide(color: isSelected ? AppTheme.primaryTeal : AppTheme.borderLight),
      showCheckmark: false,
      onSelected: (_) {
        ref.read(deviceManagementProvider.notifier).setFilter(statusKey);
      },
    );
  }

  Widget _buildStatusBadge(DeviceActivationStatus status, Color statusColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status == DeviceActivationStatus.approved
                ? Icons.verified_rounded
                : (status == DeviceActivationStatus.pendingApproval
                    ? Icons.hourglass_top_rounded
                    : Icons.block_rounded),
            size: 11,
            color: statusColor,
          ),
          const SizedBox(width: 4),
          Text(
            status == DeviceActivationStatus.pendingApproval ? 'Pending Approval' : status.displayNameEn,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(BuildContext context, WidgetRef ref, DeviceModel dev, String adminUserId) {
    final vm = ref.read(deviceManagementProvider.notifier);
    final statusColor = _getStatusColor(dev.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: dev.isApproved
              ? AppTheme.primaryTeal.withValues(alpha: 0.3)
              : (dev.status == DeviceActivationStatus.pendingApproval
                  ? AppTheme.warningAmber.withValues(alpha: 0.6)
                  : Colors.grey.shade200),
          width: dev.status == DeviceActivationStatus.pendingApproval ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDeviceDetailsDialog(context, dev, vm, adminUserId),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device Header: Icon, Name, Model, Status Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      dev.model.toLowerCase().contains('tab') || dev.model.toLowerCase().contains('pad')
                          ? Icons.tablet_mac_rounded
                          : Icons.devices_rounded,
                      color: statusColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                dev.deviceName,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _buildStatusBadge(dev.status, statusColor),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Model: ${dev.model} • ID: ${dev.deviceId}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Hardware Fingerprint Monospace Display with 1-tap Copy
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.fingerprint_rounded, size: 16, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    const Text('Fingerprint: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    Expanded(
                      child: Text(
                        dev.hardwareFingerprint,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.black87),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Tooltip(
                      message: 'Copy Hardware Fingerprint',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: dev.hardwareFingerprint));
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Hardware fingerprint copied to clipboard.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(3.0),
                          child: Icon(Icons.copy_rounded, size: 14, color: Colors.blueGrey),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Registered Info Row
              Row(
                children: [
                  const Icon(Icons.person_outline_rounded, size: 14, color: Colors.blueGrey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Registered by: ${(dev.registeredByName != null && dev.registeredByName!.isNotEmpty) ? dev.registeredByName! : "Field Staff"}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.access_time_rounded, size: 13, color: Colors.blueGrey),
                  const SizedBox(width: 4),
                  Text(
                    '${dev.registeredAt.year}-${dev.registeredAt.month.toString().padLeft(2, '0')}-${dev.registeredAt.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                  ),
                ],
              ),
              const Divider(height: 20),

              // Actions (using Wrap to completely eliminate RenderFlex overflow on narrow mobile screens)
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.info_outline_rounded, size: 15),
                    label: const Text('Details', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: () => _showDeviceDetailsDialog(context, dev, vm, adminUserId),
                  ),
                  if (dev.status == DeviceActivationStatus.pendingApproval) ...[
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Approve Device'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.successGreen,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      onPressed: () => _confirmApprove(context, vm, dev, adminUserId),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.dangerRose,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      onPressed: () => _confirmRevoke(context, vm, dev, adminUserId, isReject: true),
                    ),
                  ],
                  if (dev.status == DeviceActivationStatus.approved) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.block, size: 16),
                      label: const Text('Revoke Access'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.dangerRose,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      onPressed: () => _confirmRevoke(context, vm, dev, adminUserId),
                    ),
                  ],
                  if (dev.status == DeviceActivationStatus.revoked) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.replay, size: 16),
                      label: const Text('Re-Authorize'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryTeal,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      onPressed: () => _confirmApprove(context, vm, dev, adminUserId),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeviceDetailsDialog(BuildContext context, DeviceModel dev, DeviceManagementViewModel vm, String adminUserId) {
    final statusColor = _getStatusColor(dev.status);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.tablet_mac_rounded, color: statusColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dev.deviceName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Device Security Specification', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Device Identifier', dev.deviceId),
              _buildDetailRow('Hardware Model', dev.model),
              _buildDetailRow('Activation Status', dev.status.displayNameEn, valueColor: statusColor),
              _buildDetailRow('Hardware Fingerprint', dev.hardwareFingerprint, isMonospace: true),
              _buildDetailRow(
                'Registered By',
                (dev.registeredByName != null && dev.registeredByName!.isNotEmpty)
                    ? dev.registeredByName!
                    : 'Field Staff (${dev.registeredByUserId ?? "Unknown"})',
              ),
              _buildDetailRow(
                'Registration Timestamp',
                dev.registeredAt.toLocal().toString().split('.')[0],
              ),
              if (dev.approvedAt != null)
                _buildDetailRow(
                  'Approval Timestamp',
                  '${dev.approvedAt!.toLocal().toString().split('.')[0]} (${dev.approvedByUserId ?? "Admin"})',
                ),
              _buildDetailRow(
                'App Lock Security',
                dev.hasPinSet ? 'Encrypted Local PIN Configured' : 'No Local App Lock PIN',
                valueColor: dev.hasPinSet ? AppTheme.successGreen : Colors.grey,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (dev.status == DeviceActivationStatus.pendingApproval)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
              onPressed: () {
                Navigator.pop(ctx);
                _confirmApprove(context, vm, dev, adminUserId);
              },
              child: const Text('Approve Device'),
            ),
          if (dev.status == DeviceActivationStatus.approved)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose),
              onPressed: () {
                Navigator.pop(ctx);
                _confirmRevoke(context, vm, dev, adminUserId);
              },
              child: const Text('Revoke Access'),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isMonospace = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontFamily: isMonospace ? 'monospace' : null,
                fontWeight: FontWeight.w500,
                color: valueColor ?? const Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmApprove(BuildContext context, DeviceManagementViewModel vm, DeviceModel dev, String adminUserId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Authorize Field Device?'),
        content: Text(
          'Allowing "${dev.deviceName}" (${dev.model}) will cryptographically bind it to the Gynocamp cluster and permit offline clinical intake.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await vm.approveDevice(dev.deviceId, adminUserId: adminUserId);
              if (success && context.mounted) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Device "${dev.deviceName}" approved successfully.'),
                    backgroundColor: AppTheme.successGreen,
                  ),
                );
              }
            },
            child: const Text('Approve & Whitelist'),
          ),
        ],
      ),
    );
  }

  void _confirmRevoke(BuildContext context, DeviceManagementViewModel vm, DeviceModel dev, String adminUserId, {bool isReject = false}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isReject ? 'Reject Device Registration?' : 'Revoke Device Access?'),
        content: Text(
          isReject
              ? 'Rejecting "${dev.deviceName}" will discard this registration request.'
              : 'Revoking access will immediately disable data intake and synchronization on this tablet.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await vm.revokeDevice(dev.deviceId, adminUserId: adminUserId);
              if (success && context.mounted) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Device "${dev.deviceName}" access revoked.'),
                    backgroundColor: AppTheme.dangerRose,
                  ),
                );
              }
            },
            child: Text(isReject ? 'Reject' : 'Revoke Access'),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(DeviceActivationStatus status) {
    switch (status) {
      case DeviceActivationStatus.approved:
        return AppTheme.successGreen;
      case DeviceActivationStatus.pendingApproval:
      case DeviceActivationStatus.pendingOtp:
        return AppTheme.warningAmber;
      case DeviceActivationStatus.revoked:
        return AppTheme.dangerRose;
      case DeviceActivationStatus.unregistered:
        return Colors.grey;
    }
  }
}
