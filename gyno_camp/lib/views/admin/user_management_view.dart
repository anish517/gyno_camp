import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/security/security_service.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/camp_model.dart';
import '../../models/user_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../../viewmodels/sync_viewmodel.dart';

final allUsersProvider = FutureProvider.autoDispose<List<UserModel>>((ref) async {
  final authRepo = ref.watch(authRepositoryProvider);
  return authRepo.getAllUsers(includeInactive: true);
});

enum StaffStatusFilter {
  all,
  activeOnly,
  inactiveOnly,
}

class UserManagementView extends ConsumerStatefulWidget {
  const UserManagementView({super.key});

  @override
  ConsumerState<UserManagementView> createState() => _UserManagementViewState();
}

class _UserManagementViewState extends ConsumerState<UserManagementView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  UserRole? _filterRole;
  StaffStatusFilter _statusFilter = StaffStatusFilter.all;
  bool _isDialogOpen = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _safeShowDialog(Future<void> Function() dialogLauncher) async {
    if (_isDialogOpen || !mounted) return;
    _isDialogOpen = true;
    try {
      await dialogLauncher();
    } finally {
      if (mounted) {
        _isDialogOpen = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SyncState>(syncStateProvider, (previous, next) {
      if (previous?.lastSyncedAt != next.lastSyncedAt && next.lastSyncedAt != null) {
        ref.invalidate(allUsersProvider);
      }
    });

    final usersAsync = ref.watch(allUsersProvider);
    final campState = ref.watch(campStateProvider);
    final currentUser = ref.watch(authStateProvider).currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 460;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isCompact ? 'Staff Directory' : 'Staff & Personnel Management',
                  style: TextStyle(fontSize: isCompact ? 16 : 18, fontWeight: FontWeight.bold),
                ),
                if (!isCompact)
                  const Text(
                    'Role permissions, station credentials & field camp roster',
                    style: TextStyle(fontSize: 11, color: Colors.white70),
                  ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Staff Directory',
            onPressed: () => ref.invalidate(allUsersProvider),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.person_add_rounded, size: 16),
              label: const Text('Add Staff', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F766E),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _safeShowDialog(() => _showAddStaffDialog(context, campState.camps)),
            ),
          ),
        ],
      ),
      body: usersAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.dangerRose),
              const SizedBox(height: 12),
              Text('Error loading personnel: $err', style: const TextStyle(color: AppTheme.dangerRose)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => ref.invalidate(allUsersProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (users) {
          final filteredUsers = users.where((u) {
            if (_filterRole != null && u.role != _filterRole) return false;
            if (_statusFilter == StaffStatusFilter.activeOnly && !u.isActive) return false;
            if (_statusFilter == StaffStatusFilter.inactiveOnly && u.isActive) return false;
            if (_searchQuery.trim().isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              final matchesName = u.name.toLowerCase().contains(q);
              final matchesEmail = u.email.toLowerCase().contains(q);
              final matchesPhone = u.phone.toLowerCase().contains(q);
              final matchesTenant = u.tenantName.toLowerCase().contains(q);
              if (!matchesName && !matchesEmail && !matchesPhone && !matchesTenant) return false;
            }
            return true;
          }).toList();

          final activeNurses = users.where((u) => u.role == UserRole.dataTaker && u.isActive).length;
          final totalAdmins = users.where((u) => u.role == UserRole.superAdmin && u.isActive).length;
          final totalInactive = users.where((u) => !u.isActive).length;

          final hasActiveFilters = _searchQuery.isNotEmpty || _filterRole != null || _statusFilter != StaffStatusFilter.all;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Quick Stats Bar (Interactive Filters)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth >= 720;
                        final columns = isDesktop ? 4 : 2;
                        const spacing = 12.0;
                        final cardWidth = (constraints.maxWidth - (spacing * (columns - 1))) / columns;
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            SizedBox(
                              width: cardWidth,
                              child: _buildMetricCard(
                                label: 'Total Personnel',
                                value: '${users.length}',
                                icon: Icons.badge_outlined,
                                color: const Color(0xFF0F766E),
                                isSelected: _filterRole == null && _statusFilter == StaffStatusFilter.all,
                                onTap: () => setState(() {
                                  _filterRole = null;
                                  _statusFilter = StaffStatusFilter.all;
                                }),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _buildMetricCard(
                                label: 'Active Field Nurses',
                                value: '$activeNurses',
                                icon: Icons.assignment_ind_rounded,
                                color: AppTheme.primaryTeal,
                                isSelected: _filterRole == UserRole.dataTaker && _statusFilter == StaffStatusFilter.activeOnly,
                                onTap: () => setState(() {
                                  _filterRole = UserRole.dataTaker;
                                  _statusFilter = StaffStatusFilter.activeOnly;
                                }),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _buildMetricCard(
                                label: 'Super Admins',
                                value: '$totalAdmins',
                                icon: Icons.admin_panel_settings_rounded,
                                color: const Color(0xFF0F766E),
                                isSelected: _filterRole == UserRole.superAdmin,
                                onTap: () => setState(() {
                                  _filterRole = UserRole.superAdmin;
                                }),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _buildMetricCard(
                                label: 'Suspended / Inactive',
                                value: '$totalInactive',
                                icon: Icons.block_rounded,
                                color: totalInactive > 0 ? AppTheme.dangerRose : const Color(0xFF64748B),
                                isSelected: _statusFilter == StaffStatusFilter.inactiveOnly,
                                onTap: () => setState(() {
                                  _statusFilter = StaffStatusFilter.inactiveOnly;
                                }),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // Filter & Search Header
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF64748B)),
                                suffixIcon: _searchCtrl.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 18, color: Color(0xFF94A3B8)),
                                        tooltip: 'Clear search',
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                      )
                                    : null,
                                hintText: 'Search staff by name, email, phone, or organization...',
                                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              onChanged: (val) => setState(() => _searchQuery = val),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text(
                                  'Role:',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                ),
                                FilterChip(
                                  label: const Text('All Roles'),
                                  selected: _filterRole == null,
                                  onSelected: (_) => setState(() => _filterRole = null),
                                ),
                                FilterChip(
                                  label: const Text('Data Takers'),
                                  selected: _filterRole == UserRole.dataTaker,
                                  onSelected: (_) => setState(() => _filterRole = UserRole.dataTaker),
                                ),
                                FilterChip(
                                  label: const Text('Super Admins'),
                                  selected: _filterRole == UserRole.superAdmin,
                                  onSelected: (_) => setState(() => _filterRole = UserRole.superAdmin),
                                ),
                                FilterChip(
                                  label: const Text('Analysts'),
                                  selected: _filterRole == UserRole.dataAnalyst,
                                  onSelected: (_) => setState(() => _filterRole = UserRole.dataAnalyst),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text(
                                  'Status:',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                ),
                                FilterChip(
                                  label: const Text('All Status'),
                                  selected: _statusFilter == StaffStatusFilter.all,
                                  onSelected: (_) => setState(() => _statusFilter = StaffStatusFilter.all),
                                ),
                                FilterChip(
                                  label: const Text('Active Only'),
                                  selected: _statusFilter == StaffStatusFilter.activeOnly,
                                  onSelected: (_) => setState(() => _statusFilter = StaffStatusFilter.activeOnly),
                                ),
                                FilterChip(
                                  label: const Text('Suspended / Inactive'),
                                  selected: _statusFilter == StaffStatusFilter.inactiveOnly,
                                  onSelected: (_) => setState(() => _statusFilter = StaffStatusFilter.inactiveOnly),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Results Count & Clear
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          'Showing ${filteredUsers.length} of ${users.length} staff members',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                        ),
                        if (hasActiveFilters)
                          TextButton.icon(
                            icon: const Icon(Icons.filter_alt_off_rounded, size: 14),
                            label: const Text('Clear Filters', style: TextStyle(fontSize: 12)),
                            onPressed: () => setState(() {
                              _searchCtrl.clear();
                              _searchQuery = '';
                              _filterRole = null;
                              _statusFilter = StaffStatusFilter.all;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Personnel Roster
                    if (filteredUsers.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(40),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            const Icon(Icons.people_outline_rounded, size: 56, color: Color(0xFFCBD5E1)),
                            const SizedBox(height: 12),
                            const Text(
                              'No staff records found matching criteria',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Try adjusting your search query or role/status filters.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredUsers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final staff = filteredUsers[index];
                          final isCurrent = staff.id == currentUser?.id;
                          return _buildStaffCard(
                            context: context,
                            staff: staff,
                            isCurrent: isCurrent,
                            camps: campState.camps,
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isSelected = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : const Color(0xFFE2E8F0),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildStaffCard({
    required BuildContext context,
    required UserModel staff,
    required bool isCurrent,
    required List<CampModel> camps,
  }) {
    Color roleColor;
    String roleLabel;
    switch (staff.role) {
      case UserRole.superAdmin:
        roleColor = AppTheme.primaryDark;
        roleLabel = 'Super Admin';
        break;
      case UserRole.dataTaker:
        roleColor = AppTheme.primaryTeal;
        roleLabel = 'Data Taker (Field Nurse)';
        break;
      case UserRole.dataAnalyst:
        roleColor = const Color(0xFF334155);
        roleLabel = 'Data Analyst';
        break;
    }

    final isProtectedRoot = staff.id == 'usr-superadmin-01';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCurrent ? AppTheme.primaryTeal.withValues(alpha: 0.5) : const Color(0xFFE2E8F0),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, cardConstraints) {
                final isNarrow = cardConstraints.maxWidth < 500;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: roleColor.withValues(alpha: 0.12),
                      foregroundColor: roleColor,
                      radius: 22,
                      child: Text(
                        staff.name.isNotEmpty ? staff.name.substring(0, 1).toUpperCase() : 'U',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                staff.name,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              ),
                              if (isCurrent)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryTeal.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.4)),
                                  ),
                                  child: const Text('You', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal)),
                                ),
                              if (isProtectedRoot)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryDark.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppTheme.primaryDark.withValues(alpha: 0.4)),
                                  ),
                                  child: const Text('Root Admin', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryDark)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${staff.email} • Phone: ${staff.phone.isNotEmpty ? staff.phone : "Not provided"}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                          if (staff.tenantName.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.business_rounded, size: 12, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    staff.tenantName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (isNarrow) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: roleColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: roleColor.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    roleLabel,
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: roleColor),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: staff.isActive ? const Color(0xFF10B981).withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        staff.isActive ? Icons.check_circle : Icons.cancel,
                                        size: 12,
                                        color: staff.isActive ? const Color(0xFF059669) : AppTheme.dangerRose,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        staff.isActive ? 'Active' : 'Suspended',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: staff.isActive ? const Color(0xFF059669) : AppTheme.dangerRose,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!isNarrow) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: roleColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: roleColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          roleLabel,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: roleColor),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: staff.isActive ? const Color(0xFF10B981).withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              staff.isActive ? Icons.check_circle : Icons.cancel,
                              size: 12,
                              color: staff.isActive ? const Color(0xFF059669) : AppTheme.dangerRose,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              staff.isActive ? 'Active' : 'Suspended',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: staff.isActive ? const Color(0xFF059669) : AppTheme.dangerRose,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 10),

            // Camp Assignment Badges & Controls
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    const Icon(Icons.campaign_outlined, size: 16, color: Color(0xFF64748B)),
                    const Text(
                      'Assigned Camps: ',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                    ),
                    if (staff.role == UserRole.superAdmin)
                      const Text(
                        'All Camps (Universal Super Admin)',
                        style: TextStyle(fontSize: 12, color: AppTheme.primaryDark, fontWeight: FontWeight.w600),
                      )
                    else ...[
                      () {
                        final validAssigned = staff.assignedCampIds.where((cId) => camps.any((c) => c.id == cId)).toList();
                        if (validAssigned.isEmpty) {
                          return const Text(
                            'None assigned (Field intake restricted)',
                            style: TextStyle(fontSize: 12, color: AppTheme.dangerRose),
                          );
                        }
                        return Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: validAssigned.map((cId) {
                            final matchedCamp = camps.where((c) => c.id == cId).firstOrNull;
                            final code = matchedCamp?.campCode ?? cId;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Text(
                                code,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                              ),
                            );
                          }).toList(),
                        );
                      }(),
                    ],
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit_calendar_rounded, size: 14),
                      label: const Text('Assign Camps', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _safeShowDialog(() => _showAssignCampsDialog(context, staff, camps)),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      label: const Text('Edit', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _safeShowDialog(() => _showEditProfileDialog(context, staff)),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.lock_reset_rounded, size: 14, color: AppTheme.primaryDark),
                      label: const Text('Security', style: TextStyle(fontSize: 11, color: AppTheme.primaryDark)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        side: BorderSide(color: AppTheme.primaryDark.withValues(alpha: 0.35)),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _safeShowDialog(() => _showSecurityDialog(context, staff)),
                    ),
                    if (!isCurrent && !isProtectedRoot)
                      PopupMenuButton<String>(
                        tooltip: 'More actions',
                        icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF64748B)),
                        padding: EdgeInsets.zero,
                        onSelected: (action) {
                          if (action == 'toggle_status') {
                            _toggleStaffStatus(context, staff);
                          } else if (action == 'delete') {
                            _safeShowDialog(() => _showDeleteStaffDialog(context, staff));
                          }
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'toggle_status',
                            child: Row(
                              children: [
                                Icon(
                                  staff.isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                                  size: 16,
                                  color: staff.isActive ? AppTheme.dangerRose : const Color(0xFF059669),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  staff.isActive ? 'Suspend Staff' : 'Reactivate Staff',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: staff.isActive ? AppTheme.dangerRose : const Color(0xFF059669),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.dangerRose),
                                SizedBox(width: 8),
                                Text('Delete Staff...', style: TextStyle(fontSize: 12, color: AppTheme.dangerRose)),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleStaffStatus(BuildContext context, UserModel staff) async {
    final messenger = ScaffoldMessenger.of(context);
    final currentUser = ref.read(authStateProvider).currentUser;
    final deviceState = ref.read(deviceSecurityProvider);
    final updated = staff.copyWith(isActive: !staff.isActive);

    try {
      await ref.read(authRepositoryProvider).updateUser(
            user: updated,
            adminUserId: currentUser?.id ?? 'admin-root',
            deviceId: deviceState.device?.deviceId ?? 'dev-admin',
          );
      ref.invalidate(allUsersProvider);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              updated.isActive
                  ? 'Staff member "${staff.name}" has been reactivated.'
                  : 'Staff member "${staff.name}" has been suspended.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: AppTheme.dangerRose,
          ),
        );
      }
    }
  }

  Future<void> _showDeleteStaffDialog(BuildContext context, UserModel staff) async {
    final messenger = ScaffoldMessenger.of(context);
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppTheme.dangerRose),
                SizedBox(width: 10),
                Text('Delete Staff Member', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to remove staff member "${staff.name}" (${staff.email})?',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 16, color: AppTheme.dangerRose),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Notice: If this nurse or staff member recorded clinical visits or triage notes in active camps, consider Suspending their account instead of permanent deletion to preserve medical audit trails.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF991B1B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              if (staff.isActive)
                OutlinedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          Navigator.pop(ctx);
                          await _toggleStaffStatus(context, staff);
                        },
                  child: const Text('Suspend Instead'),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.dangerRose,
                  foregroundColor: Colors.white,
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        setDialogState(() => isSubmitting = true);
                        final currentUser = ref.read(authStateProvider).currentUser;
                        final deviceState = ref.read(deviceSecurityProvider);

                        try {
                          await ref.read(authRepositoryProvider).deleteUser(
                                userId: staff.id,
                                adminUserId: currentUser?.id ?? 'admin-root',
                                deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                              );
                          ref.invalidate(allUsersProvider);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Staff member "${staff.name}" removed.')),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() => isSubmitting = false);
                          }
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Failed to delete staff: $e'), backgroundColor: AppTheme.dangerRose),
                            );
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddStaffDialog(BuildContext context, List<CampModel> camps) async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    UserRole selectedRole = UserRole.dataTaker;
    final selectedCampIds = <String>{};
    bool obscurePassword = true;
    bool obscurePin = true;
    bool isSubmitting = false;

    final currentUser = ref.read(authStateProvider).currentUser;
    final savedOrg = SessionService.current?.getOrganizationName();
    final defaultTenant = (savedOrg != null && savedOrg.trim().isNotEmpty)
        ? savedOrg.trim()
        : (currentUser?.tenantName.trim().isNotEmpty == true && currentUser?.tenantName != 'Outreach Health Center'
            ? currentUser!.tenantName.trim()
            : 'Nepal Health Outreach Network');
    final tenantCtrl = TextEditingController(text: defaultTenant);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580, maxHeight: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header Banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    color: const Color(0xFF0F766E),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Register Staff Member',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Assign credentials, operational role & field outreach deployments',
                                style: TextStyle(color: Color(0xFFCCFBF1), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                          ),
                          child: const Text(
                            'NEW STAFF',
                            style: TextStyle(
                              color: Color(0xFFCCFBF1),
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                          tooltip: 'Close',
                          onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),

                  // Form Body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFormSectionHeader(Icons.badge_outlined, 'Personal & Contact Details'),
                          const SizedBox(height: 12),
                          TextField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              labelText: 'Full Name *',
                              hintText: 'e.g. Maya Shrestha (Staff Nurse)',
                              prefixIcon: const Icon(Icons.person_outline, size: 18, color: Color(0xFF64748B)),
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    labelText: 'Email Address *',
                                    hintText: 'e.g. maya@gynocamp.org',
                                    prefixIcon: const Icon(Icons.email_outlined, size: 18, color: Color(0xFF64748B)),
                                    floatingLabelBehavior: FloatingLabelBehavior.always,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: phoneCtrl,
                                  keyboardType: TextInputType.phone,
                                  decoration: InputDecoration(
                                    labelText: 'Mobile Phone *',
                                    hintText: 'e.g. 9841998877',
                                    prefixIcon: const Icon(Icons.phone_outlined, size: 18, color: Color(0xFF64748B)),
                                    floatingLabelBehavior: FloatingLabelBehavior.always,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: tenantCtrl,
                            decoration: InputDecoration(
                              labelText: 'Organization / Tenant Name',
                              hintText: 'e.g. Nepal Health Outreach Network',
                              prefixIcon: const Icon(Icons.corporate_fare_outlined, size: 18, color: Color(0xFF64748B)),
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                              isDense: true,
                            ),
                          ),

                          const SizedBox(height: 20),
                          _buildFormSectionHeader(Icons.security_outlined, 'Designated Role & Station Credentials'),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<UserRole>(
                            initialValue: selectedRole,
                            decoration: InputDecoration(
                              labelText: 'Designated User Role *',
                              prefixIcon: const Icon(Icons.admin_panel_settings_outlined, size: 18, color: Color(0xFF64748B)),
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                              isDense: true,
                            ),
                            items: UserRole.values.map((r) {
                              return DropdownMenuItem(
                                value: r,
                                child: Text(r.displayNameEn, style: const TextStyle(fontSize: 13.5)),
                              );
                            }).toList(),
                            onChanged: isSubmitting
                                ? null
                                : (val) {
                                    if (val != null) setDialogState(() => selectedRole = val);
                                  },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const ValueKey('add_staff_password_field'),
                                  controller: passwordCtrl,
                                  obscureText: obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: 'Initial Password *',
                                    hintText: 'Min 6 characters',
                                    prefixIcon: const Icon(Icons.lock_outline, size: 18, color: Color(0xFF64748B)),
                                    floatingLabelBehavior: FloatingLabelBehavior.always,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                    isDense: true,
                                    suffixIcon: IconButton(
                                      icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility, size: 18, color: const Color(0xFF64748B)),
                                      onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  key: const ValueKey('add_staff_pin_field'),
                                  controller: pinCtrl,
                                  keyboardType: TextInputType.number,
                                  maxLength: 6,
                                  obscureText: obscurePin,
                                  decoration: InputDecoration(
                                    labelText: 'Station PIN (4-6 digits) *',
                                    counterText: '',
                                    hintText: '1234',
                                    prefixIcon: const Icon(Icons.dialpad_outlined, size: 18, color: Color(0xFF64748B)),
                                    floatingLabelBehavior: FloatingLabelBehavior.always,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                    isDense: true,
                                    suffixIcon: IconButton(
                                      icon: Icon(obscurePin ? Icons.visibility_off : Icons.visibility, size: 18, color: const Color(0xFF64748B)),
                                      onPressed: () => setDialogState(() => obscurePin = !obscurePin),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),
                          _buildFormSectionHeader(Icons.hub_outlined, 'Field Camp Deployment (Optional)'),
                          const SizedBox(height: 12),
                          if (camps.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.info_outline, size: 16, color: Color(0xFF64748B)),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'No camps available. You can assign staff members later.',
                                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              constraints: const BoxConstraints(maxHeight: 180),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: camps.length,
                                separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                                itemBuilder: (_, idx) {
                                  final c = camps[idx];
                                  final checked = selectedCampIds.contains(c.id);
                                  return InkWell(
                                    onTap: isSubmitting
                                        ? null
                                        : () {
                                            setDialogState(() {
                                              if (checked) {
                                                selectedCampIds.remove(c.id);
                                              } else {
                                                selectedCampIds.add(c.id);
                                              }
                                            });
                                          },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: Checkbox(
                                              value: checked,
                                              activeColor: AppTheme.primaryTeal,
                                              onChanged: isSubmitting
                                                  ? null
                                                  : (v) {
                                                      setDialogState(() {
                                                        if (v == true) {
                                                          selectedCampIds.add(c.id);
                                                        } else {
                                                          selectedCampIds.remove(c.id);
                                                        }
                                                      });
                                                    },
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFCCFBF1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              c.campCode,
                                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(c.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                                Text('${c.venue}, ${c.district}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                              ],
                                            ),
                                          ),
                                        ],
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

                  // Actions Footer
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF475569),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.person_add_alt_1_rounded, size: 16),
                          label: const Text('Register Staff'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryTeal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  final name = nameCtrl.text.trim();
                                  final email = emailCtrl.text.trim().toLowerCase();
                                  final phone = phoneCtrl.text.trim();
                                  final password = passwordCtrl.text.trim();
                                  final pin = pinCtrl.text.trim();
                                  final tenant = tenantCtrl.text.trim().isNotEmpty
                                      ? tenantCtrl.text.trim()
                                      : (currentUser?.tenantName ?? 'Community Health Outreach Mission');

                                  if (name.isEmpty || email.isEmpty || phone.isEmpty || password.isEmpty || pin.isEmpty) {
                                    messenger.showSnackBar(
                                      const SnackBar(content: Text('Please complete all required fields.')),
                                    );
                                    return;
                                  }

                                  if (password.length < 6) {
                                    messenger.showSnackBar(
                                      const SnackBar(content: Text('Initial password must be at least 6 characters.')),
                                    );
                                    return;
                                  }

                                  if (pin.length < 4 || pin.length > 6) {
                                    messenger.showSnackBar(
                                      const SnackBar(content: Text('Station PIN must be between 4 and 6 digits.')),
                                    );
                                    return;
                                  }

                                  setDialogState(() => isSubmitting = true);

                                  final deviceState = ref.read(deviceSecurityProvider);

                                  final newStaff = UserModel(
                                    id: 'usr-${DateTime.now().millisecondsSinceEpoch}',
                                    name: name,
                                    email: email,
                                    phone: phone,
                                    role: selectedRole,
                                    isActive: true,
                                    assignedCampIds: selectedCampIds.toList(),
                                    tenantId: currentUser?.tenantId ?? 'tenant_default',
                                    tenantName: tenant,
                                    passwordHash: SecurityService.hashSha256(password),
                                    pinHash: SecurityService.hashPin(pin),
                                  );

                                  try {
                                    await ref.read(authRepositoryProvider).createUser(
                                          user: newStaff,
                                          adminUserId: currentUser?.id ?? 'admin-root',
                                          deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                                        );
                                    ref.invalidate(allUsersProvider);
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                    }
                                    if (mounted) {
                                      messenger.showSnackBar(
                                        SnackBar(content: Text('Staff member "${newStaff.name}" registered successfully.')),
                                      );
                                    }
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      setDialogState(() => isSubmitting = false);
                                    }
                                    if (mounted) {
                                      messenger.showSnackBar(
                                        SnackBar(content: Text('Failed to register user: $e'), backgroundColor: AppTheme.dangerRose),
                                      );
                                    }
                                  }
                                },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAssignCampsDialog(BuildContext context, UserModel staff, List<CampModel> camps) async {
    final validCampIds = camps.map((c) => c.id).toSet();
    final assigned = staff.assignedCampIds.where((id) => validCampIds.contains(id)).toSet();
    final messenger = ScaffoldMessenger.of(context);
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.edit_calendar_rounded, color: AppTheme.primaryTeal),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Camp Assignments: ${staff.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: camps.isEmpty
                  ? const Text('No camps configured in the system yet.')
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: camps.map((c) {
                          final checked = assigned.contains(c.id);
                          return Material(
                            type: MaterialType.transparency,
                            child: CheckboxListTile(
                              dense: true,
                              value: checked,
                              title: Text('${c.campCode} - ${c.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Text('Status: ${c.status.displayNameEn} • ${c.venue}', style: const TextStyle(fontSize: 11)),
                              onChanged: isSubmitting
                                  ? null
                                  : (v) {
                                      setDialogState(() {
                                        if (v == true) {
                                          assigned.add(c.id);
                                        } else {
                                          assigned.remove(c.id);
                                        }
                                      });
                                    },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        setDialogState(() => isSubmitting = true);
                        final updated = staff.copyWith(assignedCampIds: assigned.toList());
                        final currentUser = ref.read(authStateProvider).currentUser;
                        final deviceState = ref.read(deviceSecurityProvider);

                        try {
                          await ref.read(authRepositoryProvider).updateUser(
                                user: updated,
                                adminUserId: currentUser?.id ?? 'admin-root',
                                deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                              );
                          ref.invalidate(allUsersProvider);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Camp assignments updated for ${staff.name}.')),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() => isSubmitting = false);
                          }
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Failed to update assignments: $e'), backgroundColor: AppTheme.dangerRose),
                            );
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Assignments', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEditProfileDialog(BuildContext context, UserModel staff) async {
    final nameCtrl = TextEditingController(text: staff.name);
    final savedOrg = SessionService.current?.getOrganizationName();
    final initialTenant = (staff.isSuperAdmin && savedOrg != null && savedOrg.trim().isNotEmpty)
        ? savedOrg
        : staff.tenantName;
    final tenantCtrl = TextEditingController(text: initialTenant);
    final phoneCtrl = TextEditingController(text: staff.phone);
    final messenger = ScaffoldMessenger.of(context);
    bool isActive = staff.isActive;
    UserRole selectedRole = staff.role;
    bool isSubmitting = false;

    final currentUser = ref.read(authStateProvider).currentUser;
    final isSelf = staff.id == currentUser?.id;
    final isProtectedRoot = staff.id == 'usr-superadmin-01' ||
        staff.email.trim().toLowerCase() == 'admin@gynocamp.org' ||
        staff.isSuperAdmin;
    if (isProtectedRoot) {
      selectedRole = UserRole.superAdmin;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.edit_outlined, color: AppTheme.primaryTeal),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Edit Profile: ${staff.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.mail_outline, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${staff.email} • ID: ${staff.id}',
                              style: const TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Full Name / Staff Title *',
                        hintText: 'e.g. Dr. Jane Doe or Sita Sharma',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tenantCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Organization / Tenant Name',
                        hintText: 'e.g. Nepal Health Outreach Network',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        hintText: 'e.g. 9841234567',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Role Designation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<UserRole>(
                      initialValue: selectedRole,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        isDense: true,
                        helperText: isProtectedRoot ? 'Super Administrator role is protected and locked.' : null,
                      ),
                      items: UserRole.values.map((r) {
                        return DropdownMenuItem(value: r, child: Text(r.displayNameEn));
                      }).toList(),
                      onChanged: (isSubmitting || isProtectedRoot)
                          ? null
                          : (val) {
                              if (val != null) setDialogState(() => selectedRole = val);
                            },
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      title: const Text('Account Active Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        isSelf
                            ? 'Your own administrator account cannot be deactivated'
                            : (isActive ? 'User can log in and perform clinical actions' : 'User account suspended / access blocked'),
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelf ? AppTheme.primaryTeal : Colors.grey.shade600,
                        ),
                      ),
                      value: isActive,
                      activeThumbColor: const Color(0xFF059669),
                      onChanged: (isSubmitting || isSelf)
                          ? null
                          : (val) => setDialogState(() => isActive = val),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final newName = nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : staff.name;
                        final newTenant = tenantCtrl.text.trim().isNotEmpty ? tenantCtrl.text.trim() : staff.tenantName;

                        setDialogState(() => isSubmitting = true);

                        final deviceState = ref.read(deviceSecurityProvider);
                        final updated = staff.copyWith(
                          name: newName,
                          tenantName: newTenant,
                          phone: phoneCtrl.text.trim(),
                          role: selectedRole,
                          isActive: isActive,
                        );

                        try {
                          await ref.read(authRepositoryProvider).updateUser(
                                user: updated,
                                adminUserId: currentUser?.id ?? 'admin-root',
                                deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                              );
                          if (currentUser?.id == staff.id) {
                            ref.read(authStateProvider.notifier).updateCurrentUser(updated);
                          }
                          ref.invalidate(allUsersProvider);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Staff profile updated for $newName.')),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() => isSubmitting = false);
                          }
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Failed to update staff profile: $e'), backgroundColor: AppTheme.dangerRose),
                            );
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showSecurityDialog(BuildContext context, UserModel staff) async {
    final passwordCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    bool obscurePassword = true;
    bool obscurePin = true;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.lock_reset_rounded, color: AppTheme.primaryDark),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Security & Credentials: ${staff.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDFA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFCCFBF1)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.security_rounded, size: 20, color: Color(0xFF0F766E)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'User: ${staff.email}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F766E)),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Updating credentials immediately takes effect across all field workstations and authentications. Leave fields blank to keep existing credentials unchanged.',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF0F766E)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('New Master Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        hintText: 'Min 6 characters',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility, size: 18),
                          onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('New Station PIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: pinCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      obscureText: obscurePin,
                      decoration: InputDecoration(
                        labelText: 'Station PIN (4-6 digits)',
                        counterText: '',
                        hintText: 'e.g. 1234',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: Icon(obscurePin ? Icons.visibility_off : Icons.visibility, size: 18),
                          onPressed: () => setDialogState(() => obscurePin = !obscurePin),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.shield_outlined, size: 16),
                label: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Update Credentials', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, foregroundColor: Colors.white),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final newPassword = passwordCtrl.text.trim();
                        final newPin = pinCtrl.text.trim();

                        if (newPassword.isEmpty && newPin.isEmpty) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('No credential changes entered.')),
                          );
                          return;
                        }

                        if (newPassword.isNotEmpty && newPassword.length < 6) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Password must be at least 6 characters.')),
                          );
                          return;
                        }

                        if (newPin.isNotEmpty && (newPin.length < 4 || newPin.length > 6)) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Station PIN must be 4 to 6 digits.')),
                          );
                          return;
                        }

                        setDialogState(() => isSubmitting = true);

                        final currentUser = ref.read(authStateProvider).currentUser;
                        final deviceState = ref.read(deviceSecurityProvider);
                        final updated = staff.copyWith(
                          passwordHash: newPassword.isNotEmpty ? SecurityService.hashSha256(newPassword) : staff.passwordHash,
                          pinHash: newPin.isNotEmpty ? SecurityService.hashPin(newPin) : staff.pinHash,
                        );

                        try {
                          await ref.read(authRepositoryProvider).updateUser(
                                user: updated,
                                adminUserId: currentUser?.id ?? 'admin-root',
                                deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                              );
                          if (currentUser?.id == staff.id) {
                            ref.read(authStateProvider.notifier).updateCurrentUser(updated);
                          }
                          ref.invalidate(allUsersProvider);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Security credentials updated for ${staff.name}.')),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() => isSubmitting = false);
                          }
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Failed to update credentials: $e'), backgroundColor: AppTheme.dangerRose),
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

  Widget _buildFormSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF0F766E)),
        const SizedBox(width: 6),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Color(0xFF0F766E),
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Divider(color: Color(0xFFE2E8F0), thickness: 1),
        ),
      ],
    );
  }
}

