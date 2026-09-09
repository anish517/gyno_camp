import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nepali_utils/nepali_utils.dart';
import '../../core/constants/app_constants.dart';
import '../../core/security/security_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/nepali_date_helper.dart';
import '../../models/camp_model.dart';
import '../../models/user_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../patient/patient_registration_view.dart';
import '../scanner/form_scan_view.dart';
import '../patient/patient_list_view.dart';

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
  bool _isNepaliCalendarMode = true;
  late NepaliDateTime _selectedBsMonth;
  NepaliDateTime? _selectedBsDate;
  DateTime _selectedCalendarMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _selectedCalendarDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final nowBs = NepaliDateTime.now();
    _selectedBsMonth = NepaliDateTime(nowBs.year, nowBs.month, 1);
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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: const Color(0xFF0F766E),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hub_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Camp Lifecycle & Calendar',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${campState.camps.length} Camps',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Field outreach deployments, mission scheduling & personnel dispatch',
              style: TextStyle(color: Color(0xFFCCFBF1), fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_location_alt, size: 16),
              label: const Text('New Camp'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF042F2E),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFF14B8A6)),
                ),
              ),
              onPressed: () => _showCreateCampDialog(context),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            width: double.infinity,
            color: const Color(0xFF042F2E),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: AppTheme.primaryTeal,
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(
                  icon: Icon(Icons.list_alt, size: 18),
                  text: 'Camp Roster',
                ),
                Tab(
                  icon: Icon(Icons.calendar_month, size: 18),
                  text: 'Interactive Calendar',
                ),
              ],
            ),
          ),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 14.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: camp.isOpen ? AppTheme.primaryTeal : Colors.grey.shade200, width: camp.isOpen ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: camp.isOpen ? AppTheme.primaryTeal.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: statusColor, width: 5)),
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Code, Name, Status Badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      camp.campCode,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: statusColor),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      camp.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimaryLight),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          camp.status.displayNameEn,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Location Row
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 16, color: Colors.blueGrey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${camp.venue}, Ward ${camp.ward}, ${camp.municipality.isNotEmpty ? "${camp.municipality}, " : ""}${camp.district}',
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryLight),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Dual Date Range (Nepali BS & English AD)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 15, color: AppTheme.primaryDark),
                    const SizedBox(width: 6),
                    Text(
                      '🇳🇵 ${NepaliDateHelper.formatBsRange(camp.startDate, camp.endDate, pureNepali: true)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryDark),
                    ),
                    const Text('  •  ', style: TextStyle(color: Colors.grey)),
                    Text(
                      '🌐 ${_formatDate(camp.startDate)}  →  ${_formatDate(camp.endDate)}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
                    ),
                    const Spacer(),
                    const Icon(Icons.people_alt_outlined, size: 15, color: AppTheme.primaryTeal),
                    const SizedBox(width: 4),
                    Text(
                      '${camp.totalPatientsRegistered} Intakes',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

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
                children: [
                  // Fast Station Entry if active
                  if (camp.isOpen)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.medical_services_outlined, size: 16),
                      label: const Text('Clinic Workstation'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryTeal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: () => _openCampWorkstation(camp),
                    ),
                  const Spacer(),

                  // Edit Camp Details
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit Camp Details',
                    onPressed: () => _showEditCampDialog(context, camp),
                  ),
                  // Safe Delete Camp (only if not active/open)
                  if (!camp.isOpen)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.dangerRose),
                      tooltip: 'Delete Camp',
                      onPressed: () => _confirmDeleteCamp(context, camp, user, deviceState),
                    ),
                  const SizedBox(width: 4),

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
      ),
    );
  }

  // ==========================================
  // TAB 2: INTERACTIVE CAMP CALENDAR
  // ==========================================
  Widget _buildInteractiveCalendarTab(BuildContext context, CampState campState) {
    final camps = campState.camps;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1020;

        final calendarColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Controls Bar: Dual Mode Switcher & Month Navigation
            _buildCalendarControlsBar(),
            const SizedBox(height: 10),

            // "Why are dates marked?" Mission Schedule Explanation Banner
            _buildMissionExplanationBanner(camps),
            const SizedBox(height: 10),

            // The Active Calendar View (Nepali or Gregorian)
            _isNepaliCalendarMode
                ? _buildNepaliCalendarGrid(context, camps)
                : _buildGregorianCalendarGrid(context, camps),
          ],
        );

        if (isDesktop) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 440,
                  child: calendarColumn,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSelectedDateMissionDetails(context, camps),
                ),
              ],
            ),
          );
        } else {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: calendarColumn,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSelectedDateMissionDetails(context, camps),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildCalendarControlsBar() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        child: Column(
          children: [
            // Row 1: Dual Mode Switcher (segmented bar)
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  Expanded(
                    child: _buildCalendarModePill(
                      title: '🇳🇵 Bikram Sambat (BS)',
                      isSelected: _isNepaliCalendarMode,
                      onTap: () => setState(() => _isNepaliCalendarMode = true),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _buildCalendarModePill(
                      title: '🌐 Gregorian (AD)',
                      isSelected: !_isNepaliCalendarMode,
                      onTap: () => setState(() => _isNepaliCalendarMode = false),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Row 2: Month Navigation Bar (< भाद्र २०८३ >)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 22, color: AppTheme.primaryTeal),
                  tooltip: 'Previous Month',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _navigateMonth(-1),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isNepaliCalendarMode
                            ? '${NepaliDateHelper.nepaliMonthPureNp[_selectedBsMonth.month - 1]} ${_selectedBsMonth.year} (${NepaliDateHelper.nepaliMonthPureEn[_selectedBsMonth.month - 1]} ${_selectedBsMonth.year} BS)'
                            : '${_getMonthName(_selectedCalendarMonth.month)} ${_selectedCalendarMonth.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isNepaliCalendarMode
                            ? 'September 2026 (Aug 18 – Sep 17, 2026 AD)'
                            : 'वि.सं. भाद्र – असोज २०८३ (Bhadra – Ashwin 2083 BS)',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22, color: AppTheme.primaryTeal),
                  tooltip: 'Next Month',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _navigateMonth(1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _navigateMonth(int delta) {
    setState(() {
      if (_isNepaliCalendarMode) {
        int newMonth = _selectedBsMonth.month + delta;
        int newYear = _selectedBsMonth.year;
        if (newMonth > 12) {
          newMonth = 1;
          newYear++;
        } else if (newMonth < 1) {
          newMonth = 12;
          newYear--;
        }
        _selectedBsMonth = NepaliDateTime(newYear, newMonth, 1);
        _selectedBsDate = null;
      } else {
        _selectedCalendarMonth = DateTime(_selectedCalendarMonth.year, _selectedCalendarMonth.month + delta, 1);
        _selectedCalendarDate = null;
      }
    });
  }

  Widget _buildCalendarModePill({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppTheme.primaryTeal : Colors.blueGrey,
          ),
        ),
      ),
    );
  }

  Widget _buildMissionExplanationBanner(List<CampModel> camps) {
    // Determine active camps in this view
    final activeCamps = camps.where((c) => c.isOpen).toList();
    final scheduledCamps = camps.where((c) => c.status == CampStatus.scheduled).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 18, color: Color(0xFF16A34A)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Why are calendar dates marked?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF166534)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: Text(
                  '${camps.length} Missions',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            activeCamps.isNotEmpty
                ? 'Highlighted green date boxes indicate active field outreach camps in progress (${activeCamps.map((c) => "${c.name} [${c.campCode}]").join(", ")}). Blue indicates upcoming scheduled deployments. Tap any date to inspect full facility and roster details.'
                : (scheduledCamps.isNotEmpty
                    ? 'Highlighted date boxes indicate upcoming scheduled outreach missions. Tap any highlighted date to inspect camp details.'
                    : 'No camps active in this calendar window. Highlighted blocks show operational date windows.'),
            style: const TextStyle(fontSize: 12, color: Color(0xFF15803D)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _buildLegendPill(AppTheme.primaryTeal, 'Active / Open Camp'),
              _buildLegendPill(Colors.indigo, 'Scheduled Mission'),
              _buildLegendPill(Colors.grey.shade400, 'Available Date'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendPill(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.blueGrey),
        ),
      ],
    );
  }

  // ==========================================
  // BIKRAM SAMBAT (NEPALI BS) GRID
  // ==========================================
  Widget _buildNepaliCalendarGrid(BuildContext context, List<CampModel> camps) {
    final year = _selectedBsMonth.year;
    final month = _selectedBsMonth.month;
    final daysInMonth = NepaliDateHelper.getDaysInBsMonth(year, month);
    final firstDayOffset = NepaliDateHelper.getFirstDayWeekdayBs(year, month); // 0=Sun ... 6=Sat

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // Days of Week Header (Sun to Sat)
            Row(
              children: [
                _buildDayHeader('आई\nSun'),
                _buildDayHeader('सोम\nMon'),
                _buildDayHeader('मंगल\nTue'),
                _buildDayHeader('बुध\nWed'),
                _buildDayHeader('बिही\nThu'),
                _buildDayHeader('शुक्र\nFri'),
                _buildDayHeader('शनि\nSat', isHoliday: true),
              ],
            ),
            const Divider(height: 16),

            // 42-cell Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 42,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.35,
              ),
              itemBuilder: (context, index) {
                final dayOffset = index - firstDayOffset;
                if (dayOffset < 0 || dayOffset >= daysInMonth) {
                  return const SizedBox.shrink();
                }

                final dayNum = dayOffset + 1;
                final currentBs = NepaliDateTime(year, month, dayNum);
                final currentAd = currentBs.toDateTime();

                // Check camps on this date
                final dayCamps = camps.where((c) {
                  final s = DateTime(c.startDate.year, c.startDate.month, c.startDate.day);
                  final e = DateTime(c.endDate.year, c.endDate.month, c.endDate.day, 23, 59, 59);
                  return !currentAd.isBefore(s) && !currentAd.isAfter(e);
                }).toList();

                final hasActiveCamp = dayCamps.any((c) => c.isOpen);
                final hasScheduledCamp = dayCamps.any((c) => c.status == CampStatus.scheduled);
                final isSelected = _selectedBsDate != null &&
                    _selectedBsDate!.year == year &&
                    _selectedBsDate!.month == month &&
                    _selectedBsDate!.day == dayNum;

                final isSaturday = currentBs.weekday == 7;

                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedBsDate = currentBs;
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryLight
                          : (hasActiveCamp
                              ? AppTheme.primaryTeal.withValues(alpha: 0.15)
                              : (hasScheduledCamp
                                  ? Colors.blue.withValues(alpha: 0.1)
                                  : Colors.transparent)),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryTeal
                            : (hasActiveCamp
                                ? AppTheme.primaryTeal
                                : (hasScheduledCamp ? Colors.indigo.shade200 : Colors.transparent)),
                        width: isSelected ? 2 : (hasActiveCamp ? 1.5 : 1),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$dayNum',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected || dayCamps.isNotEmpty ? FontWeight.bold : FontWeight.w500,
                            color: isSaturday
                                ? const Color(0xFFDC2626)
                                : (hasActiveCamp ? AppTheme.primaryTeal : Colors.black87),
                          ),
                        ),
                        Text(
                          '${currentAd.day}',
                          style: TextStyle(
                            fontSize: 8.5,
                            color: isSelected ? AppTheme.primaryDark : Colors.grey.shade500,
                          ),
                        ),
                        if (dayCamps.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 1),
                            width: 5,
                            height: 5,
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
          ],
        ),
      ),
    );
  }

  // ==========================================
  // GREGORIAN (AD) GRID
  // ==========================================
  Widget _buildGregorianCalendarGrid(BuildContext context, List<CampModel> camps) {
    final year = _selectedCalendarMonth.year;
    final month = _selectedCalendarMonth.month;
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final firstDayWeekday = DateTime(year, month, 1).weekday; // 1 = Mon, 7 = Sun
    final firstDayOffset = firstDayWeekday - 1;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // Days of Week Header (Mon to Sun)
            Row(
              children: [
                _buildDayHeader('Mon'),
                _buildDayHeader('Tue'),
                _buildDayHeader('Wed'),
                _buildDayHeader('Thu'),
                _buildDayHeader('Fri'),
                _buildDayHeader('Sat'),
                _buildDayHeader('Sun'),
              ],
            ),
            const Divider(height: 16),

            // 42-cell Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 42,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.35,
              ),
              itemBuilder: (context, index) {
                final dayOffset = index - firstDayOffset;
                if (dayOffset < 0 || dayOffset >= daysInMonth) {
                  return const SizedBox.shrink();
                }

                final dayNum = dayOffset + 1;
                final currentAd = DateTime(year, month, dayNum);
                final currentBs = NepaliDateHelper.toNepali(currentAd);

                final dayCamps = camps.where((c) {
                  final s = DateTime(c.startDate.year, c.startDate.month, c.startDate.day);
                  final e = DateTime(c.endDate.year, c.endDate.month, c.endDate.day, 23, 59, 59);
                  return !currentAd.isBefore(s) && !currentAd.isAfter(e);
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
                      _selectedCalendarDate = currentAd;
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
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryTeal
                            : (hasActiveCamp
                                ? AppTheme.primaryTeal
                                : (hasScheduledCamp ? Colors.indigo.shade200 : Colors.transparent)),
                        width: isSelected ? 2 : (hasActiveCamp ? 1.5 : 1),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$dayNum',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected || dayCamps.isNotEmpty ? FontWeight.bold : FontWeight.w500,
                            color: hasActiveCamp ? AppTheme.primaryTeal : Colors.black87,
                          ),
                        ),
                        Text(
                          '${currentBs.day}',
                          style: TextStyle(
                            fontSize: 8.5,
                            color: isSelected ? AppTheme.primaryDark : Colors.grey.shade500,
                          ),
                        ),
                        if (dayCamps.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 1),
                            width: 5,
                            height: 5,
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
          ],
        ),
      ),
    );
  }

  Widget _buildDayHeader(String label, {bool isHoliday = false}) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isHoliday ? const Color(0xFFDC2626) : Colors.blueGrey,
          ),
        ),
      ),
    );
  }

  // ==========================================
  // SELECTED DATE MISSION DETAILS CARD
  // ==========================================
  Widget _buildSelectedDateMissionDetails(BuildContext context, List<CampModel> camps) {
    // Find matching camps
    List<CampModel> matchingCamps = [];
    String dateLabel = '';

    if (_isNepaliCalendarMode) {
      if (_selectedBsDate != null) {
        final ad = _selectedBsDate!.toDateTime();
        matchingCamps = camps.where((c) {
          final s = DateTime(c.startDate.year, c.startDate.month, c.startDate.day);
          final e = DateTime(c.endDate.year, c.endDate.month, c.endDate.day, 23, 59, 59);
          return !ad.isBefore(s) && !ad.isAfter(e);
        }).toList();
        dateLabel = '${NepaliDateHelper.nepaliMonthPureNp[_selectedBsDate!.month - 1]} ${_selectedBsDate!.day}, ${_selectedBsDate!.year} BS (${_formatDate(ad)})';
      } else {
        // Show camps in this BS month
        matchingCamps = camps.where((c) {
          final s = NepaliDateHelper.toNepali(c.startDate);
          final e = NepaliDateHelper.toNepali(c.endDate);
          return (s.year == _selectedBsMonth.year && s.month == _selectedBsMonth.month) ||
              (e.year == _selectedBsMonth.year && e.month == _selectedBsMonth.month);
        }).toList();
        dateLabel = 'All Camps in ${NepaliDateHelper.nepaliMonthPureNp[_selectedBsMonth.month - 1]} ${_selectedBsMonth.year} BS';
      }
    } else {
      if (_selectedCalendarDate != null) {
        matchingCamps = camps.where((c) {
          final s = DateTime(c.startDate.year, c.startDate.month, c.startDate.day);
          final e = DateTime(c.endDate.year, c.endDate.month, c.endDate.day, 23, 59, 59);
          return !_selectedCalendarDate!.isBefore(s) && !_selectedCalendarDate!.isAfter(e);
        }).toList();
        dateLabel = 'Camps on ${_formatDate(_selectedCalendarDate!)}';
      } else {
        matchingCamps = camps.where((c) {
          final s = c.startDate;
          final e = c.endDate;
          return (s.year == _selectedCalendarMonth.year && s.month == _selectedCalendarMonth.month) ||
              (e.year == _selectedCalendarMonth.year && e.month == _selectedCalendarMonth.month);
        }).toList();
        dateLabel = 'All Camps in ${_getMonthName(_selectedCalendarMonth.month)} ${_selectedCalendarMonth.year} (${matchingCamps.length})';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.event_note, size: 18, color: AppTheme.primaryDark),
            const SizedBox(width: 8),
            Text(
              dateLabel,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimaryLight),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (matchingCamps.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppTheme.borderLight),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.event_available, color: Colors.blueGrey),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'No camp scheduled on this date. This date is open for new field deployments.',
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Schedule Camp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _showCreateCampDialog(context),
                  ),
                ],
              ),
            ),
          )
        else
          Column(
            children: matchingCamps.map((c) {
              final color = _getStatusColor(c.status);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.isOpen ? AppTheme.primaryTeal : AppTheme.borderLight),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              c.campCode,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              c.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: color.withValues(alpha: 0.15),
                            label: Text(c.status.displayNameEn, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${c.venue}, Ward ${c.ward}, ${c.municipality.isNotEmpty ? "${c.municipality}, " : ""}${c.district}',
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryLight),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '🇳🇵 ${NepaliDateHelper.formatBsRange(c.startDate, c.endDate, pureNepali: true)}   •   🌐 ${_formatDate(c.startDate)} to ${_formatDate(c.endDate)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.primaryDark),
                      ),
                      const Divider(height: 20),
                      Row(
                        children: [
                          const Icon(Icons.people_alt_outlined, size: 16, color: AppTheme.primaryTeal),
                          const SizedBox(width: 6),
                          Text(
                            '${c.assignedStaffIds.length} Staff Assigned  •  ${c.totalPatientsRegistered} Intakes',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryLight),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (c.isOpen)
                            ElevatedButton.icon(
                              icon: const Icon(Icons.medical_services_outlined, size: 16),
                              label: const Text('Enter Workstation'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryTeal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              onPressed: () => _openCampWorkstation(c),
                            ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.person_add_alt_1, size: 16),
                            label: const Text('Staff'),
                            onPressed: () => _showAssignStaffDialog(context, c),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  void _openCampWorkstation(CampModel camp) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryDark,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      camp.campCode,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(camp.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('${camp.venue}, Ward ${camp.ward}, ${camp.district}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Launch Clinical Workstation:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppTheme.primaryLight,
                  child: Icon(Icons.person_add_alt_1, color: AppTheme.primaryTeal),
                ),
                title: const Text('Station 1: Patient Demographic Registration'),
                subtitle: const Text('Register incoming patients for this camp mission'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PatientRegistrationView()));
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFEF3C7),
                  child: Icon(Icons.document_scanner, color: Color(0xFFD97706)),
                ),
                title: const Text('Station 2: AI Yellow Form OCR Scanner'),
                subtitle: const Text('Capture Page 1 & Page 2 clinical charts with OCR verification'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const FormScanView()));
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE0E7FF),
                  child: Icon(Icons.people_alt, color: Color(0xFF4F46E5)),
                ),
                title: const Text('Station 3: Patient Roll & Medical Records'),
                subtitle: const Text('Browse all screened patients and charts'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PatientListView()));
                },
              ),
            ],
          ),
        );
      },
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
    ref.invalidate(staffUsersProvider);
    final assigned = Set<String>.from(camp.assignedStaffIds);
    final user = ref.read(authStateProvider).currentUser;
    final deviceState = ref.read(deviceSecurityProvider);

    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer(
          builder: (dialogCtx, ref, _) {
            final staffAsync = ref.watch(staffUsersProvider);

            return StatefulBuilder(
              builder: (innerCtx, setDialogState) {
                return AlertDialog(
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Assign Staff to ${camp.campCode}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.person_add_alt_1, size: 18),
                        label: const Text('Add Staff', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () => _showAddNewStaffDialog(context, assigned, setDialogState),
                      ),
                    ],
                  ),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: staffAsync.when(
                      loading: () => const SizedBox(
                        height: 140,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text('Error loading staff: $e', style: const TextStyle(color: AppTheme.dangerRose)),
                      ),
                      data: (staffList) {
                        if (staffList.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.people_outline, size: 40, color: Colors.grey),
                                const SizedBox(height: 8),
                                const Text('No registered staff users found.'),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text('Register First Staff Member'),
                                  onPressed: () => _showAddNewStaffDialog(context, assigned, setDialogState),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: staffList.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
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
      },
    );
  }

  void _showAddNewStaffDialog(
    BuildContext context,
    Set<String> assigned,
    void Function(void Function()) setDialogState,
  ) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passwordCtrl = TextEditingController(text: 'nurse123');
    final pinCtrl = TextEditingController(text: '1234');
    UserRole selectedRole = UserRole.dataTaker;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (innerCtx, setInnerState) {
          return AlertDialog(
            title: const Text('Register New Staff Member'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Official Email',
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role & Responsibility',
                      prefixIcon: Icon(Icons.badge),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: UserRole.dataTaker,
                        child: Text(UserRole.dataTaker.displayNameEn),
                      ),
                      DropdownMenuItem(
                        value: UserRole.superAdmin,
                        child: Text(UserRole.superAdmin.displayNameEn),
                      ),
                      DropdownMenuItem(
                        value: UserRole.dataAnalyst,
                        child: Text(UserRole.dataAnalyst.displayNameEn),
                      ),
                    ],
                    onChanged: (role) {
                      if (role != null) {
                        setInnerState(() => selectedRole = role);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: passwordCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Initial Password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: pinCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: 'Station PIN (4-6 Digits)',
                            counterText: '',
                            prefixIcon: Icon(Icons.pin),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final email = emailCtrl.text.trim().toLowerCase();
                  final password = passwordCtrl.text.trim().isNotEmpty ? passwordCtrl.text.trim() : 'nurse123';
                  final pin = pinCtrl.text.trim().isNotEmpty ? pinCtrl.text.trim() : '1234';

                  if (name.isEmpty || email.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter staff name and email.')),
                    );
                    return;
                  }

                  final user = ref.read(authStateProvider).currentUser;
                  final deviceState = ref.read(deviceSecurityProvider);
                  final messenger = ScaffoldMessenger.of(context);
                  final newUser = UserModel(
                    id: 'usr-${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    email: email,
                    phone: phoneCtrl.text.trim(),
                    role: selectedRole,
                    isActive: true,
                    tenantId: user?.tenantId ?? 'tenant_default',
                    tenantName: user?.tenantName ?? 'Community Health Outreach Mission',
                    passwordHash: SecurityService.hashSha256(password),
                    pinHash: SecurityService.hashPin(pin),
                  );

                  Navigator.pop(ctx);
                  await ref.read(authRepositoryProvider).createUser(
                        user: newUser,
                        adminUserId: user?.id ?? 'admin-user',
                        deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                      );

                  ref.invalidate(staffUsersProvider);
                  setDialogState(() {
                    assigned.add(newUser.id);
                  });

                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Registered "$name" (PIN: $pin) and assigned to camp.')),
                    );
                  }
                },
                child: const Text('Add Staff'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCreateCampDialog(BuildContext context) {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final districtCtrl = TextEditingController();
    final munCtrl = TextEditingController();
    final wardCtrl = TextEditingController();
    final venueCtrl = TextEditingController();
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
              title: const Text('Schedule New Health Camp'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: codeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Camp Code *',
                          hintText: 'e.g. KTM02, DHN03, PKR01',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Camp Name *',
                          hintText: 'e.g. Nilkantha Women Health Outreach Camp',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: districtCtrl,
                        decoration: const InputDecoration(
                          labelText: 'District *',
                          hintText: 'e.g. Kathmandu / Dhading / Kaski',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: munCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Municipality / Rural Mun.',
                                hintText: 'e.g. Budhanilkantha',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: wardCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Ward No.',
                                hintText: 'e.g. 03',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: venueCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Venue / Health Post Facility *',
                          hintText: 'e.g. Primary Health Care Center',
                        ),
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
                                  lastDate: DateTime(2035),
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
                                  lastDate: DateTime(2035),
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
                        const SnackBar(content: Text('Please enter camp code and name.')),
                      );
                      return;
                    }

                    final newCamp = CampModel(
                      id: 'camp-${DateTime.now().millisecondsSinceEpoch}',
                      campCode: codeCtrl.text.trim().toUpperCase(),
                      name: nameCtrl.text.trim(),
                      district: districtCtrl.text.trim().isNotEmpty ? districtCtrl.text.trim() : 'Bagmati',
                      municipality: munCtrl.text.trim(),
                      ward: wardCtrl.text.trim().isNotEmpty ? wardCtrl.text.trim() : '01',
                      venue: venueCtrl.text.trim().isNotEmpty ? venueCtrl.text.trim() : 'Health Post',
                      startDate: startDate,
                      endDate: endDate,
                      status: CampStatus.scheduled,
                      tenantId: user?.tenantId ?? 'tenant_default',
                      organizationName: user?.tenantName ?? 'Community Health Outreach Mission',
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
                        SnackBar(
                          content: Text('Camp "${newCamp.name}" scheduled. Assign staff to allow field intake.'),
                          action: SnackBarAction(
                            label: 'Assign Staff',
                            textColor: Colors.tealAccent,
                            onPressed: () => _showAssignStaffDialog(context, newCamp),
                          ),
                          duration: const Duration(seconds: 8),
                        ),
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

  void _showEditCampDialog(BuildContext context, CampModel camp) {
    final nameCtrl = TextEditingController(text: camp.name);
    final districtCtrl = TextEditingController(text: camp.district);
    final munCtrl = TextEditingController(text: camp.municipality);
    final wardCtrl = TextEditingController(text: camp.ward);
    final venueCtrl = TextEditingController(text: camp.venue);
    DateTime startDate = camp.startDate;
    DateTime endDate = camp.endDate;

    final user = ref.read(authStateProvider).currentUser;
    final deviceState = ref.read(deviceSecurityProvider);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: Text('Edit Camp (${camp.campCode})'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Camp Name *'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: districtCtrl,
                        decoration: const InputDecoration(labelText: 'District *'),
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
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Ward'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: venueCtrl,
                        decoration: const InputDecoration(labelText: 'Venue / Facility *'),
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
                                  lastDate: DateTime(2035),
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
                                  lastDate: DateTime(2035),
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
                    if (nameCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Camp name cannot be empty.')),
                      );
                      return;
                    }

                    final updated = camp.copyWith(
                      name: nameCtrl.text.trim(),
                      district: districtCtrl.text.trim(),
                      municipality: munCtrl.text.trim(),
                      ward: wardCtrl.text.trim(),
                      venue: venueCtrl.text.trim(),
                      startDate: startDate,
                      endDate: endDate,
                    );

                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(ctx);
                    final success = await ref.read(campStateProvider.notifier).updateCamp(
                          updated,
                          adminUserId: user?.id ?? 'admin-user',
                          deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                        );
                    if (mounted && success) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Camp "${updated.name}" updated successfully.')),
                      );
                    }
                  },
                  child: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteCamp(
    BuildContext context,
    CampModel camp,
    UserModel? user,
    DeviceSecurityState deviceState,
  ) {
    if (camp.totalPatientsRegistered > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.gavel, color: AppTheme.dangerRose, size: 36),
          title: const Text('Clinical Audit Rule: Cannot Delete'),
          content: Text(
            'Camp "${camp.name}" (${camp.campCode}) currently contains ${camp.totalPatientsRegistered} registered patient intake records.\n\nUnder healthcare clinical compliance and medical audit regulations, camps with patient records cannot be deleted. You can Archive this camp to preserve all clinical data in read-only mode.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppTheme.dangerRose, size: 36),
        title: const Text('Delete Camp Configuration?'),
        content: Text(
          'Are you sure you want to permanently delete camp "${camp.name}" (${camp.campCode})?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final success = await ref.read(campStateProvider.notifier).deleteCamp(
                    camp.id,
                    adminUserId: user?.id ?? 'admin-user',
                    deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                  );
              if (mounted && success) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Camp "${camp.name}" deleted.')),
                );
              }
            },
            child: const Text('Delete Camp'),
          ),
        ],
      ),
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
