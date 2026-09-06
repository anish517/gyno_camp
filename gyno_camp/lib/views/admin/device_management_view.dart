import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/device_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/device_management_viewmodel.dart';

class DeviceManagementView extends ConsumerWidget {
  const DeviceManagementView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(deviceManagementProvider);
    final vm = ref.read(deviceManagementProvider.notifier);
    final user = ref.watch(authStateProvider).currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Whitelist & Hardware Security'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Devices',
            onPressed: () => vm.loadDevices(),
          ),
        ],
      ),
      body: deviceState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                          count: deviceState.pendingCount,
                          color: AppTheme.warningAmber,
                          icon: Icons.hourglass_top,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildCountCard(
                          label: 'Authorized',
                          count: deviceState.approvedCount,
                          color: AppTheme.successGreen,
                          icon: Icons.verified,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildCountCard(
                          label: 'Revoked',
                          count: deviceState.revokedCount,
                          color: AppTheme.dangerRose,
                          icon: Icons.block,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

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

                  // Device Cards List
                  if (deviceState.filteredDevices.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          children: [
                            Icon(Icons.devices_other, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            const Text('No hardware devices found for this filter.', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    )
                  else
                    ...deviceState.filteredDevices.map(
                      (dev) => _buildDeviceCard(context, ref, dev, user?.id ?? 'admin-user'),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildCountCard({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const Spacer(),
                Text(
                  '$count',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
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
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: AppTheme.primaryLight,
      onSelected: (_) {
        ref.read(deviceManagementProvider.notifier).setFilter(statusKey);
      },
    );
  }

  Widget _buildDeviceCard(BuildContext context, WidgetRef ref, DeviceModel dev, String adminUserId) {
    final vm = ref.read(deviceManagementProvider.notifier);
    final statusColor = _getStatusColor(dev.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: dev.isApproved ? AppTheme.primaryTeal.withValues(alpha: 0.5) : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device Header: Name, Model, Status Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.tablet_android, color: statusColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dev.deviceName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Model: ${dev.model} • ID: ${dev.deviceId}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                      ),
                    ],
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  label: Text(
                    dev.status.displayNameEn,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Hardware Fingerprint Monospace Display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.fingerprint, size: 16, color: Colors.blueGrey),
                  const SizedBox(width: 6),
                  const Text('Fingerprint: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(
                      dev.hardwareFingerprint,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.black87),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Registered Info
            Row(
              children: [
                const Icon(Icons.person_outline, size: 14, color: Colors.blueGrey),
                const SizedBox(width: 4),
                Text(
                  'Registered by: ${(dev.registeredByName != null && dev.registeredByName!.isNotEmpty) ? dev.registeredByName! : "Field Staff"}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
                ),
                const Spacer(),
                const Icon(Icons.access_time, size: 14, color: Colors.blueGrey),
                const SizedBox(width: 4),
                Text(
                  '${dev.registeredAt.year}-${dev.registeredAt.month.toString().padLeft(2, '0')}-${dev.registeredAt.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                ),
              ],
            ),
            const Divider(height: 16),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (dev.status == DeviceActivationStatus.pendingApproval) ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Approve Device'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
                    onPressed: () => _confirmApprove(context, vm, dev, adminUserId),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.dangerRose),
                    onPressed: () => _confirmRevoke(context, vm, dev, adminUserId, isReject: true),
                  ),
                ],
                if (dev.status == DeviceActivationStatus.approved) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.block, size: 16),
                    label: const Text('Revoke Access'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.dangerRose),
                    onPressed: () => _confirmRevoke(context, vm, dev, adminUserId),
                  ),
                ],
                if (dev.status == DeviceActivationStatus.revoked) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.replay, size: 16),
                    label: const Text('Re-Authorize'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryTeal),
                    onPressed: () => _confirmApprove(context, vm, dev, adminUserId),
                  ),
                ],
              ],
            ),
          ],
        ),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Device "${dev.deviceName}" approved successfully.')),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Device "${dev.deviceName}" access revoked.')),
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
