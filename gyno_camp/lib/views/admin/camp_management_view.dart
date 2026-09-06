import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/camp_model.dart';
import '../../models/user_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';

final staffUsersProvider = FutureProvider<List<UserModel>>((ref) async {
  final authRepo = ref.watch(authRepositoryProvider);
  return authRepo.getAllUsers();
});

class CampManagementView extends ConsumerStatefulWidget {
  const CampManagementView({super.key});

  @override
  ConsumerState<CampManagementView> createState() => _CampManagementViewState();
}

class _CampManagementViewState extends ConsumerState<CampManagementView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _statusFilter = 'ALL';
  DateTime _selectedCalendarMonth = DateTime(2026, 9, 1);
  DateTime? _selectedCalendarDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final campState = ref.watch(campStateProvider);
    final user = ref.watch(authStateProvider).currentUser;
    final deviceState = ref.watch(deviceSecurityProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Camp Lifecycle & Calendar'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: 'Camp Roster'),
            Tab(icon: Icon(Icons.calendar_month), text: 'Interactive Calendar'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_location_alt),
        label: const Text('New Camp'),
        backgroundColor: AppTheme.primaryTeal,
        onPressed: () => _showCreateCampDialog(context),
      ),
      body: campState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCampRosterTab(context, campState, user, deviceState),
                _buildInteractiveCalendarTab(context, campState),
              ],
            ),
    );
  }

  // ==========================================
  // TAB 1: CAMP ROSTER & LIFECYCLE
  // ==========================================
  Widget _buildCampRosterTab(
    BuildContext context,
    CampState campState,
    UserModel? user,
    DeviceSecurityState deviceState,
  ) {
    final filteredCamps = campState.camps.where((c) {
      if (_statusFilter == 'ALL') return true;
      return c.status.toDbString() == _statusFilter;
    }).toList();

    return Column(
      children: [
        // Filter Chips Bar
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              _buildFilterChip('ALL', 'All Camps (${campState.camps.length})'),
              const SizedBox(width: 8),
              _buildFilterChip(AppConstants.campStatusOpen, 'Active (Open)'),
              const SizedBox(width: 8),
              _buildFilterChip(AppConstants.campStatusScheduled, 'Scheduled'),
              const SizedBox(width: 8),
              _buildFilterChip(AppConstants.campStatusDraft, 'Draft'),
              const SizedBox(width: 8),
              _buildFilterChip(AppConstants.campStatusClosed, 'Closed'),
              const SizedBox(width: 8),
              _buildFilterChip(AppConstants.campStatusArchived, 'Archived'),
            ],
          ),
        ),
        const Divider(height: 1),

        // List of Camps
        Expanded(
          child: filteredCamps.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.campaign_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text(
                        'No camps found for status: $_statusFilter',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: filteredCamps.length,
                  itemBuilder: (context, index) {
                    final camp = filteredCamps[index];
                    return _buildCampCard(context, camp, user, deviceState);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String statusKey, String label) {
    final isSelected = _statusFilter == statusKey;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: AppTheme.primaryLight,
      onSelected: (_) {
        setState(() {
          _statusFilter = statusKey;
        });
      },
    );
  }

  Widget _buildCampCard(
    BuildContext context,
    CampModel camp,
    UserModel? user,
    DeviceSecurityState deviceState,
  ) {
    final statusColor = _getStatusColor(camp.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 14.0),
      elevation: camp.isOpen ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: camp.isOpen ? AppTheme.primaryTeal : Colors.grey.shade200,
          width: camp.isOpen ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Code, Name, Status Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    camp.campCode,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: statusColor),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    camp.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  label: Text(
                    camp.status.displayNameEn,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Location & Date Range
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 16, color: Colors.blueGrey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${camp.venue}, Ward ${camp.ward}, ${camp.municipality.isNotEmpty ? "${camp.municipality}, " : ""}${camp.district}',
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryLight),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.date_range_outlined, size: 16, color: Colors.blueGrey),
                const SizedBox(width: 4),
                Text(
                  '${_formatDate(camp.startDate)}  →  ${_formatDate(camp.endDate)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                const Icon(Icons.people_alt_outlined, size: 16, color: AppTheme.primaryTeal),
                const SizedBox(width: 4),
                Text(
                  '${camp.totalPatientsRegistered} Intakes',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Assigned Staff Roster
            Row(
              children: [
                const Text(
                  'Staff Team: ',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                ),
                camp.assignedStaffIds.isEmpty
                    ? const Text('None assigned', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey))
                    : Text(
                        '${camp.assignedStaffIds.length} Staff Member(s)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryDark),
                      ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.person_add_alt_1, size: 16),
                  label: const Text('Assign Staff', style: TextStyle(fontSize: 12)),
                  onPressed: () => _showAssignStaffDialog(context, camp),
                ),
              ],
            ),
            const Divider(height: 16),

            // Action Buttons based on Camp Status
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (camp.status == CampStatus.draft || camp.status == CampStatus.scheduled) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Open for Data Entry'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.successGreen,
                      side: const BorderSide(color: AppTheme.successGreen),
                    ),
                    onPressed: () => _confirmOpenCamp(context, camp, user, deviceState),
                  ),
                ],
                if (camp.isOpen) ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('Close Camp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.dangerRose,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _confirmCloseCamp(context, camp, user, deviceState),
                  ),
                ],
                if (camp.status == CampStatus.closed) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    label: const Text('Archive Camp'),
                    onPressed: () => _confirmArchiveCamp(context, camp, user, deviceState),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('Re-Open'),
                    onPressed: () => _confirmOpenCamp(context, camp, user, deviceState),
                  ),
                ],
                if (camp.status == CampStatus.archived) ...[
                  const Chip(
                    label: Text('Archived (Read-Only)', style: TextStyle(fontSize: 11)),
                    backgroundColor: Colors.black12,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 2: INTERACTIVE CAMP CALENDAR
  // ==========================================
  Widget _buildInteractiveCalendarTab(BuildContext context, CampState campState) {
    final camps = campState.camps;
    final year = _selectedCalendarMonth.year;
    final month = _selectedCalendarMonth.month;

    // Month details
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final firstDayWeekday = DateTime(year, month, 1).weekday; // 1 = Mon, 7 = Sun

    // Camps in this month
    final monthCamps = camps.where((c) {
      final start = c.startDate;
      final end = c.endDate;
      return (start.year == year && start.month == month) ||
          (end.year == year && end.month == month);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Month Header Navigation
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () {
                      setState(() {
                        _selectedCalendarMonth = DateTime(year, month - 1, 1);
                        _selectedCalendarDate = null;
                      });
                    },
                  ),
                  Text(
                    '${_getMonthName(month)} $year',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () {
                      setState(() {
                        _selectedCalendarMonth = DateTime(year, month + 1, 1);
                        _selectedCalendarDate = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Day of Week Labels
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _DayHeader('Mon'),
              _DayHeader('Tue'),
              _DayHeader('Wed'),
              _DayHeader('Thu'),
              _DayHeader('Fri'),
              _DayHeader('Sat'),
              _DayHeader('Sun'),
            ],
          ),
          const SizedBox(height: 8),

          // Month Grid
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 42, // 6 weeks max
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  childAspectRatio: 1.1,
                ),
                itemBuilder: (context, index) {
                  final dayOffset = index - (firstDayWeekday - 1);
                  if (dayOffset < 0 || dayOffset >= daysInMonth) {
                    return const SizedBox.shrink();
                  }

                  final dayNum = dayOffset + 1;
                  final currentDate = DateTime(year, month, dayNum);

                  // Check if any camp is active on this day
                  final dayCamps = camps.where((c) {
                    final s = DateTime(c.startDate.year, c.startDate.month, c.startDate.day);
                    final e = DateTime(c.endDate.year, c.endDate.month, c.endDate.day, 23, 59);
                    return currentDate.isAfter(s.subtract(const Duration(seconds: 1))) &&
                        currentDate.isBefore(e.add(const Duration(seconds: 1)));
                  }).toList();

                  final hasActiveCamp = dayCamps.any((c) => c.isOpen);
                  final hasScheduledCamp = dayCamps.any((c) => c.status == CampStatus.scheduled);
                  final isSelected = _selectedCalendarDate != null &&
                      _selectedCalendarDate!.year == year &&
                      _selectedCalendarDate!.month == month &&
                      _selectedCalendarDate!.day == dayNum;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedCalendarDate = currentDate;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryLight
                            : (hasActiveCamp
                                ? AppTheme.primaryTeal.withValues(alpha: 0.15)
                                : (hasScheduledCamp
                                    ? Colors.blue.withValues(alpha: 0.1)
                                    : Colors.transparent)),
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected ? Border.all(color: AppTheme.primaryTeal, width: 2) : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$dayNum',
                            style: TextStyle(
                              fontWeight: isSelected || dayCamps.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                              color: hasActiveCamp ? AppTheme.primaryTeal : Colors.black87,
                            ),
                          ),
                          if (dayCamps.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: hasActiveCamp ? AppTheme.primaryTeal : Colors.indigo,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Detail Section for Selected Date / Month Overview
          Text(
            _selectedCalendarDate != null
                ? 'Camps on ${_formatDate(_selectedCalendarDate!)}'
                : 'All Camps in ${_getMonthName(month)} $year (${monthCamps.length})',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          Builder(
            builder: (context) {
              final activeList = _selectedCalendarDate != null
                  ? camps.where((c) {
                      final s = DateTime(c.startDate.year, c.startDate.month, c.startDate.day);
                      final e = DateTime(c.endDate.year, c.endDate.month, c.endDate.day, 23, 59);
                      return _selectedCalendarDate!.isAfter(s.subtract(const Duration(seconds: 1))) &&
                          _selectedCalendarDate!.isBefore(e.add(const Duration(seconds: 1)));
                    }).toList()
                  : monthCamps;

              if (activeList.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No camp scheduled on this date.'),
                  ),
                );
              }

              return Column(
                children: activeList.map((c) {
                  final color = _getStatusColor(c.status);
                  return Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.15),
                        child: Icon(Icons.campaign, color: color),
                      ),
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${c.campCode} • ${c.venue}, ${c.district} • ${_formatDate(c.startDate)} to ${_formatDate(c.endDate)}'),
                      trailing: Chip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: color.withValues(alpha: 0.15),
                        label: Text(c.status.displayNameEn, style: TextStyle(fontSize: 10, color: color)),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // MODALS & DIALOGS
  // ==========================================

  void _confirmOpenCamp(
    BuildContext context,
    CampModel camp,
    UserModel? user,
    DeviceSecurityState deviceState,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open Camp for Data Entry?'),
        content: Text(
          'Activating "${camp.name}" (${camp.campCode}) will set it as the primary field station.\n\nNote: Any other currently active camp will automatically be set to CLOSED.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final success = await ref.read(campStateProvider.notifier).openCamp(
                    camp.id,
                    adminUserId: user?.id ?? 'admin-user',
                    deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                  );
              if (mounted && success) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Camp "${camp.name}" is now OPEN for data intake.')),
                );
              }
            },
            child: const Text('Confirm & Open'),
          ),
        ],
      ),
    );
  }

  void _confirmCloseCamp(
    BuildContext context,
    CampModel camp,
    UserModel? user,
    DeviceSecurityState deviceState,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Camp?'),
        content: Text(
          'Closing "${camp.name}" will stop field patient intake. Final reports and sync cycles can still be executed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final success = await ref.read(campStateProvider.notifier).closeCamp(
                    camp.id,
                    adminUserId: user?.id ?? 'admin-user',
                    deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                  );
              if (mounted && success) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Camp "${camp.name}" has been CLOSED.')),
                );
              }
            },
            child: const Text('Close Camp'),
          ),
        ],
      ),
    );
  }

  void _confirmArchiveCamp(
    BuildContext context,
    CampModel camp,
    UserModel? user,
    DeviceSecurityState deviceState,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Camp?'),
        content: Text('Archiving "${camp.name}" will preserve all clinical records in read-only mode.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final success = await ref.read(campStateProvider.notifier).archiveCamp(
                    camp.id,
                    adminUserId: user?.id ?? 'admin-user',
                    deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                  );
              if (mounted && success) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Camp "${camp.name}" archived.')),
                );
              }
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  void _showAssignStaffDialog(BuildContext context, CampModel camp) {
    final assigned = Set<String>.from(camp.assignedStaffIds);
    final user = ref.read(authStateProvider).currentUser;
    final deviceState = ref.read(deviceSecurityProvider);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final staffAsync = ref.watch(staffUsersProvider);

            return AlertDialog(
              title: Text('Assign Staff to ${camp.campCode}'),
              content: SizedBox(
                width: double.maxFinite,
                child: staffAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error loading staff: $e'),
                  data: (staffList) {
                    if (staffList.isEmpty) return const Text('No registered staff users found.');
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: staffList.length,
                      itemBuilder: (_, idx) {
                        final s = staffList[idx];
                        final isChecked = assigned.contains(s.id);
                        return CheckboxListTile(
                          dense: true,
                          title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${s.role.displayNameEn} • ${s.email}'),
                          value: isChecked,
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                assigned.add(s.id);
                              } else {
                                assigned.remove(s.id);
                              }
                            });
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(ctx);
                    final success = await ref.read(campStateProvider.notifier).assignStaff(
                          camp.id,
                          assigned.toList(),
                          adminUserId: user?.id ?? 'admin-user',
                          deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                        );
                    if (mounted && success) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Staff updated for camp "${camp.name}".')),
                      );
                    }
                  },
                  child: const Text('Save Assignments'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreateCampDialog(BuildContext context) {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final districtCtrl = TextEditingController(text: 'Dhading');
    final munCtrl = TextEditingController(text: 'Nilkantha');
    final wardCtrl = TextEditingController(text: '3');
    final venueCtrl = TextEditingController(text: 'Primary Health Center');
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 3));

    final user = ref.read(authStateProvider).currentUser;
    final deviceState = ref.read(deviceSecurityProvider);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: const Text('Create New Camp'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: codeCtrl,
                        decoration: const InputDecoration(labelText: 'Camp Code (e.g. DHN03, KTM02)'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Camp Name (e.g. Nilkantha Women Camp)'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: districtCtrl,
                        decoration: const InputDecoration(labelText: 'District'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: munCtrl,
                              decoration: const InputDecoration(labelText: 'Municipality'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: wardCtrl,
                              decoration: const InputDecoration(labelText: 'Ward'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: venueCtrl,
                        decoration: const InputDecoration(labelText: 'Venue / Facility'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.date_range, size: 16),
                              label: Text('Start: ${_formatDate(startDate)}', style: const TextStyle(fontSize: 11)),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: dialogCtx,
                                  initialDate: startDate,
                                  firstDate: DateTime(2025),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setDialogState(() => startDate = picked);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.date_range, size: 16),
                              label: Text('End: ${_formatDate(endDate)}', style: const TextStyle(fontSize: 11)),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: dialogCtx,
                                  initialDate: endDate,
                                  firstDate: DateTime(2025),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setDialogState(() => endDate = picked);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    if (codeCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter camp code and name')),
                      );
                      return;
                    }

                    final newCamp = CampModel(
                      id: 'camp-${DateTime.now().millisecondsSinceEpoch}',
                      campCode: codeCtrl.text.trim().toUpperCase(),
                      name: nameCtrl.text.trim(),
                      district: districtCtrl.text.trim(),
                      municipality: munCtrl.text.trim(),
                      ward: wardCtrl.text.trim(),
                      venue: venueCtrl.text.trim(),
                      startDate: startDate,
                      endDate: endDate,
                      status: CampStatus.scheduled,
                      createdAt: DateTime.now(),
                    );

                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(ctx);
                    final success = await ref.read(campStateProvider.notifier).createCamp(
                          newCamp,
                          adminUserId: user?.id ?? 'admin-user',
                          deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                        );
                    if (mounted && success) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Camp "${newCamp.name}" scheduled successfully.')),
                      );
                    }
                  },
                  child: const Text('Schedule Camp'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // HELPERS
  // ==========================================
  Color _getStatusColor(CampStatus status) {
    switch (status) {
      case CampStatus.open:
        return AppTheme.successGreen;
      case CampStatus.scheduled:
        return Colors.indigo;
      case CampStatus.draft:
        return Colors.blueGrey;
      case CampStatus.closed:
        return AppTheme.warningAmber;
      case CampStatus.archived:
        return Colors.purple;
    }
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _getMonthName(int month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return names[month - 1];
  }
}

class _DayHeader extends StatelessWidget {
  final String label;
  const _DayHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      child: Center(
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
        ),
      ),
    );
  }
}
