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
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hub_outlined, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Camp Lifecycle & Calendar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Color(0xFFCCFBF1), fontSize: 11, fontWeight: FontWeight.normal),
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
              ? _buildEmptyStatusState(context, _statusFilter)
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
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.primaryDark),
                            ),
                          ),
                          TextSpan(
                            text: '🇳🇵 ${NepaliDateHelper.formatBsRange(camp.startDate, camp.endDate, pureNepali: true)}',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.primaryDark),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '🌐 ${_formatDate(camp.startDate)} → ${_formatDate(camp.endDate)}',
                      style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondaryLight),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people_alt_outlined, size: 14, color: AppTheme.primaryTeal),
                        const SizedBox(width: 4),
                        Text(
                          '${camp.totalPatientsRegistered} Intakes',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Assigned Staff Roster
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text.rich(
                    TextSpan(
                      text: 'Staff Team: ',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                      children: [
                        TextSpan(
                          text: camp.assignedStaffIds.isEmpty
                              ? 'None assigned'
                              : '${camp.assignedStaffIds.length} Staff Member(s)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: camp.assignedStaffIds.isEmpty ? FontWeight.normal : FontWeight.w600,
                            fontStyle: camp.assignedStaffIds.isEmpty ? FontStyle.italic : FontStyle.normal,
                            color: camp.assignedStaffIds.isEmpty ? Colors.grey : AppTheme.primaryDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                    icon: const Icon(Icons.person_add_alt_1, size: 16),
                    label: const Text('Assign Staff', style: TextStyle(fontSize: 12)),
                    onPressed: () => _showAssignStaffDialog(context, camp),
                  ),
                ],
              ),
              const Divider(height: 16),

              // Action Buttons based on Camp Status
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
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
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
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
                      if (camp.status == CampStatus.draft || camp.status == CampStatus.scheduled)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('Open for Data Entry'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.successGreen,
                            side: const BorderSide(color: AppTheme.successGreen),
                          ),
                          onPressed: () => _confirmOpenCamp(context, camp, user, deviceState),
                        ),
                      if (camp.isOpen)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.stop_circle_outlined, size: 18),
                          label: const Text('Close Camp'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.dangerRose,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _confirmCloseCamp(context, camp, user, deviceState),
                        ),
                      if (camp.status == CampStatus.closed) ...[
                        OutlinedButton.icon(
                          icon: const Icon(Icons.archive_outlined, size: 18),
                          label: const Text('Archive Camp'),
                          onPressed: () => _confirmArchiveCamp(context, camp, user, deviceState),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.replay, size: 18),
                          label: const Text('Re-Open'),
                          onPressed: () => _confirmOpenCamp(context, camp, user, deviceState),
                        ),
                      ],
                      if (camp.status == CampStatus.archived)
                        const Chip(
                          label: Text('Archived (Read-Only)', style: TextStyle(fontSize: 11)),
                          backgroundColor: Colors.black12,
                        ),
                    ],
                  ),
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
                childAspectRatio: 1.05,
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
                    child: Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
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
                childAspectRatio: 1.05,
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
                    child: Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
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
            Expanded(
              child: Text(
                dateLabel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimaryLight),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 520;
                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.event_available, color: Colors.blueGrey, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No camp scheduled on this date. This date is open for new field deployments.',
                                style: TextStyle(color: Colors.blueGrey, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Schedule Camp'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryTeal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                            onPressed: () => _showCreateCampDialog(context),
                          ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      const Icon(Icons.event_available, color: Colors.blueGrey),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'No camp scheduled on this date. This date is open for new field deployments.',
                          style: TextStyle(color: Colors.blueGrey),
                        ),
                      ),
                      const SizedBox(width: 8),
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
                  );
                },
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
                          Expanded(
                            child: Text(
                              '${c.assignedStaffIds.length} Staff Assigned  •  ${c.totalPatientsRegistered} Intakes',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryLight),
                              overflow: TextOverflow.ellipsis,
                            ),
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
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: assigned.isEmpty ? Colors.grey.shade300 : AppTheme.primaryLight,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${assigned.length} of ${staffList.length} selected',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: assigned.isEmpty ? Colors.grey.shade700 : AppTheme.primaryDark,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                    onPressed: () {
                                      setDialogState(() {
                                        assigned.addAll(staffList.map((s) => s.id));
                                      });
                                    },
                                    child: const Text('Select All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 4),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                    onPressed: () {
                                      setDialogState(() {
                                        assigned.clear();
                                      });
                                    },
                                    child: const Text('Clear All', style: TextStyle(fontSize: 12, color: AppTheme.dangerRose)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 320),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: staffList.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (_, idx) {
                                  final s = staffList[idx];
                                  final isChecked = assigned.contains(s.id);
                                  return Material(
                                    type: MaterialType.transparency,
                                    child: CheckboxListTile(
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
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
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
    final passwordCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
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
                            hintText: 'Min 6 characters',
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
                            labelText: 'Station PIN',
                            hintText: '4-6 digits',
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
                  final password = passwordCtrl.text.trim();
                  final pin = pinCtrl.text.trim();

                  if (name.isEmpty || email.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter staff name and official email.')),
                    );
                    return;
                  }

                  if (password.isEmpty || pin.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please set both an initial password and a 4-6 digit station PIN.')),
                    );
                    return;
                  }

                  if (pin.length < 4 || pin.length > 6) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Station PIN must be between 4 and 6 digits.')),
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

  void _showCreateCampDialog(BuildContext context, {CampStatus initialStatus = CampStatus.scheduled}) {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final districtCtrl = TextEditingController(text: 'Kathmandu');
    final munCtrl = TextEditingController();
    final wardCtrl = TextEditingController();
    final venueCtrl = TextEditingController();
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 2));
    CampStatus selectedStatus = initialStatus;
    // Staff assignment starts completely empty by default so admin chooses explicitly
    final selectedStaffIds = <String>{};

    final user = ref.read(authStateProvider).currentUser;
    final deviceState = ref.read(deviceSecurityProvider);

    const popularDistricts = [
      'Kathmandu', 'Dhading', 'Kaski', 'Sindhupalchok', 'Chitwan', 'Gorkha', 'Nuwakot', 'Lalitpur'
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer(
          builder: (dialogCtx, ref, _) {
            final staffAsync = ref.watch(staffUsersProvider);

            return StatefulBuilder(
              builder: (innerCtx, setDialogState) {
                final durationDays = endDate.difference(startDate).inDays + 1;
                final isDateValid = !endDate.isBefore(startDate);

                return Dialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 620,
                      maxHeight: MediaQuery.of(context).size.height * 0.9,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: const BoxDecoration(
                            color: Color(0xFF0F766E),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.add_location_alt, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Schedule Community Outreach Camp',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'नयाँ स्वास्थ्य शिविर तालिका र कर्मचारी परिचालन',
                                      style: TextStyle(color: Color(0xFFCCFBF1), fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white70),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                        ),

                        // Scrollable Form Body
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // SECTION 1: Camp Identity
                                _buildSectionHeader(Icons.badge_outlined, 'Camp Identity (शिविर पहिचान)'),
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 140,
                                      child: TextField(
                                        controller: codeCtrl,
                                        textCapitalization: TextCapitalization.characters,
                                        decoration: const InputDecoration(
                                          labelText: 'Camp Code *',
                                          hintText: 'e.g. KTM02',
                                          isDense: true,
                                          prefixIcon: Icon(Icons.tag, size: 18),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: nameCtrl,
                                        decoration: const InputDecoration(
                                          labelText: 'Official Camp Name *',
                                          hintText: 'e.g. Nilkantha Women Health Camp',
                                          isDense: true,
                                          prefixIcon: Icon(Icons.health_and_safety_outlined, size: 18),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // SECTION 2: Geographic Location
                                _buildSectionHeader(Icons.place_outlined, 'Geographic Location (नेपाल स्थान विवरण)'),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: districtCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'District *',
                                    hintText: 'e.g. Kathmandu / Dhading / Kaski',
                                    isDense: true,
                                    prefixIcon: Icon(Icons.map_outlined, size: 18),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: popularDistricts.map((dist) {
                                    final isSelected = districtCtrl.text == dist;
                                    return ActionChip(
                                      label: Text(dist, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: isSelected ? AppTheme.primaryLight : const Color(0xFFF1F5F9),
                                      onPressed: () {
                                        setDialogState(() {
                                          districtCtrl.text = dist;
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: TextField(
                                        controller: munCtrl,
                                        decoration: const InputDecoration(
                                          labelText: 'Municipality / Rural Mun.',
                                          hintText: 'e.g. Budhanilkantha',
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextField(
                                        controller: wardCtrl,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Ward No.',
                                          hintText: 'e.g. 03',
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: venueCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Venue / Health Post Facility *',
                                    hintText: 'e.g. Primary Health Care Center',
                                    isDense: true,
                                    prefixIcon: Icon(Icons.business_outlined, size: 18),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // SECTION 3: Operational Timeline (Bilingual)
                                _buildSectionHeader(Icons.calendar_today_outlined, 'Operational Timeline (सञ्चालन मिति तथा अवधि)'),
                                const SizedBox(height: 8),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final isStacked = constraints.maxWidth < 440;
                                    if (isStacked) {
                                      return Column(
                                        children: [
                                          _buildBilingualDateField(
                                            context: context,
                                            labelEn: 'Start Date',
                                            labelNp: 'सुरु मिति',
                                            date: startDate,
                                            onDateSelected: (d) => setDialogState(() => startDate = d),
                                          ),
                                          const SizedBox(height: 8),
                                          _buildBilingualDateField(
                                            context: context,
                                            labelEn: 'End Date',
                                            labelNp: 'समापन मिति',
                                            date: endDate,
                                            onDateSelected: (d) => setDialogState(() => endDate = d),
                                          ),
                                        ],
                                      );
                                    }
                                    return Row(
                                      children: [
                                        Expanded(
                                          child: _buildBilingualDateField(
                                            context: context,
                                            labelEn: 'Start Date',
                                            labelNp: 'सुरु मिति',
                                            date: startDate,
                                            onDateSelected: (d) => setDialogState(() => startDate = d),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _buildBilingualDateField(
                                            context: context,
                                            labelEn: 'End Date',
                                            labelNp: 'समापन मिति',
                                            date: endDate,
                                            onDateSelected: (d) => setDialogState(() => endDate = d),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isDateValid ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isDateValid ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isDateValid ? Icons.timer_outlined : Icons.error_outline,
                                        size: 16,
                                        color: isDateValid ? AppTheme.successGreen : AppTheme.dangerRose,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          isDateValid
                                              ? '⏱️ Deployment: $durationDays Day(s)  •  🇳🇵 ${NepaliDateHelper.formatBsRange(startDate, endDate, pureNepali: true)}'
                                              : 'End date cannot precede the start date. Please adjust the deployment period.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isDateValid ? const Color(0xFF166534) : AppTheme.dangerRose,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // SECTION 4: Status Configuration
                                _buildSectionHeader(Icons.flag_outlined, 'Deployment Lifecycle Status (शिविर स्थिति)'),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => setDialogState(() => selectedStatus = CampStatus.scheduled),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: selectedStatus == CampStatus.scheduled ? Colors.indigo.withValues(alpha: 0.1) : Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: selectedStatus == CampStatus.scheduled ? Colors.indigo : AppTheme.borderLight,
                                              width: selectedStatus == CampStatus.scheduled ? 1.5 : 1,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 18,
                                                height: 18,
                                                margin: const EdgeInsets.symmetric(horizontal: 8),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: selectedStatus == CampStatus.scheduled ? Colors.indigo : Colors.grey.shade400,
                                                    width: selectedStatus == CampStatus.scheduled ? 5 : 1.5,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text('Scheduled', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                    Text('तालिकाबद्ध (Ready to open)', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => setDialogState(() => selectedStatus = CampStatus.draft),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: selectedStatus == CampStatus.draft ? AppTheme.warningAmber.withValues(alpha: 0.12) : Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: selectedStatus == CampStatus.draft ? AppTheme.warningAmber : AppTheme.borderLight,
                                              width: selectedStatus == CampStatus.draft ? 1.5 : 1,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 18,
                                                height: 18,
                                                margin: const EdgeInsets.symmetric(horizontal: 8),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: selectedStatus == CampStatus.draft ? AppTheme.warningAmber : Colors.grey.shade400,
                                                    width: selectedStatus == CampStatus.draft ? 5 : 1.5,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text('Draft', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                    Text('मस्यौदा (Planning stage)', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // SECTION 5: Staff Dispatch (Starts 100% EMPTY!)
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildSectionHeader(Icons.people_alt_outlined, 'Staff Dispatch (कर्मचारी परिचालन)'),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: selectedStaffIds.isEmpty ? Colors.grey.shade200 : AppTheme.primaryLight,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${selectedStaffIds.length} selected',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: selectedStaffIds.isEmpty ? Colors.grey.shade700 : AppTheme.primaryDark,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                staffAsync.when(
                                  loading: () => const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
                                  error: (e, _) => Text('Error loading staff: $e', style: const TextStyle(color: AppTheme.dangerRose, fontSize: 12)),
                                  data: (staffList) {
                                    if (staffList.isEmpty) {
                                      return const Text('No registered staff members found. Staff can be registered later.', style: TextStyle(fontSize: 12, color: Colors.grey));
                                    }
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppTheme.borderLight),
                                      ),
                                      child: Column(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            child: Row(
                                              children: [
                                                const Expanded(
                                                  child: Text(
                                                    'Starts empty — select staff explicitly:',
                                                    style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                TextButton(
                                                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                                                  onPressed: () {
                                                    setDialogState(() {
                                                      selectedStaffIds.addAll(staffList.map((s) => s.id));
                                                    });
                                                  },
                                                  child: const Text('Select All', style: TextStyle(fontSize: 11)),
                                                ),
                                                TextButton(
                                                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                                                  onPressed: () {
                                                    setDialogState(() {
                                                      selectedStaffIds.clear();
                                                    });
                                                  },
                                                  child: const Text('Clear', style: TextStyle(fontSize: 11, color: AppTheme.dangerRose)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Divider(height: 1),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(maxHeight: 180),
                                            child: ListView.separated(
                                              shrinkWrap: true,
                                              itemCount: staffList.length,
                                              separatorBuilder: (_, _) => const Divider(height: 1),
                                              itemBuilder: (_, idx) {
                                                final s = staffList[idx];
                                                final isChecked = selectedStaffIds.contains(s.id);
                                                return Material(
                                                  type: MaterialType.transparency,
                                                  child: CheckboxListTile(
                                                    dense: true,
                                                    visualDensity: VisualDensity.compact,
                                                    title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                    subtitle: Text('${s.role.displayNameEn} • ${s.email}', style: const TextStyle(fontSize: 11)),
                                                    value: isChecked,
                                                    onChanged: (val) {
                                                      setDialogState(() {
                                                        if (val == true) {
                                                          selectedStaffIds.add(s.id);
                                                        } else {
                                                          selectedStaffIds.remove(s.id);
                                                        }
                                                      });
                                                    },
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Dialog Footer Actions
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                            border: Border(top: BorderSide(color: AppTheme.borderLight)),
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel'),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.edit_note, size: 16),
                                label: const Text('Save as Draft'),
                                onPressed: () => _submitCampForm(
                                  ctx: ctx,
                                  code: codeCtrl.text.trim(),
                                  name: nameCtrl.text.trim(),
                                  district: districtCtrl.text.trim(),
                                  municipality: munCtrl.text.trim(),
                                  ward: wardCtrl.text.trim(),
                                  venue: venueCtrl.text.trim(),
                                  startDate: startDate,
                                  endDate: endDate,
                                  status: CampStatus.draft,
                                  assignedStaffIds: selectedStaffIds.toList(),
                                  user: user,
                                  deviceState: deviceState,
                                ),
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.check, size: 16),
                                label: Text(selectedStatus == CampStatus.draft ? 'Save Draft' : 'Schedule Camp'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: selectedStatus == CampStatus.draft ? AppTheme.warningAmber : AppTheme.primaryTeal,
                                  foregroundColor: selectedStatus == CampStatus.draft ? Colors.black87 : Colors.white,
                                ),
                                onPressed: () => _submitCampForm(
                                  ctx: ctx,
                                  code: codeCtrl.text.trim(),
                                  name: nameCtrl.text.trim(),
                                  district: districtCtrl.text.trim(),
                                  municipality: munCtrl.text.trim(),
                                  ward: wardCtrl.text.trim(),
                                  venue: venueCtrl.text.trim(),
                                  startDate: startDate,
                                  endDate: endDate,
                                  status: selectedStatus,
                                  assignedStaffIds: selectedStaffIds.toList(),
                                  user: user,
                                  deviceState: deviceState,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _submitCampForm({
    required BuildContext ctx,
    required String code,
    required String name,
    required String district,
    required String municipality,
    required String ward,
    required String venue,
    required DateTime startDate,
    required DateTime endDate,
    required CampStatus status,
    required List<String> assignedStaffIds,
    required UserModel? user,
    required DeviceSecurityState deviceState,
  }) async {
    if (code.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both Camp Code and Camp Name.')),
      );
      return;
    }

    if (endDate.isBefore(startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camp end date cannot be before start date.')),
      );
      return;
    }

    final newCamp = CampModel(
      id: 'camp-${DateTime.now().millisecondsSinceEpoch}',
      campCode: code.toUpperCase(),
      name: name,
      district: district.isNotEmpty ? district : 'Bagmati',
      municipality: municipality,
      ward: ward.isNotEmpty ? ward : '01',
      venue: venue.isNotEmpty ? venue : 'Health Post',
      startDate: startDate,
      endDate: endDate,
      status: status,
      assignedStaffIds: assignedStaffIds,
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
      final statusLabel = status == CampStatus.draft ? 'saved as Draft' : 'scheduled';
      messenger.showSnackBar(
        SnackBar(
          content: Text('Camp "${newCamp.name}" $statusLabel with ${assignedStaffIds.length} assigned staff.'),
          action: status == CampStatus.draft
              ? SnackBarAction(
                  label: 'View Drafts',
                  textColor: Colors.amberAccent,
                  onPressed: () => setState(() => _statusFilter = AppConstants.campStatusDraft),
                )
              : (assignedStaffIds.isEmpty
                  ? SnackBarAction(
                      label: 'Assign Staff',
                      textColor: Colors.tealAccent,
                      onPressed: () => _showAssignStaffDialog(context, newCamp),
                    )
                  : null),
          duration: const Duration(seconds: 6),
        ),
      );
    }
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
            final durationDays = endDate.difference(startDate).inDays + 1;
            final isDateValid = !endDate.isBefore(startDate);

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 580,
                  maxHeight: MediaQuery.of(context).size.height * 0.88,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0F766E),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_location_alt_outlined, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Edit Camp (${camp.campCode})',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: nameCtrl,
                              decoration: const InputDecoration(labelText: 'Camp Name *', isDense: true),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: districtCtrl,
                              decoration: const InputDecoration(labelText: 'District *', isDense: true),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: munCtrl,
                                    decoration: const InputDecoration(labelText: 'Municipality', isDense: true),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: wardCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'Ward', isDense: true),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: venueCtrl,
                              decoration: const InputDecoration(labelText: 'Venue / Facility *', isDense: true),
                            ),
                            const SizedBox(height: 16),
                            _buildSectionHeader(Icons.calendar_today_outlined, 'Bilingual Dates (नेपाली र अंग्रेजी मिति)'),
                            const SizedBox(height: 8),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isStacked = constraints.maxWidth < 440;
                                if (isStacked) {
                                  return Column(
                                    children: [
                                      _buildBilingualDateField(
                                        context: context,
                                        labelEn: 'Start Date',
                                        labelNp: 'सुरु मिति',
                                        date: startDate,
                                        onDateSelected: (d) => setDialogState(() => startDate = d),
                                      ),
                                      const SizedBox(height: 8),
                                      _buildBilingualDateField(
                                        context: context,
                                        labelEn: 'End Date',
                                        labelNp: 'समापन मिति',
                                        date: endDate,
                                        onDateSelected: (d) => setDialogState(() => endDate = d),
                                      ),
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(
                                      child: _buildBilingualDateField(
                                        context: context,
                                        labelEn: 'Start Date',
                                        labelNp: 'सुरु मिति',
                                        date: startDate,
                                        onDateSelected: (d) => setDialogState(() => startDate = d),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _buildBilingualDateField(
                                        context: context,
                                        labelEn: 'End Date',
                                        labelNp: 'समापन मिति',
                                        date: endDate,
                                        onDateSelected: (d) => setDialogState(() => endDate = d),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isDateValid ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDateValid ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isDateValid ? Icons.timer_outlined : Icons.error_outline,
                                    size: 16,
                                    color: isDateValid ? AppTheme.successGreen : AppTheme.dangerRose,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      isDateValid
                                          ? '⏱️ Deployment: $durationDays Day(s)  •  🇳🇵 ${NepaliDateHelper.formatBsRange(startDate, endDate, pureNepali: true)}'
                                          : 'End date cannot precede the start date.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDateValid ? const Color(0xFF166534) : AppTheme.dangerRose,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                        border: Border(top: BorderSide(color: AppTheme.borderLight)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Save Changes'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, foregroundColor: Colors.white),
                            onPressed: () async {
                              if (nameCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Camp name cannot be empty.')),
                                );
                                return;
                              }

                              if (endDate.isBefore(startDate)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('End date cannot precede the start date.')),
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
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
  // BILINGUAL DATE PICKER & CARDS
  // ==========================================
  Widget _buildBilingualDateField({
    required BuildContext context,
    required String labelEn,
    required String labelNp,
    required DateTime date,
    required ValueChanged<DateTime> onDateSelected,
    Color accentColor = AppTheme.primaryTeal,
  }) {
    final nepaliDate = NepaliDateHelper.toNepali(date);
    final bsFormatted = 'वि.सं. ${nepaliDate.year} ${NepaliDateHelper.nepaliMonthPureNp[nepaliDate.month - 1]} ${nepaliDate.day}';
    final adFormatted = '${_formatDate(date)} (${_getDayOfWeekShort(date.weekday)})';

    return InkWell(
      onTap: () async {
        final picked = await _showBilingualDatePicker(context, initialDate: date);
        if (picked != null) {
          onDateSelected(picked);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, size: 15, color: accentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$labelEn ($labelNp)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              bsFormatted,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimaryLight),
            ),
            const SizedBox(height: 2),
            Text(
              '🌐 $adFormatted',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _showBilingualDatePicker(
    BuildContext context, {
    required DateTime initialDate,
  }) async {
    DateTime tempDate = initialDate;
    bool isNepaliMode = true;
    NepaliDateTime bsMonth = NepaliDateHelper.toNepali(tempDate);
    bsMonth = NepaliDateTime(bsMonth.year, bsMonth.month, 1);
    DateTime adMonth = DateTime(tempDate.year, tempDate.month, 1);

    return showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (pickerCtx, setPickerState) {
            final currentBs = NepaliDateHelper.toNepali(tempDate);
            final bsDisplay = 'वि.सं. ${currentBs.year} ${NepaliDateHelper.nepaliMonthPureNp[currentBs.month - 1]} ${currentBs.day}';
            final adDisplay = '${_formatDate(tempDate)} (${_getDayOfWeekShort(tempDate.weekday)})';

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top Header: Live Bilingual Preview Card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF042F2E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.calendar_month, color: Color(0xFFCCFBF1), size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Bilingual Date Picker (नेपाली र अंग्रेजी मिति)',
                                  style: TextStyle(color: Color(0xFFCCFBF1), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              bsDisplay,
                              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '🌐 Gregorian (AD): $adDisplay',
                              style: const TextStyle(color: Color(0xFF99F6E4), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Segmented Mode Toggle: BS vs AD
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
                                isSelected: isNepaliMode,
                                onTap: () => setPickerState(() => isNepaliMode = true),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildCalendarModePill(
                                title: '🌐 Gregorian (AD)',
                                isSelected: !isNepaliMode,
                                onTap: () => setPickerState(() => isNepaliMode = false),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Calendar Grid Area
                      if (isNepaliMode) ...[
                        // BS Month Navigation
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left, size: 20, color: AppTheme.primaryTeal),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setPickerState(() {
                                  int m = bsMonth.month - 1;
                                  int y = bsMonth.year;
                                  if (m < 1) {
                                    m = 12;
                                    y--;
                                  }
                                  bsMonth = NepaliDateTime(y, m, 1);
                                });
                              },
                            ),
                            Text(
                              '${NepaliDateHelper.nepaliMonthPureNp[bsMonth.month - 1]} ${bsMonth.year} (${NepaliDateHelper.nepaliMonthPureEn[bsMonth.month - 1]} BS)',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_right, size: 20, color: AppTheme.primaryTeal),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setPickerState(() {
                                  int m = bsMonth.month + 1;
                                  int y = bsMonth.year;
                                  if (m > 12) {
                                    m = 1;
                                    y++;
                                  }
                                  bsMonth = NepaliDateTime(y, m, 1);
                                });
                              },
                            ),
                          ],
                        ),
                        // Days Header
                        Row(
                          children: [
                            _buildDayHeader('आई'),
                            _buildDayHeader('सोम'),
                            _buildDayHeader('मंगल'),
                            _buildDayHeader('बुध'),
                            _buildDayHeader('बिही'),
                            _buildDayHeader('शुक्र'),
                            _buildDayHeader('शनि', isHoliday: true),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Days Grid
                        Builder(
                          builder: (_) {
                            final daysInMonth = NepaliDateHelper.getDaysInBsMonth(bsMonth.year, bsMonth.month);
                            final firstDayOffset = NepaliDateHelper.getFirstDayWeekdayBs(bsMonth.year, bsMonth.month);

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: 42,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                mainAxisSpacing: 3,
                                crossAxisSpacing: 3,
                                childAspectRatio: 1.15,
                              ),
                              itemBuilder: (context, idx) {
                                final dayOffset = idx - firstDayOffset;
                                if (dayOffset < 0 || dayOffset >= daysInMonth) {
                                  return const SizedBox.shrink();
                                }
                                final dayNum = dayOffset + 1;
                                final cellBs = NepaliDateTime(bsMonth.year, bsMonth.month, dayNum);
                                final isSelected = currentBs.year == cellBs.year &&
                                    currentBs.month == cellBs.month &&
                                    currentBs.day == cellBs.day;
                                final isSaturday = cellBs.weekday == 7;

                                return InkWell(
                                  onTap: () {
                                    setPickerState(() {
                                      tempDate = cellBs.toDateTime();
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isSelected ? AppTheme.primaryTeal : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '$dayNum',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        color: isSelected
                                            ? Colors.white
                                            : (isSaturday ? const Color(0xFFDC2626) : Colors.black87),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ] else ...[
                        // AD Month Navigation
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left, size: 20, color: AppTheme.primaryTeal),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setPickerState(() {
                                  adMonth = DateTime(adMonth.year, adMonth.month - 1, 1);
                                });
                              },
                            ),
                            Text(
                              '${_getMonthName(adMonth.month)} ${adMonth.year}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_right, size: 20, color: AppTheme.primaryTeal),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setPickerState(() {
                                  adMonth = DateTime(adMonth.year, adMonth.month + 1, 1);
                                });
                              },
                            ),
                          ],
                        ),
                        // Days Header
                        Row(
                          children: [
                            _buildDayHeader('Sun', isHoliday: true),
                            _buildDayHeader('Mon'),
                            _buildDayHeader('Tue'),
                            _buildDayHeader('Wed'),
                            _buildDayHeader('Thu'),
                            _buildDayHeader('Fri'),
                            _buildDayHeader('Sat'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // AD Grid
                        Builder(
                          builder: (_) {
                            final daysInMonth = DateUtils.getDaysInMonth(adMonth.year, adMonth.month);
                            final firstDayWeekday = DateTime(adMonth.year, adMonth.month, 1).weekday % 7;

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: 42,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                mainAxisSpacing: 3,
                                crossAxisSpacing: 3,
                                childAspectRatio: 1.15,
                              ),
                              itemBuilder: (context, idx) {
                                final dayOffset = idx - firstDayWeekday;
                                if (dayOffset < 0 || dayOffset >= daysInMonth) {
                                  return const SizedBox.shrink();
                                }
                                final dayNum = dayOffset + 1;
                                final cellAd = DateTime(adMonth.year, adMonth.month, dayNum);
                                final isSelected = tempDate.year == cellAd.year &&
                                    tempDate.month == cellAd.month &&
                                    tempDate.day == cellAd.day;
                                final isSun = cellAd.weekday == 7;

                                return InkWell(
                                  onTap: () {
                                    setPickerState(() {
                                      tempDate = cellAd;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isSelected ? AppTheme.primaryTeal : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '$dayNum',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        color: isSelected
                                            ? Colors.white
                                            : (isSun ? const Color(0xFFDC2626) : Colors.black87),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],

                      const SizedBox(height: 10),
                      // Quick Shortcuts
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _buildQuickDateChip('Today (आज)', () {
                            setPickerState(() {
                              tempDate = DateTime.now();
                              final bs = NepaliDateHelper.toNepali(tempDate);
                              bsMonth = NepaliDateTime(bs.year, bs.month, 1);
                              adMonth = DateTime(tempDate.year, tempDate.month, 1);
                            });
                          }),
                          _buildQuickDateChip('Tomorrow (भोलि)', () {
                            setPickerState(() {
                              tempDate = DateTime.now().add(const Duration(days: 1));
                              final bs = NepaliDateHelper.toNepali(tempDate);
                              bsMonth = NepaliDateTime(bs.year, bs.month, 1);
                              adMonth = DateTime(tempDate.year, tempDate.month, 1);
                            });
                          }),
                          _buildQuickDateChip('+3 Days', () {
                            setPickerState(() {
                              tempDate = DateTime.now().add(const Duration(days: 3));
                              final bs = NepaliDateHelper.toNepali(tempDate);
                              bsMonth = NepaliDateTime(bs.year, bs.month, 1);
                              adMonth = DateTime(tempDate.year, tempDate.month, 1);
                            });
                          }),
                          _buildQuickDateChip('+7 Days', () {
                            setPickerState(() {
                              tempDate = DateTime.now().add(const Duration(days: 7));
                              final bs = NepaliDateHelper.toNepali(tempDate);
                              bsMonth = NepaliDateTime(bs.year, bs.month, 1);
                              adMonth = DateTime(tempDate.year, tempDate.month, 1);
                            });
                          }),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Dialog Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, null),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Confirm Date'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryTeal,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(ctx, tempDate),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================
  // CONTEXTUAL EMPTY STATES
  // ==========================================
  Widget _buildEmptyStatusState(BuildContext context, String statusFilter) {
    IconData icon;
    Color accentColor;
    String titleEn;
    String titleNp;
    String description;
    Widget? actionWidget;

    switch (statusFilter) {
      case AppConstants.campStatusDraft:
        icon = Icons.edit_note_rounded;
        accentColor = AppTheme.warningAmber;
        titleEn = 'No Draft Camps';
        titleNp = 'कुनै मस्यौदा शिविर फेला परेन';
        description =
            'Draft camps allow outreach coordinators to prepare logistical plans, facility requirements, and venues before officially scheduling field staff. Save an upcoming deployment as draft to view it here.';
        actionWidget = ElevatedButton.icon(
          icon: const Icon(Icons.add_task, size: 16),
          label: const Text('Create Draft Camp (नयाँ मस्यौदा)'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.warningAmber,
            foregroundColor: Colors.black87,
          ),
          onPressed: () => _showCreateCampDialog(context, initialStatus: CampStatus.draft),
        );
        break;

      case AppConstants.campStatusArchived:
        icon = Icons.archive_outlined;
        accentColor = Colors.purple;
        titleEn = 'No Archived Camps';
        titleNp = 'कुनै अभिलेखिकृत शिविर छैन';
        description =
            'Archived camps represent finalized outreach missions preserved in immutable, read-only status for clinical audit and healthcare reporting. Completed camps can be archived once closed.';
        actionWidget = OutlinedButton.icon(
          icon: const Icon(Icons.list_alt, size: 16),
          label: const Text('View All Active Camps'),
          onPressed: () => setState(() => _statusFilter = 'ALL'),
        );
        break;

      case AppConstants.campStatusScheduled:
        icon = Icons.event_available_outlined;
        accentColor = Colors.indigo;
        titleEn = 'No Scheduled Camps';
        titleNp = 'कुनै तालिकाबद्ध शिविर छैन';
        description =
            'Scheduled camps are planned outreach deployments ready to be dispatched. Once field personnel arrive at the venue, administrators can open the camp for clinical patient intake.';
        actionWidget = ElevatedButton.icon(
          icon: const Icon(Icons.add_location_alt, size: 16),
          label: const Text('Schedule Outreach Camp'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
          ),
          onPressed: () => _showCreateCampDialog(context, initialStatus: CampStatus.scheduled),
        );
        break;

      case AppConstants.campStatusClosed:
        icon = Icons.fact_check_outlined;
        accentColor = const Color(0xFF0F766E);
        titleEn = 'No Closed Camps';
        titleNp = 'कुनै बन्द शिविर छैन';
        description =
            'When an outreach mission concludes, closing the camp prevents further data entry and prepares clinical records for central synchronization and archiving.';
        actionWidget = OutlinedButton.icon(
          icon: const Icon(Icons.list_alt, size: 16),
          label: const Text('View All Active Camps'),
          onPressed: () => setState(() => _statusFilter = 'ALL'),
        );
        break;

      case AppConstants.campStatusOpen:
        icon = Icons.health_and_safety_outlined;
        accentColor = AppTheme.successGreen;
        titleEn = 'No Active Camps';
        titleNp = 'कुनै सक्रिय शिविर छैन';
        description =
            'No outreach camp is currently open for clinical intake. You can open a scheduled camp from the roster to start registering patients.';
        actionWidget = ElevatedButton.icon(
          icon: const Icon(Icons.event_available, size: 16),
          label: const Text('View Scheduled Camps'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
          onPressed: () => setState(() => _statusFilter = AppConstants.campStatusScheduled),
        );
        break;

      default:
        icon = Icons.campaign_outlined;
        accentColor = AppTheme.primaryTeal;
        titleEn = 'No Camps Found';
        titleNp = 'शिविर सूची खाली छ';
        description =
            'No outreach camps match the current filter. Schedule a new healthcare outreach camp to organize patient registration and field workflows.';
        actionWidget = ElevatedButton.icon(
          icon: const Icon(Icons.add_location_alt, size: 16),
          label: const Text('Schedule First Camp'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, foregroundColor: Colors.white),
          onPressed: () => _showCreateCampDialog(context),
        );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.all(28.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderLight),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 32, color: accentColor),
                ),
                const SizedBox(height: 16),
                Text(
                  titleEn,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimaryLight),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  titleNp,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  style: const TextStyle(fontSize: 13, height: 1.45, color: AppTheme.textSecondaryLight),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                actionWidget,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // HELPERS
  // ==========================================
  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppTheme.primaryTeal),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimaryLight),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickDateChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
      backgroundColor: const Color(0xFFF1F5F9),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: onTap,
    );
  }

  String _getDayOfWeekShort(int weekday) {
    switch (weekday) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      case 7:
        return 'Sun';
      default:
        return '';
    }
  }

  Color _getStatusColor(CampStatus status) {
    switch (status) {
      case CampStatus.open:
        return AppTheme.successGreen;
      case CampStatus.scheduled:
        return Colors.indigo;
      case CampStatus.draft:
        return AppTheme.warningAmber;
      case CampStatus.closed:
        return AppTheme.dangerRose;
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
