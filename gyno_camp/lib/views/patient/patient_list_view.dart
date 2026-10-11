import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        Clipboard,
        ClipboardData,
        FilteringTextInputFormatter,
        LengthLimitingTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/clinical_constants.dart';
import '../../core/constants/nepal_geodata.dart';
import '../../core/providers/organization_provider.dart';
import '../../core/services/document_capture_service.dart';
import '../../core/services/file_download_helper.dart';
import '../../core/services/pdf_report_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/camp_model.dart';
import '../../models/patient_model.dart';
import '../../models/user_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/clinical_assessment_viewmodel.dart';
import '../../viewmodels/master_lookup_viewmodel.dart';
import '../../viewmodels/patient_list_viewmodel.dart';
import '../../viewmodels/patient_registration_viewmodel.dart';
import '../../viewmodels/reporting_viewmodel.dart';
import '../../viewmodels/sync_viewmodel.dart';
import '../scanner/form_scan_view.dart';
import '../shared/blank_form_download_dialog.dart';
import 'clinical_assessment_view.dart';
import 'clinical_history_panel.dart';
import 'patient_follow_up_form_view.dart';
import 'patient_follow_up_slip_modal.dart';
import 'patient_registration_view.dart';

class PatientListView extends ConsumerStatefulWidget {
  final String? campId;
  final String? initialQuery;
  const PatientListView({super.key, this.campId, this.initialQuery});

  @override
  ConsumerState<PatientListView> createState() => _PatientListViewState();
}

class _PatientListViewState extends ConsumerState<PatientListView> {
  static const Map<String, String> _clinicalLabelMap = {
    'routine_checkup': 'Routine Checkup (नियमित जाँच)',
    'checkup': 'Routine Checkup (नियमित जाँच)',
    'something hanging out': 'Prolapse / Something Hanging Out (आङ खस्ने)',
    'something_hanging_out': 'Prolapse / Something Hanging Out (आङ खस्ने)',
    'discharge and or itching': 'White Discharge & Itching (सेतो पानी तथा चिलाउने)',
    'discharge_and_or_itching': 'White Discharge & Itching (सेतो पानी तथा चिलाउने)',
    'discharge_itching': 'White Discharge & Itching (सेतो पानी तथा चिलाउने)',
    'problems passing urine': 'Urinary Problems (पिसाब सम्बन्धी)',
    'problems_passing_urine': 'Urinary Problems (पिसाब सम्बन्धी)',
    'problems passing stool': 'Bowel / Stool Problems (दिसा सम्बन्धी)',
    'problems_passing_stool': 'Bowel / Stool Problems (दिसा सम्बन्धी)',
    'menstrual problem': 'Menstrual Problem (महिनावारी गडबडी)',
    'menstrual_problem': 'Menstrual Problem (महिनावारी गडबडी)',
    'infertility': 'Infertility (निःसन्तान)',
    'pain': 'Pelvic / Lower Abdominal Pain (तल्लो पेट / कम्मर दुख्ने)',
    'lower_abdominal_pain': 'Lower Abdominal Pain (तल्लो पेट दुख्ने)',
    'post_menopausal_bleeding': 'Post-Menopausal Bleeding (महिनावारी रोकिएपछिको रक्तस्राव)',
  };

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _municipalityFilterController =
      TextEditingController();
  final TextEditingController _minAgeController = TextEditingController();
  final TextEditingController _maxAgeController = TextEditingController();

  bool _showFilterPanel = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetCampId = widget.campId ??
          ref.read(userActiveCampProvider)?.id ??
          ref.read(campStateProvider).activeCamp?.id ??
          (ref.read(campStateProvider).camps.isNotEmpty
              ? ref.read(campStateProvider).camps.first.id
              : null);
      ref.read(masterLookupProvider.notifier).setCampScope(targetCampId);
      if (widget.initialQuery != null &&
          widget.initialQuery!.trim().isNotEmpty) {
        _searchController.text = widget.initialQuery!.trim();
        ref
            .read(patientListProvider.notifier)
            .search(targetCampId, widget.initialQuery!.trim());
      } else {
        ref.read(patientListProvider.notifier).loadPatients(targetCampId);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _municipalityFilterController.dispose();
    _minAgeController.dispose();
    _maxAgeController.dispose();
    super.dispose();
  }

  void _reloadCurrentList(PatientListViewModel vm, {bool silent = false}) {
    final currentFilter = ref.read(patientListProvider).filters.campId;
    if (currentFilter == 'all') {
      vm.loadPatients('all', silent);
    } else if (currentFilter != null && currentFilter.isNotEmpty) {
      vm.loadPatients(currentFilter, silent);
    } else {
      final active = ref.read(userActiveCampProvider) ??
          ref.read(campStateProvider).activeCamp ??
          (ref.read(campStateProvider).camps.isNotEmpty
              ? ref.read(campStateProvider).camps.first
              : null);
      if (active != null) {
        vm.loadPatients(active.id, silent);
      } else {
        vm.loadPatients('all', silent);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final campState = ref.watch(campStateProvider);
    final patientState = ref.watch(patientListProvider);
    final vm = ref.read(patientListProvider.notifier);
    // Use user-scoped camp so staff see their assigned camp, not the global one
    final activeCamp = ref.watch(userActiveCampProvider) ??
        campState.activeCamp ??
        (campState.camps.isNotEmpty ? campState.camps.first : null);
    final filterCampId = patientState.filters.campId;
    final bool isAllCamps = filterCampId == 'all';
    final effectiveCamp = isAllCamps
        ? null
        : (filterCampId != null
            ? campState.camps.cast<CampModel?>().firstWhere(
                  (c) => c?.id == filterCampId,
                  orElse: () => activeCamp,
                )
            : (widget.campId != null
                ? campState.camps.cast<CampModel?>().firstWhere(
                      (c) => c?.id == widget.campId,
                      orElse: () => activeCamp,
                    )
                : activeCamp));
    final effectiveCampId = effectiveCamp?.id;

    // Only auto-switch patient roll on activeCamp change if not explicitly bound to a campId
    if (widget.campId == null) {
      ref.listen<CampModel?>(userActiveCampProvider, (previous, next) {
        // Once the list has loaded, never auto-switch view on background updates
        if (patientState.hasLoaded || patientState.filters.campId == 'all') return;

        if (next != null &&
            (previous?.id != next.id || !patientState.hasLoaded)) {
          if (_searchController.text.trim().isNotEmpty) {
            ref
                .read(patientListProvider.notifier)
                .search(next.id, _searchController.text.trim());
          } else {
            ref.read(patientListProvider.notifier).loadPatients(next.id);
          }
        }
      });
    }

    ref.listen<SyncState>(syncStateProvider, (previous, next) {
      if (previous?.lastSyncedAt != next.lastSyncedAt && next.lastSyncedAt != null) {
        _reloadCurrentList(vm, silent: true);
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: 68,
        elevation: 0,
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            gradient: LinearGradient(
              colors: [
                const Color(0xFF30026E).withValues(alpha: 0.08), // Light brand purple with opacity
                const Color(0xFF81005D).withValues(alpha: 0.05), // Light brand magenta with opacity
                const Color(0xFFF8FAFC),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2.5),
          child: Container(
            height: 2.5,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF81005D), // WFWSN deep magenta/pink from logo
                  Color(0xFFBE185D), // Vibrant dark pink
                  Color(0xFF9D174D), // Deep rich pink
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
        ),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1E0A38), size: 18),
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context),
              )
            : null,
        titleSpacing: Navigator.canPop(context) ? 0 : 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Camp Patient Roll',
              style: TextStyle(
                color: Color(0xFF1E0A38),
                fontSize: 17.5,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            Builder(builder: (context) {
              final selectedCampId = patientState.filters.campId ?? effectiveCampId;
              if (selectedCampId == null || selectedCampId == 'all') {
                return Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF30026E).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFF30026E).withValues(alpha: 0.18)),
                  ),
                  child: const Text(
                    'All Camps (सबै क्याम्पहरू)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF30026E),
                      letterSpacing: 0.1,
                    ),
                  ),
                );
              }

              final displayedCamp = campState.camps.cast<CampModel?>().firstWhere(
                    (c) => c?.id == selectedCampId,
                    orElse: () => effectiveCamp,
                  );

              if (displayedCamp != null) {
                return Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF30026E).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFF30026E).withValues(alpha: 0.18)),
                  ),
                  child: Text(
                    '${displayedCamp.name}  •  ${displayedCamp.campCode}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF30026E),
                      letterSpacing: 0.1,
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Tooltip(
                message: 'Refresh Patient List',
                child: InkWell(
                  onTap: () => _reloadCurrentList(vm),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.refresh_rounded, color: Color(0xFF475569), size: 20),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: (effectiveCamp == null && activeCamp == null)
            ? Colors.grey.shade400
            : const Color(0xFF81005D),
        elevation: 4,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text(
          'New Patient',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        onPressed: (effectiveCamp == null && activeCamp == null)
            ? () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'No camp selected. Please select a camp first.',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              )
            : () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PatientRegistrationView(),
                  ),
                );
                if (mounted) {
                  _reloadCurrentList(vm);
                }
              },
      ),
      body: (effectiveCamp == null && !isAllCamps)
          ? const Center(
              child: Text(
                'No active camp selected. Please activate a camp first.',
              ),
            )
          : LayoutBuilder(
              builder: (context, viewportConstraints) {
                final isDesktop = viewportConstraints.maxWidth >= 900;

                if (isDesktop) {
                  return Column(
                    children: [
                      // Full-width Header Toolbar with Edge Padding (No artificial maxWidth cage)
                      _buildSearchAndActionHeader(
                        effectiveCampId: effectiveCampId,
                        isAllCamps: isAllCamps,
                        activeCamp: activeCamp,
                        patientState: patientState,
                        vm: vm,
                        isWide: true,
                        isDesktop: true,
                        campState: campState,
                      ),

                      // Full-width Statistics Bar with Edge Padding
                      _buildStatisticsBar(
                        patientState,
                        vm,
                        isWide: true,
                      ),

                      // Main Workspace Area (Sidebar + Responsive Card Grid)
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Desktop Left Sidebar for Dedicated Patient Filters
                            if (_showFilterPanel) ...[
                              SizedBox(
                                width: 320,
                                height: viewportConstraints.maxHeight,
                                child: _buildDedicatedFilterSection(
                                  context,
                                  campState,
                                  patientState,
                                  vm,
                                  isSidebar: true,
                                ),
                              ),
                              const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                            ],

                            // Patient Cards List (Responsive Multi-Column Grid on Desktop)
                            Expanded(
                              child: _buildPatientCardsList(
                                effectiveCampId,
                                effectiveCamp ?? activeCamp,
                                patientState,
                                vm,
                                campState,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                // Mobile / Tablet Stacked Layout (< 900px)
                return Column(
                  children: [
                    // Search & Filter Header
                    _buildSearchAndActionHeader(
                      effectiveCampId: effectiveCampId,
                      isAllCamps: isAllCamps,
                      activeCamp: activeCamp,
                      patientState: patientState,
                      vm: vm,
                      isWide: viewportConstraints.maxWidth >= 700,
                      isDesktop: false,
                      campState: campState,
                    ),

                    // Patient Roll Statistics Bar (Includes active filter pills & Reset All)
                    _buildStatisticsBar(patientState, vm, isWide: false),

                    // Patient Cards List (100% full height on mobile)
                    Expanded(
                      child: _buildPatientCardsList(
                        effectiveCampId,
                        effectiveCamp ?? activeCamp,
                        patientState,
                        vm,
                        campState,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildSearchAndActionHeader({
    required String? effectiveCampId,
    required bool isAllCamps,
    required CampModel? activeCamp,
    required PatientListState patientState,
    required PatientListViewModel vm,
    required bool isWide,
    required bool isDesktop,
    required CampState campState,
  }) {
    final searchField = TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search by Patient ID, Name, Phone, Ward, District...',
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 14, right: 10),
          child: Icon(Icons.search_rounded, color: AppTheme.primaryTeal, size: 20),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                tooltip: 'Clear Search',
                onPressed: () {
                  _searchController.clear();
                  vm.search(isAllCamps ? 'all' : effectiveCampId, '');
                },
              )
            : null,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.8),
        ),
      ),
      onChanged: (val) => vm.search(isAllCamps ? 'all' : effectiveCampId, val),
    );

    final filterButton = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: patientState.filters.hasActiveFilters
            ? Colors.white
            : AppTheme.primaryTeal,
        backgroundColor: patientState.filters.hasActiveFilters
            ? AppTheme.primaryTeal
            : Colors.transparent,
        side: BorderSide(
          color: patientState.filters.hasActiveFilters
              ? AppTheme.primaryTeal
              : const Color(0xFFCBD5E1),
          width: 1.4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(
        isDesktop
            ? (_showFilterPanel ? Icons.filter_alt_off_rounded : Icons.filter_alt_rounded)
            : Icons.tune_rounded,
        size: 17,
      ),
      label: Text(
        patientState.filters.hasActiveFilters
            ? 'Filters (${patientState.filters.activeFilterCount})'
            : 'Filters',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      onPressed: () {
        if (isDesktop) {
          setState(() => _showFilterPanel = !_showFilterPanel);
        } else {
          _showMobileFilterBottomSheet(context, campState, patientState, vm);
        }
      },
    );

    final scanButton = FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.1),
        foregroundColor: AppTheme.primaryTeal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
      label: const Text('Scan QR / Barcode', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      onPressed: (effectiveCampId == null && !isAllCamps && activeCamp?.id == null)
          ? null
          : () => _showScanTokenDialog(
              context,
              effectiveCampId ?? activeCamp?.id ?? '',
              vm,
              patientState.rawPatients,
            ),
    );

    final blankFormsButton = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.4),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF475569),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.print_outlined, size: 17),
      label: const Text('Blank Forms', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      onPressed: () {
        final campState = ref.read(campStateProvider);
        CampModel? targetCamp;
        try {
          if (effectiveCampId != null) {
            targetCamp = campState.camps.firstWhere((c) => c.id == effectiveCampId);
          }
        } catch (_) {}
        targetCamp ??= activeCamp ?? campState.activeCamp;
        BlankFormDownloadDialog.show(context, camp: targetCamp);
      },
    );

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: isWide ? 24.0 : 16.0, vertical: 10.0),
      child: isWide
          ? Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 10),
                filterButton,
                const SizedBox(width: 8),
                scanButton,
                const SizedBox(width: 8),
                blankFormsButton,
              ],
            )
          : Column(
              children: [
                searchField,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: filterButton),
                    const SizedBox(width: 8),
                    Expanded(child: scanButton),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: blankFormsButton,
                ),
              ],
            ),
    );
  }

  Widget _buildStatisticsBar(
    PatientListState patientState,
    PatientListViewModel vm, {
    bool isWide = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 24.0 : 16.0, vertical: 7),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, statsConstraints) {
          final isNarrow = statsConstraints.maxWidth < 450;
          final hasActiveFilters = patientState.filters.hasActiveFilters;
          final count = patientState.patients.length;

          return Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: hasActiveFilters
                              ? AppTheme.warningAmber.withValues(alpha: 0.1)
                              : AppTheme.brandPurpleLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: hasActiveFilters
                                ? AppTheme.warningAmber.withValues(alpha: 0.35)
                                : AppTheme.brandPurpleBorder,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasActiveFilters ? Icons.filter_alt_rounded : Icons.people_alt_rounded,
                              size: 13,
                              color: hasActiveFilters ? AppTheme.warningAmber : AppTheme.primaryTeal,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              hasActiveFilters
                                  ? '$count of ${patientState.rawPatients.length} Patients'
                                  : 'Total: $count Registered',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                color: hasActiveFilters
                                    ? const Color(0xFF92400E)
                                    : AppTheme.primaryDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasActiveFilters) ...[
                        const SizedBox(width: 8),
                        ..._buildActiveFilterPills(patientState.filters, vm),
                        InkWell(
                          onTap: () => _clearAllFilters(vm),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.dangerRose.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.dangerRose.withValues(alpha: 0.25)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.close_rounded, size: 12, color: AppTheme.dangerRose),
                                SizedBox(width: 3),
                                Text(
                                  'Reset All',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.dangerRose,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.brandPurpleLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.brandPurpleBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded, size: 12, color: AppTheme.primaryTeal),
                    const SizedBox(width: 4),
                    Text(
                      isNarrow
                          ? 'AES-256'
                          : (patientState.patients.isNotEmpty
                              ? 'AES-256 Encrypted \u2022 $count Records'
                              : 'AES-256 Encrypted'),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.primaryDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPatientCardsList(
    String? effectiveCampId,
    CampModel? effectiveCamp,
    PatientListState patientState,
    PatientListViewModel vm,
    CampState campState,
  ) {
    if (patientState.isLoading && patientState.patients.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        patientState.patients.isEmpty
            ? _buildEmptyState(context, effectiveCampId, vm)
            : RefreshIndicator(
                onRefresh: () async {
                  _reloadCurrentList(vm);
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth = constraints.maxWidth;
                    final double horizontalPadding = availableWidth >= 1200
                        ? 24.0
                        : (availableWidth >= 800 ? 18.0 : 12.0);
                    const double minTableWidth = 860.0;
                    final double contentWidth = availableWidth - (horizontalPadding * 2);
                    final double effectiveTableWidth = contentWidth > minTableWidth
                        ? contentWidth
                        : minTableWidth;

                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 14,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0A000000),
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: SizedBox(
                            width: effectiveTableWidth,
                            height: constraints.maxHeight.isFinite
                                ? (constraints.maxHeight - 28)
                                : null,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildTableHeader(),
                                Expanded(
                                  child: ListView.separated(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    itemCount: patientState.patients.length,
                                    separatorBuilder: (_, _) => const Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: Color(0xFFF1F5F9),
                                    ),
                                    itemBuilder: (context, index) {
                                      final patient = patientState.patients[index];
                                      return _buildTableRow(
                                        context: context,
                                        patient: patient,
                                        activeCamp: effectiveCamp,
                                        vm: vm,
                                        campState: campState,
                                        isEven: index.isEven,
                                      );
                                    },
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
              ),
        if (patientState.isLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2.5,
              color: AppTheme.primaryTeal,
              backgroundColor: Colors.transparent,
            ),
          ),
      ],
    );
  }

  void _clearAllFilters(PatientListViewModel vm) {
    _municipalityFilterController.clear();
    _minAgeController.clear();
    _maxAgeController.clear();
    vm.resetFilters();
  }

  List<Widget> _buildActiveFilterPills(
    PatientFilterCriteria filters,
    PatientListViewModel vm,
  ) {
    final pills = <Widget>[];

    // Age
    if (filters.minAge != null || filters.maxAge != null) {
      final label = 'Age: ${filters.minAge ?? 0}-${filters.maxAge ?? "∞"}y';
      pills.add(_buildFilterPill(label, () {
        _minAgeController.clear();
        _maxAgeController.clear();
        vm.updateFilters(filters.copyWith(clearMinAge: true, clearMaxAge: true));
      }));
    }

    // Chief Complaint
    if (filters.chiefComplaint != null &&
        filters.chiefComplaint!.isNotEmpty &&
        filters.chiefComplaint != 'all') {
      pills.add(_buildFilterPill('Complaint: ${filters.chiefComplaint}', () {
        vm.updateFilters(filters.copyWith(clearChiefComplaint: true));
      }));
    }

    // Disease / Diagnosis
    if (filters.disease != null &&
        filters.disease!.isNotEmpty &&
        filters.disease != 'all') {
      pills.add(_buildFilterPill('Dx: ${filters.disease}', () {
        vm.updateFilters(filters.copyWith(clearDisease: true));
      }));
    }

    // POP Stage
    if (filters.popStage != null && filters.popStage != 'all') {
      pills.add(_buildFilterPill('Stage: ${filters.popStage}', () {
        vm.updateFilters(filters.copyWith(popStage: 'all'));
      }));
    }

    // Doctor
    if (filters.doctor != null && filters.doctor != 'all' && filters.doctor!.isNotEmpty) {
      pills.add(_buildFilterPill('Dr: ${filters.doctor}', () {
        vm.updateFilters(filters.copyWith(doctor: 'all'));
      }));
    }

    // Nurse
    if (filters.nurse != null && filters.nurse != 'all' && filters.nurse!.isNotEmpty) {
      pills.add(_buildFilterPill('Nurse: ${filters.nurse}', () {
        vm.updateFilters(filters.copyWith(nurse: 'all'));
      }));
    }

    // Clinical Intake
    if (filters.clinicalIntake != null && filters.clinicalIntake != 'all') {
      pills.add(_buildFilterPill('Intake: ${filters.clinicalIntake}', () {
        vm.updateFilters(filters.copyWith(clinicalIntake: 'all'));
      }));
    }

    // Level of Treatment
    if (filters.treatmentLevel != null &&
        filters.treatmentLevel!.isNotEmpty &&
        filters.treatmentLevel != 'all') {
      final label = filters.treatmentLevel == 'council_level'
          ? 'Level: Council'
          : (filters.treatmentLevel == 'full_check_up' ? 'Level: Full Check' : 'Level: ${filters.treatmentLevel}');
      pills.add(_buildFilterPill(label, () {
        vm.setTreatmentLevelFilter(null);
      }));
    }

    // Surgery Done
    if (filters.surgeryDone != null && filters.surgeryDone != 'all') {
      pills.add(_buildFilterPill('Surgery: ${filters.surgeryDone == 'yes' ? 'Done' : 'No'}', () {
        vm.updateFilters(filters.copyWith(surgeryDone: 'all', clearSurgeryType: true));
      }));
    }

    // Marital Status
    if (filters.maritalStatus != null && filters.maritalStatus != 'all') {
      pills.add(_buildFilterPill('Status: ${filters.maritalStatus}', () {
        vm.updateFilters(filters.copyWith(maritalStatus: 'all'));
      }));
    }

    // District
    if (filters.district != null && filters.district != 'all' && filters.district!.isNotEmpty) {
      pills.add(_buildFilterPill('Dist: ${filters.district}', () {
        vm.updateFilters(filters.copyWith(district: 'all'));
      }));
    }

    // Municipality
    if (filters.municipality != null && filters.municipality!.isNotEmpty) {
      pills.add(_buildFilterPill('Palika: ${filters.municipality}', () {
        _municipalityFilterController.clear();
        vm.updateFilters(filters.copyWith(clearMunicipality: true));
      }));
    }

    // Province
    if (filters.province != null && filters.province != 'all' && filters.province!.isNotEmpty) {
      pills.add(_buildFilterPill('Province: ${filters.province}', () {
        vm.updateFilters(filters.copyWith(clearProvince: true));
      }));
    }

    return pills;
  }

  Widget _buildFilterPill(String label, VoidCallback onRemove) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1D4ED8),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(1.0),
              child: Icon(Icons.close_rounded, size: 12, color: Color(0xFF1D4ED8)),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the custom age range input row inside the filter panel.
  Widget _buildCustomAgeRangeRow(
    BuildContext context,
    PatientFilterCriteria filters,
    PatientListViewModel vm,
  ) {
    // Check if the current filter is a preset bracket — if so, pre-fill controllers
    final hasPreset = (filters.minAge == null && filters.maxAge == 19) ||
        (filters.minAge == 20 && filters.maxAge == 35) ||
        (filters.minAge == 36 && filters.maxAge == 50) ||
        (filters.minAge == 51 && filters.maxAge == 65) ||
        (filters.minAge == 66 && filters.maxAge == null);
    final hasCustom = (filters.minAge != null || filters.maxAge != null) && !hasPreset;

    // Sync controller text only if the user hasn't typed yet (keep controllers as source-of-truth)
    if (hasCustom) {
      if (_minAgeController.text.isEmpty && filters.minAge != null) {
        _minAgeController.text = filters.minAge.toString();
      }
      if (_maxAgeController.text.isEmpty && filters.maxAge != null) {
        _maxAgeController.text = filters.maxAge.toString();
      }
    } else if (!hasCustom) {
      // Clear if preset or no age filter
      if (_minAgeController.text.isNotEmpty && !hasPreset) _minAgeController.clear();
      if (_maxAgeController.text.isNotEmpty && !hasPreset) _maxAgeController.clear();
    }

    void applyCustomRange() {
      final minVal = int.tryParse(_minAgeController.text.trim());
      final maxVal = int.tryParse(_maxAgeController.text.trim());
      if (minVal == null && maxVal == null) {
        // Both empty → clear age filter
        vm.updateFilters(filters.copyWith(clearMinAge: true, clearMaxAge: true));
        return;
      }
      if (minVal != null && maxVal != null && minVal > maxVal) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Min age cannot be greater than max age.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
      vm.updateFilters(filters.copyWith(
        minAge: minVal,
        maxAge: maxVal,
        clearMinAge: minVal == null,
        clearMaxAge: maxVal == null,
      ));
    }

    return Container(
      decoration: BoxDecoration(
        color: hasCustom ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasCustom ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
          width: hasCustom ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 15,
                      color: hasCustom ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Custom Age Range (कस्टम उमेर)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: hasCustom ? const Color(0xFF166534) : const Color(0xFF334155),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasCustom) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    _minAgeController.clear();
                    _maxAgeController.clear();
                    vm.updateFilters(filters.copyWith(clearMinAge: true, clearMaxAge: true));
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close_rounded, size: 12, color: Color(0xFFDC2626)),
                        SizedBox(width: 2),
                        Text('Reset', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (hasCustom) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Text(
                'Active: ${filters.minAge ?? "0"} to ${filters.maxAge ?? "100+"} years old',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Min Age', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _minAgeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'e.g. 18',
                        suffixText: 'yr',
                        suffixStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.5),
                        ),
                      ),
                      onSubmitted: (_) => applyCustomRange(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(top: 18),
                child: Text('–', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Max Age', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _maxAgeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'e.g. 60',
                        suffixText: 'yr',
                        suffixStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.5),
                        ),
                      ),
                      onSubmitted: (_) => applyCustomRange(),
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
              onPressed: applyCustomRange,
              icon: const Icon(Icons.check_rounded, size: 15, color: Colors.white),
              label: const Text(
                'Apply Age Range (लागू गर्नुहोस्)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 9),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMobileFilterBottomSheet(
    BuildContext context,
    CampState campState,
    PatientListState patientState,
    PatientListViewModel vm,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final currentPatientState = ref.watch(patientListProvider);
            final currentCampState = ref.watch(campStateProvider);
            final currentFilters = currentPatientState.filters;
            final patientCount = currentPatientState.patients.length;

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Drag Handle
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header with Title, Count, Reset All, and Close
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.tune_rounded, size: 20, color: AppTheme.primaryTeal),
                              const SizedBox(width: 8),
                              const Flexible(
                                child: Text(
                                  'Patient Filters (बिरामी फिल्टर)',
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1E293B),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                              if (currentFilters.hasActiveFilters) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryTeal,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${currentFilters.activeFilterCount}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (currentFilters.hasActiveFilters) ...[
                          const SizedBox(width: 4),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.dangerRose,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _clearAllFilters(vm),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.refresh_rounded, size: 13),
                                SizedBox(width: 3),
                                Text(
                                  'Reset',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                          tooltip: 'Close',
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.only(left: 4),
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.pop(bottomSheetContext),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),

                  // Scrollable Filter Sections Body
                  Expanded(
                    child: _buildDedicatedFilterSection(
                      context,
                      currentCampState,
                      currentPatientState,
                      vm,
                      isSidebar: false,
                      hideHeader: true,
                    ),
                  ),

                  // Sticky Bottom Action Bar with "Show X Patients"
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: const Border(
                        top: BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryTeal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: Text(
                            'Show $patientCount ${patientCount == 1 ? "Patient" : "Patients"}',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                          onPressed: () => Navigator.pop(bottomSheetContext),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDedicatedFilterSection(
    BuildContext context,
    CampState campState,
    PatientListState patientState,
    PatientListViewModel vm, {
    bool isSidebar = false,
    bool hideHeader = false,
  }) {
    final filters = patientState.filters;
    // Scope visible camps: Super Admin sees all; Data Takers only see assigned camps
    final currentUser = ref.watch(authStateProvider).currentUser;
    final isSuperAdmin = currentUser?.isSuperAdmin ?? true;
    final rawVisibleCamps = isSuperAdmin
        ? campState.camps
        : campState.camps
            .where((c) =>
                c.isStaffAssigned(currentUser!.id) ||
                currentUser.assignedCampIds.contains(c.id))
            .toList();
    final uniqueCampsMap = <String, CampModel>{};
    for (final c in rawVisibleCamps) {
      uniqueCampsMap[c.id] = c;
    }
    final visibleCamps = uniqueCampsMap.values.toList();

    final allDoctors = <String>{};
    final campDoctorsMap = <String, List<String>>{};
    for (final camp in visibleCamps) {
      final docs = camp.doctorNames.isNotEmpty
          ? camp.doctorNames
          : (camp.doctorName.trim().isNotEmpty ? [camp.doctorName.trim()] : <String>[]);
      campDoctorsMap[camp.id] = docs;
      for (final d in docs) {
        final clean = d.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim();
        if (clean.isNotEmpty) allDoctors.add(clean);
      }
    }
    for (final p in patientState.rawPatients) {
      if (p.primaryDoctorName != null && p.primaryDoctorName!.trim().isNotEmpty) {
        final clean = p.primaryDoctorName!.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim();
        if (clean.isNotEmpty) allDoctors.add(clean);
      }
      for (final doc in p.attendingDoctorNames) {
        final clean = doc.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim();
        if (clean.isNotEmpty) allDoctors.add(clean);
      }
    }
    if (filters.doctor != null && filters.doctor != 'all' && filters.doctor!.trim().isNotEmpty) {
      final clean = filters.doctor!.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim();
      if (clean.isNotEmpty) allDoctors.add(clean);
    }
    final sortedDoctors = allDoctors.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final allNurses = <String>{};
    for (final camp in visibleCamps) {
      for (final n in camp.nurseNames) {
        final clean = NurseProfile.stripPrefixes(n).trim();
        if (clean.isNotEmpty) allNurses.add(clean);
      }
    }
    for (final p in patientState.rawPatients) {
      if (p.primaryNurseName != null && p.primaryNurseName!.trim().isNotEmpty) {
        final clean = NurseProfile.stripPrefixes(p.primaryNurseName!).trim();
        if (clean.isNotEmpty) allNurses.add(clean);
      }
      for (final nurse in p.attendingNurseNames) {
        final clean = NurseProfile.stripPrefixes(nurse).trim();
        if (clean.isNotEmpty) allNurses.add(clean);
      }
    }
    if (filters.nurse != null && filters.nurse != 'all' && filters.nurse!.trim().isNotEmpty) {
      final clean = NurseProfile.stripPrefixes(filters.nurse!).trim();
      if (clean.isNotEmpty) allNurses.add(clean);
    }
    final sortedNurses = allNurses.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // Dynamic Diagnoses: active camp lookups + patient records + current filter (NO hardcoded static defaults)
    final activeDiagnoses = ref.watch(activeDiagnosesProvider);
    final allDiagnoses = <String>{};
    for (final d in activeDiagnoses) {
      if (d.labelEn.trim().isNotEmpty) {
        allDiagnoses.add(d.labelNe.isNotEmpty ? '${d.labelEn} (${d.labelNe})' : d.labelEn);
      }
    }
    // Only if 0 diagnoses exist in Master Data, fallback to any active patient records
    if (allDiagnoses.isEmpty) {
      for (final p in patientState.rawPatients) {
        allDiagnoses.addAll(p.diagnoses.map((d) => d.trim()).where((d) => d.isNotEmpty));
      }
      for (final p in patientState.patients) {
        allDiagnoses.addAll(p.diagnoses.map((d) => d.trim()).where((d) => d.isNotEmpty));
      }
    }
    if (filters.disease != null && filters.disease!.trim().isNotEmpty && filters.disease != 'all') {
      allDiagnoses.add(filters.disease!.trim());
    }
    final sortedDiagnoses = allDiagnoses.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // Dynamic Complaints & Visit Reasons: active master lookups (NO hardcoded static defaults or unconfigured patient scraping)
    final activeChiefComplaints = ref.watch(activeChiefComplaintsProvider);
    final activeVisitReasons = ref.watch(activeVisitReasonsProvider);
    final dynamicComplaintsMap = <String, String>{};

    String formatTitle(String text) {
      if (text.isEmpty) return text;
      return text.split(' ').map((w) {
        if (w.isEmpty) return w;
        return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
      }).join(' ');
    }

    final masterComplaints = activeChiefComplaints.isNotEmpty
        ? activeChiefComplaints
        : activeVisitReasons;

    for (final item in masterComplaints) {
      final key = item.labelEn.trim().isNotEmpty ? item.labelEn.trim() : item.code.trim();
      final titleEn = formatTitle(item.labelEn.trim());
      final label = item.labelNe.isNotEmpty
          ? '$titleEn (${item.labelNe})'
          : titleEn;
      if (key.isNotEmpty && !dynamicComplaintsMap.containsKey(key)) {
        dynamicComplaintsMap[key] = label;
      }
    }

    // Only if 0 complaints exist in master data, fallback to any active patient records
    if (dynamicComplaintsMap.isEmpty) {
      for (final p in patientState.rawPatients) {
        for (final r in p.reasonsForVisit) {
          final cleanR = r.trim();
          if (cleanR.isNotEmpty && !dynamicComplaintsMap.keys.any((k) => k.toLowerCase() == cleanR.toLowerCase())) {
            final normR = cleanR.toLowerCase().replaceAll('_', ' ');
            final label = _clinicalLabelMap[normR] ??
                _clinicalLabelMap[cleanR] ??
                _clinicalLabelMap[normR.replaceAll(' ', '_')] ??
                formatTitle(normR);
            dynamicComplaintsMap[cleanR] = label;
          }
        }
      }
    }

    // Ensure currently selected filter value exists in the map so dropdown doesn't crash
    if (filters.chiefComplaint != null &&
        filters.chiefComplaint!.isNotEmpty &&
        filters.chiefComplaint != 'all' &&
        !dynamicComplaintsMap.containsKey(filters.chiefComplaint)) {
      final normC = filters.chiefComplaint!.toLowerCase().replaceAll('_', ' ');
      final label = _clinicalLabelMap[normC] ??
          _clinicalLabelMap[filters.chiefComplaint] ??
          formatTitle(normC);
      dynamicComplaintsMap[filters.chiefComplaint!] = label;
    }

    return Container(
      color: const Color(0xFFF8FAFC),
      height: isSidebar ? double.infinity : null,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isSidebar ? 12 : 16,
          vertical: 12,
        ),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Filter Header & Reset Action
            if (!hideHeader) ...[
              Row(
                children: [
                  const Icon(
                    Icons.tune,
                    size: 18,
                    color: AppTheme.primaryTeal,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Dedicated Patient Filters (बिरामी फिल्टर)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: AppTheme.textPrimaryLight,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (filters.hasActiveFilters)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.dangerRose,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.refresh, size: 13),
                      label: const Text(
                        'Reset All',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () => _clearAllFilters(vm),
                    ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppTheme.textSecondaryLight,
                    ),
                    tooltip: 'Close Filter Panel',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _showFilterPanel = false),
                  ),
                ],
              ),
              if (filters.hasActiveFilters) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryTeal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_alt, size: 12, color: AppTheme.primaryTeal),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${filters.activeFilterCount} active filter${filters.activeFilterCount == 1 ? "" : "s"} applied',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryTeal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
            ],

            // SECTION 1: Demographic & Patient Filters
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.badge_outlined,
                          size: 16,
                          color: AppTheme.primaryTeal,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Demographic & Patient Filters (जनसांख्यिकी तथा बिरामी विवरण)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              color: AppTheme.primaryDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Camp & Province Row
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 550;
                        final activeCamp = ref.watch(userActiveCampProvider) ??
                            campState.activeCamp ??
                            (campState.camps.isNotEmpty ? campState.camps.first : null);
                        final defaultCampId = activeCamp?.id ??
                            (visibleCamps.isNotEmpty ? visibleCamps.first.id : 'all');
                        final isCampValid = filters.campId == 'all' ||
                            (filters.campId != null &&
                                visibleCamps.any((c) => c.id == filters.campId));
                        final safeCampValue = filters.campId == 'all'
                            ? 'all'
                            : (isCampValid
                                ? filters.campId!
                                : (visibleCamps.any((c) => c.id == defaultCampId)
                                    ? defaultCampId
                                    : (visibleCamps.isNotEmpty ? visibleCamps.first.id : 'all')));

                        if (!isCampValid &&
                            filters.campId != null &&
                            filters.campId != 'all') {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              vm.updateFilters(filters.copyWith(campId: 'all'));
                            }
                          });
                        }

                        final campDropdown = DropdownButtonFormField<String>(
                          key: ValueKey('camp_dropdown_$safeCampValue'),
                          initialValue: safeCampValue,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Camp (स्वास्थ्य शिविर)',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Text('All Camps (सबै क्याम्पहरू)'),
                            ),
                            ...visibleCamps.map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(
                                  '${c.name} (${c.campCode})${c.status == CampStatus.closed ? " [Closed]" : ""}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            vm.updateFilters(filters.copyWith(campId: val));
                            final campScope = (val != null && val != 'all') ? val : null;
                            ref.read(masterLookupProvider.notifier).setCampScope(campScope);
                            if (val != null && val != 'all') {
                              vm.loadPatients(val);
                            } else {
                              vm.loadPatients('all');
                            }
                          },
                        );

                        final provinceDropdown =
                            DropdownButtonFormField<String>(
                              key: ValueKey(
                                'province_dropdown_${filters.province}',
                              ),
                              initialValue: filters.province ?? 'all',
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Province (प्रदेश)',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: 'all',
                                  child: Text('All Provinces (सबै)'),
                                ),
                                ...ClinicalConstants.nepalProvinces.map(
                                  (p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p),
                                  ),
                                ),
                              ],
                              onChanged: (val) => vm.updateFilters(
                                filters.copyWith(province: val),
                              ),
                            );

                        if (isWide) {
                          return Row(
                            children: [
                              Expanded(flex: 3, child: campDropdown),
                              const SizedBox(width: 8),
                              Expanded(flex: 2, child: provinceDropdown),
                            ],
                          );
                        } else {
                          return Column(
                            children: [
                              campDropdown,
                              const SizedBox(height: 8),
                              provinceDropdown,
                            ],
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 8),

                    // District Dropdown — cascades from Province
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 450;
                        final availableDistricts = NepalGeodata.districtsFor(
                          filters.province == 'all' ? null : filters.province,
                        );
                        final currentDistrict = availableDistricts.contains(filters.district)
                            ? filters.district
                            : null;

                        final districtDropdown = DropdownButtonFormField<String?>(
                          key: ValueKey('district_filter_${filters.district}'),
                          initialValue: currentDistrict,
                          decoration: const InputDecoration(
                            labelText: 'District (जिल्ला)',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All Districts', style: TextStyle(fontSize: 13, color: Colors.grey))),
                            ...availableDistricts.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13)))),
                          ],
                          onChanged: (val) => vm.updateFilters(
                            filters.copyWith(district: val, clearDistrict: val == null),
                          ),
                        );

                        final availablePalikas = NepalGeodata.palikasFor(
                          currentDistrict,
                          extraPalikas: (patientState.rawPatients.isNotEmpty ? patientState.rawPatients : patientState.patients)
                              .map((p) => p.municipality.trim())
                              .where((m) => m.isNotEmpty)
                              .toList(),
                        );
                        final currentPalika = (filters.municipality?.isNotEmpty == true && availablePalikas.contains(filters.municipality))
                            ? filters.municipality
                            : null;

                        final palikaDropdown = DropdownButtonFormField<String?>(
                          key: ValueKey('palika_filter_${filters.municipality}'),
                          initialValue: currentPalika,
                          decoration: const InputDecoration(
                            labelText: 'Palika / Municipality (पालिका)',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All Palikas (सबै)', style: TextStyle(fontSize: 13, color: Colors.grey))),
                            ...availablePalikas.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13)))),
                          ],
                          onChanged: (val) => vm.updateFilters(
                            filters.copyWith(municipality: val, clearMunicipality: val == null),
                          ),
                        );

                        if (isNarrow) {
                          return Column(
                            children: [
                              districtDropdown,
                              const SizedBox(height: 8),
                              palikaDropdown,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: districtDropdown),
                            const SizedBox(width: 8),
                            Expanded(child: palikaDropdown),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),

                    // Row 3: Age Range & Marital Status Dropdowns
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 450;
                        String currentAgeBracket = 'all';
                        if (filters.minAge == null && filters.maxAge == 19) {
                          currentAgeBracket = '<20';
                        } else if (filters.minAge == 20 && filters.maxAge == 35) {
                          currentAgeBracket = '20-35';
                        } else if (filters.minAge == 36 && filters.maxAge == 50) {
                          currentAgeBracket = '36-50';
                        } else if (filters.minAge == 51 && filters.maxAge == 65) {
                          currentAgeBracket = '51-65';
                        } else if (filters.minAge == 66 && filters.maxAge == null) {
                          currentAgeBracket = '>65';
                        } else if (filters.minAge != null || filters.maxAge != null) {
                          currentAgeBracket = 'custom';
                        }

                        final ageDropdown = DropdownButtonFormField<String>(
                          key: ValueKey('age_bracket_$currentAgeBracket'),
                          initialValue: currentAgeBracket,
                          decoration: const InputDecoration(
                            labelText: 'Age Bracket (उमेर समूह)',
                            prefixIcon: Icon(Icons.cake_outlined, size: 18),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: 'all', child: Text('All Ages (सबै उमेर समूह)', style: TextStyle(fontSize: 13))),
                            const DropdownMenuItem(value: '<20', child: Text('Under 20 Years (< 20 वर्ष)', style: TextStyle(fontSize: 13))),
                            const DropdownMenuItem(value: '20-35', child: Text('20 - 35 Years (20 देखि 35 सम्म)', style: TextStyle(fontSize: 13))),
                            const DropdownMenuItem(value: '36-50', child: Text('36 - 50 Years (36 देखि 50 सम्म)', style: TextStyle(fontSize: 13))),
                            const DropdownMenuItem(value: '51-65', child: Text('51 - 65 Years (51 देखि 65 सम्म)', style: TextStyle(fontSize: 13))),
                            const DropdownMenuItem(value: '>65', child: Text('Above 65 Years (> 65 भन्दा माथि)', style: TextStyle(fontSize: 13))),
                            if (currentAgeBracket == 'custom')
                              DropdownMenuItem(
                                value: 'custom',
                                child: Text(
                                  'Custom (${filters.minAge ?? 0} - ${filters.maxAge ?? "∞"} yrs)',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
                                ),
                              ),
                          ],
                          onChanged: (val) {
                            if (val == '<20') {
                              _minAgeController.text = '';
                              _maxAgeController.text = '19';
                              vm.updateFilters(filters.copyWith(maxAge: 19, clearMinAge: true));
                            } else if (val == '20-35') {
                              _minAgeController.text = '20';
                              _maxAgeController.text = '35';
                              vm.updateFilters(filters.copyWith(minAge: 20, maxAge: 35));
                            } else if (val == '36-50') {
                              _minAgeController.text = '36';
                              _maxAgeController.text = '50';
                              vm.updateFilters(filters.copyWith(minAge: 36, maxAge: 50));
                            } else if (val == '51-65') {
                              _minAgeController.text = '51';
                              _maxAgeController.text = '65';
                              vm.updateFilters(filters.copyWith(minAge: 51, maxAge: 65));
                            } else if (val == '>65') {
                              _minAgeController.text = '66';
                              _maxAgeController.text = '';
                              vm.updateFilters(filters.copyWith(minAge: 66, clearMaxAge: true));
                            } else if (val == 'all') {
                              _minAgeController.clear();
                              _maxAgeController.clear();
                              vm.updateFilters(filters.copyWith(clearMinAge: true, clearMaxAge: true));
                            }
                          },
                        );

                        final maritalDropdown = DropdownButtonFormField<String>(
                          key: const ValueKey('marital_status_dropdown'),
                          initialValue: filters.maritalStatus ?? 'all',
                          decoration: const InputDecoration(
                            labelText: 'Marital Status (वैवाहिक स्थिति)',
                            prefixIcon: Icon(Icons.favorite_outline, size: 18),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All Marital Statuses (सबै)', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'married', child: Text('Married (विवाहित)', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'unmarried', child: Text('Unmarried (अविवाहित)', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'widow', child: Text('Widow (एकल/विधवा)', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'divorced', child: Text('Divorced (सम्बन्धविच्छेद)', style: TextStyle(fontSize: 13))),
                          ],
                          onChanged: (val) => vm.updateFilters(filters.copyWith(maritalStatus: val)),
                        );

                        if (isNarrow) {
                          return Column(
                            children: [
                              ageDropdown,
                              const SizedBox(height: 8),
                              maritalDropdown,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: ageDropdown),
                            const SizedBox(width: 8),
                            Expanded(child: maritalDropdown),
                          ],
                        );
                      },
                    ),
                    // Custom Age Range Input Row
                    const SizedBox(height: 8),
                    _buildCustomAgeRangeRow(context, filters, vm),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // SECTION 2: Clinical Intake, Staging & Surgical Filters
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.medical_information_outlined,
                          size: 16,
                          color: AppTheme.primaryTeal,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Clinical Intake & POP Staging Filters (क्लिनिकल तथा प्रोल्याप्स स्टेज)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              color: AppTheme.primaryDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Row 1: Clinical Intake & Doctor / Clinician
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 450;

                        final intakeDropdown = DropdownButtonFormField<String>(
                          key: const ValueKey('clinical_intake_dropdown'),
                          initialValue: filters.clinicalIntake ?? 'all',
                          decoration: const InputDecoration(
                            labelText: 'Clinical Intake Status (क्लिनिकल अवस्था)',
                            prefixIcon: Icon(Icons.how_to_reg_outlined, size: 18),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All Patients (सबै बिरामी)', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'completed', child: Text('Intake Completed (जाँच सम्पन्न)', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'pending', child: Text('Intake Pending (जाँच बाँकी)', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'followup', child: Text('Follow-Up Visit (फलो-अप)', style: TextStyle(fontSize: 13))),
                          ],
                          onChanged: (val) => vm.updateFilters(filters.copyWith(clinicalIntake: val)),
                        );

                        final currentDoctorClean = (filters.doctor != null && filters.doctor != 'all' && filters.doctor!.trim().isNotEmpty)
                            ? filters.doctor!.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim()
                            : null;

                        final doctorDropdown = DropdownButtonFormField<String?>(
                          key: ValueKey('doctor_filter_$currentDoctorClean'),
                          initialValue: sortedDoctors.contains(currentDoctorClean) ? currentDoctorClean : null,
                          decoration: const InputDecoration(
                            labelText: 'Examining Doctor (जाँच गर्ने चिकित्सक)',
                            prefixIcon: Icon(Icons.medical_services_outlined, size: 18),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All Doctors (सबै डाक्टर)', style: TextStyle(fontSize: 13, color: Colors.grey))),
                            ...sortedDoctors.map((doc) => DropdownMenuItem(
                              value: doc,
                              child: Text('Dr. $doc', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                            )),
                          ],
                          onChanged: (val) => vm.updateFilters(
                            filters.copyWith(
                              doctor: val,
                              clearDoctor: val == null,
                              campDoctorsMap: campDoctorsMap,
                            ),
                          ),
                        );

                        if (isNarrow) {
                          return Column(
                            children: [
                              intakeDropdown,
                              const SizedBox(height: 8),
                              doctorDropdown,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: intakeDropdown),
                            const SizedBox(width: 8),
                            Expanded(child: doctorDropdown),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),

                    // Row 1b: Attending Nurse Dropdown
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final currentNurseClean = (filters.nurse != null && filters.nurse != 'all' && filters.nurse!.trim().isNotEmpty)
                            ? NurseProfile.stripPrefixes(filters.nurse!).trim()
                            : null;

                        return DropdownButtonFormField<String?>(
                          key: ValueKey('nurse_filter_$currentNurseClean'),
                          initialValue: sortedNurses.contains(currentNurseClean) ? currentNurseClean : null,
                          decoration: const InputDecoration(
                            labelText: 'Attending Nurse (सेवा दिने नर्स)',
                            prefixIcon: Icon(Icons.person_pin_circle_outlined, size: 18),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All Nurses (सबै नर्स)', style: TextStyle(fontSize: 13, color: Colors.grey))),
                            ...sortedNurses.map((nurse) => DropdownMenuItem(
                              value: nurse,
                              child: Text(nurse, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                            )),
                          ],
                          onChanged: (val) => vm.updateFilters(
                            filters.copyWith(
                              nurse: val,
                              clearNurse: val == null,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),

                    // Row 2: Disease / Diagnosis & POP Stage
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 450;

                        final currentDisease = (filters.disease?.isNotEmpty == true &&
                                sortedDiagnoses.contains(filters.disease))
                            ? filters.disease
                            : null;

                        final diseaseDropdown = DropdownButtonFormField<String?>(
                          key: ValueKey('disease_filter_${filters.disease}'),
                          initialValue: currentDisease,
                          decoration: const InputDecoration(
                            labelText: 'Disease / Diagnosis (रोग / निदान)',
                            prefixIcon: Icon(Icons.healing, size: 18),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          isExpanded: true,
                          items: [
                            DropdownMenuItem(
                              value: null,
                              child: Text(
                                sortedDiagnoses.isEmpty
                                    ? 'No Diagnoses Defined (कुनै निदान छैन)'
                                    : 'All Diagnoses (सबै निदान)',
                                style: const TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                            ),
                            ...sortedDiagnoses.map((d) =>
                              DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))),
                          ],
                          onChanged: (val) => vm.updateFilters(
                            filters.copyWith(disease: val, clearDisease: val == null),
                          ),
                        );

                        final popStageDropdown = DropdownButtonFormField<String>(
                          key: const ValueKey('pop_stage_dropdown'),
                          initialValue: filters.popStage ?? 'all',
                          decoration: const InputDecoration(
                            labelText: 'POP Staging (आङ खस्ने अवस्था)',
                            prefixIcon: Icon(Icons.straighten_outlined, size: 18),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All Stages (सबै स्टेज)', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: '0', child: Text('Stage 0 - Normal (सामान्य)', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: '1', child: Text('Stage I - Mild (हल्का)', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: '2', child: Text('Stage II - Moderate (मध्यम)', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: '3', child: Text('Stage III - Severe (गम्भीर)', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: '4', child: Text('Stage IV - Complete Procidentia (पूर्ण खसेको)', style: TextStyle(fontSize: 13))),
                          ],
                          onChanged: (val) => vm.updateFilters(filters.copyWith(popStage: val)),
                        );

                        if (isNarrow) {
                          return Column(
                            children: [
                              diseaseDropdown,
                              const SizedBox(height: 8),
                              popStageDropdown,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: diseaseDropdown),
                            const SizedBox(width: 8),
                            Expanded(child: popStageDropdown),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),

                    // Row 3: Surgery Performed & Chief Clinical Complaint
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 450;

                        final surgeryDoneDropdown = DropdownButtonFormField<String>(
                          key: const ValueKey('surgery_done_dropdown'),
                          initialValue: filters.surgeryDone ?? 'all',
                          decoration: const InputDecoration(
                            labelText: 'Surgery Performed (शल्यक्रिया भएको)',
                            prefixIcon: Icon(Icons.medical_services_outlined, size: 18),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All / Any (सबै)', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'yes', child: Text('Surgery Done (शल्यक्रिया भएको)', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'no', child: Text('No Surgery (नभएको)', style: TextStyle(fontSize: 13))),
                          ],
                          onChanged: (val) => vm.updateFilters(
                            filters.copyWith(
                              surgeryDone: val,
                              clearSurgeryType: val != 'yes',
                            ),
                          ),
                        );

                        final selectedComplaint = (filters.chiefComplaint?.isNotEmpty == true &&
                                dynamicComplaintsMap.containsKey(filters.chiefComplaint))
                            ? filters.chiefComplaint!
                            : 'all';

                        final chiefComplaintDropdown = DropdownButtonFormField<String>(
                          key: ValueKey('chief_complaint_$selectedComplaint'),
                          initialValue: selectedComplaint,
                          decoration: const InputDecoration(
                            labelText: 'Chief Clinical Complaint (मुख्य समस्या)',
                            prefixIcon: Icon(Icons.report_problem_outlined, size: 18),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          isExpanded: true,
                          items: [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text(
                                dynamicComplaintsMap.isEmpty
                                    ? 'No Complaints Defined (कुनै समस्या छैन)'
                                    : 'All Complaints (सबै मुख्य समस्या)',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: dynamicComplaintsMap.isEmpty ? Colors.grey : null,
                                ),
                              ),
                            ),
                            ...dynamicComplaintsMap.entries.map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    e.value,
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )),
                          ],
                          onChanged: (val) => vm.updateFilters(
                            filters.copyWith(
                              chiefComplaint: val == 'all' ? '' : val,
                              clearChiefComplaint: val == 'all' || val == null || val.isEmpty,
                            ),
                          ),
                        );

                        if (isNarrow) {
                          return Column(
                            children: [
                              surgeryDoneDropdown,
                              const SizedBox(height: 8),
                              chiefComplaintDropdown,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: surgeryDoneDropdown),
                            const SizedBox(width: 8),
                            Expanded(child: chiefComplaintDropdown),
                          ],
                        );
                      },
                    ),

                    // If Surgery Done is Yes, show Surgical Route Dropdown
                    if (filters.surgeryDone == 'yes') ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        key: ValueKey('surgery_type_dropdown_${filters.surgeryType}'),
                        initialValue: (filters.surgeryType != null &&
                                ClinicalConstants.surgeryTypes.contains(filters.surgeryType))
                            ? filters.surgeryType
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Surgical Route (शल्यक्रियाको प्रकार/मार्ग)',
                          prefixIcon: Icon(Icons.route_outlined, size: 18),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          isDense: true,
                        ),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All Surgical Routes (सबै प्रकार)', style: TextStyle(fontSize: 13, color: Colors.grey))),
                          ...ClinicalConstants.surgeryTypes.map((type) =>
                            DropdownMenuItem(value: type, child: Text(type, style: const TextStyle(fontSize: 13)))),
                        ],
                        onChanged: (val) => vm.updateFilters(
                          filters.copyWith(
                            surgeryType: val,
                            clearSurgeryType: val == null,
                          ),
                        ),
                      ),
                    ],

                    // Row 4: Level of Treatment Filter
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey('treatment_level_dropdown_${filters.treatmentLevel}'),
                      initialValue: filters.treatmentLevel ?? 'all',
                      decoration: const InputDecoration(
                        labelText: 'Level of Treatment (उपचारको तह)',
                        prefixIcon: Icon(Icons.layers_outlined, size: 18),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                      ),
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All Treatment Levels (सबै तह)', style: TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: 'council_level',
                          child: Text('Council level (काउन्सिलिङ तह)', style: TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: 'full_check_up',
                          child: Text('Full check up (पूर्ण जाँच)', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                      onChanged: (val) => vm.setTreatmentLevelFilter(val),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    String? campId,
    PatientListViewModel vm,
  ) {
    final isSearching = _searchController.text.isNotEmpty;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Gradient icon container
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF30026E), Color(0xFF81005D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.brandPurple.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                isSearching ? Icons.search_off_rounded : Icons.people_alt_rounded,
                size: 42,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isSearching ? 'No Results Found' : 'No Patients Registered',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isSearching
                  ? 'No patient matched "${_searchController.text}".\nTry a different ID, name, or phone number.'
                  : 'Start registering patients at this camp station\nusing the New Patient button.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondaryLight,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            if (!isSearching)
              ElevatedButton.icon(
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: const Text(
                  'Register Patient Now',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brandPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PatientRegistrationView(),
                    ),
                  );
                  if (mounted) {
                    _reloadCurrentList(vm);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: const Row(
        children: [
          Expanded(
            flex: 15,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.badge_outlined, size: 13, color: Color(0xFF64748B)),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'PATIENT ID',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF475569),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            flex: 22,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline_rounded, size: 13, color: Color(0xFF64748B)),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'PATIENT NAME & DETAILS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF475569),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            flex: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline_rounded, size: 13, color: Color(0xFF64748B)),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'HUSBAND / FATHER',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF475569),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            flex: 17,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on_outlined, size: 13, color: Color(0xFF64748B)),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'LOCATION & WARD',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF475569),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            flex: 18,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timeline_rounded, size: 13, color: Color(0xFF64748B)),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'ENCOUNTER STATUS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF475569),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            flex: 28,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app_outlined, size: 13, color: Color(0xFF64748B)),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'ACTIONS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF475569),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow({
    required BuildContext context,
    required PatientModel patient,
    required CampModel? activeCamp,
    required PatientListViewModel vm,
    required CampState campState,
    required bool isEven,
  }) {
    // CAMP LOCK CHECK: check if this patient's specific camp is closed/archived
    // EXCEPTION: Super Admin can always access and edit regardless of camp status.
    CampModel? patientCamp;
    try {
      patientCamp = campState.camps.firstWhere((c) => c.id == patient.campId);
    } catch (_) {}
    final listUser = ref.read(authStateProvider).currentUser;
    final isSuperAdminUser = listUser?.role == UserRole.superAdmin;
    final isCampPhysicallyClosed = patientCamp != null && patientCamp.status.isLocked;
    final isCampLocked = isCampPhysicallyClosed && !isSuperAdminUser;

    // Determine clinical completion status
    final hasReasons = patient.reasonsForVisit.isNotEmpty;
    final hasPhone = patient.mobile.isNotEmpty;
    final hasClinical = patient.hasClinicalVisit;

    // Status colors: Emerald = Clinical completed, Teal/Purple = Registered, Amber = Intake Pending
    final Color statusColor = hasClinical
        ? const Color(0xFF10B981)
        : hasReasons
            ? AppTheme.brandPurple
            : const Color(0xFFF59E0B);

    // Format guardian info gracefully — never print empty "Father: "
    final guardianName = patient.spouseOrFatherName?.trim() ?? '';
    final hasGuardian = guardianName.isNotEmpty && guardianName.toLowerCase() != 'null';
    final isFather = patient.maritalStatus == 'unmarried' || patient.age < 20;
    final familyLabel = isFather ? "Father's Name" : "Husband's Name";
    final relType = patient.relationshipType?.trim() ?? 'Guardian';

    final maritalStr = patient.maritalStatus.isNotEmpty ? patient.maritalStatus : 'N/A';

    // Resolve location
    final locationParts = <String>[];
    if (patient.municipality.isNotEmpty) locationParts.add(patient.municipality);
    if (patient.district.isNotEmpty) locationParts.add(patient.district);
    final locationStr = locationParts.isNotEmpty ? locationParts.join(', ') : 'Nepal';

    // ── Column 1: Patient ID Badge ──
    final tokenIdBadge = InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: patient.patientId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text('Copied ID: ${patient.patientId}'),
              ],
            ),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F3FF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE9D5FF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  patient.patientId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11.5,
                    color: AppTheme.brandPurple,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.copy_rounded, size: 12, color: AppTheme.brandPurple),
          ],
        ),
      ),
    );

    final campLockedBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFF87171)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: 10, color: Color(0xFFDC2626)),
          SizedBox(width: 3),
          Text(
            'Camp Closed',
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
          ),
        ],
      ),
    );

    final wardBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Text(
        'Ward ${patient.ward}',
        style: const TextStyle(
          fontSize: 10.5,
          color: Color(0xFF334155),
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final statusPill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: hasClinical
            ? const Color(0xFFECFDF5)
            : hasReasons
                ? const Color(0xFFEFF6FF)
                : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: hasClinical
              ? const Color(0xFFA7F3D0)
              : hasReasons
                  ? const Color(0xFFBFDBFE)
                  : const Color(0xFFFDE68A),
        ),
      ),
      child: Text(
        hasClinical
            ? 'CLINICAL COMPLETED'
            : hasReasons
                ? 'REGISTERED'
                : 'INTAKE PENDING',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: hasClinical
              ? const Color(0xFF047857)
              : hasReasons
                  ? const Color(0xFF1D4ED8)
                  : const Color(0xFFB45309),
        ),
      ),
    );

    final chartCue = InkWell(
      onTap: () => _showClinicalHistoryPanel(context, patient, activeCamp),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: AppTheme.primaryTeal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.25)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_edu_rounded, size: 11, color: AppTheme.primaryTeal),
            SizedBox(width: 3),
            Text(
              'Chart →',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryDark,
              ),
            ),
          ],
        ),
      ),
    );

    // Primary CTA Button
    final primaryCta = !hasClinical
        ? ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brandPurple,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
            ),
            icon: const Icon(Icons.assignment_rounded, size: 14),
            label: const Text('Clinical Intake', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ClinicalAssessmentView(patient: patient)),
              );
              if (mounted) {
                _reloadCurrentList(vm);
              }
            },
          )
        : ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brandMagenta,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
            ),
            icon: const Icon(Icons.replay_rounded, size: 14),
            label: const Text('Follow-Up', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
            onPressed: () async {
              final updated = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PatientFollowUpFormView(patient: patient, camp: activeCamp),
                ),
              );
              if (updated == true && mounted) {
                _reloadCurrentList(vm);
              }
            },
          );

    final slipBtn = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF334155),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
      icon: const Icon(Icons.qr_code_2_rounded, size: 14, color: AppTheme.brandPurple),
      label: const Text('Slip / QR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      onPressed: () async {
        final proceed = await PatientFollowUpSlipModal.show(
          context,
          patient: patient,
          camp: activeCamp,
          organizationName: (activeCamp?.organizationName.isNotEmpty == true &&
                  !AppConstants.isLegacyDefaultOrganization(activeCamp!.organizationName))
              ? activeCamp.organizationName
              : ref.read(effectiveOrganizationProvider),
          showProceedButton: true,
        );
        if (proceed == true) {
          if (!context.mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ClinicalAssessmentView(patient: patient),
            ),
          );
          if (!context.mounted) return;
          _reloadCurrentList(vm);
        }
      },
    );

    PopupMenuEntry<String> buildMenuHeader(String label) {
      return PopupMenuItem<String>(
        enabled: false,
        height: 24,
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF94A3B8),
            letterSpacing: 0.8,
          ),
        ),
      );
    }

    PopupMenuEntry<String> buildMenuItem({
      required String value,
      required IconData icon,
      required Color iconColor,
      required Color iconBg,
      required String title,
      required String subtitle,
    }) {
      return PopupMenuItem<String>(
        value: value,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 17, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final moreMenu = PopupMenuButton<String>(
      tooltip: 'Patient Options & Records',
      elevation: 6,
      shadowColor: const Color(0x20000000),
      surfaceTintColor: Colors.white,
      color: Colors.white,
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 320),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
      ),
      icon: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: const Icon(Icons.more_horiz_rounded, size: 16, color: Color(0xFF334155)),
      ),
      onSelected: (action) async {
        switch (action) {
          case 'edit':
            if (isCampLocked) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cannot edit: Camp is closed and locked.')),
              );
              return;
            }
            final updated = await Navigator.push<PatientModel?>(
              context,
              MaterialPageRoute(
                builder: (_) => PatientRegistrationView(patientToEdit: patient),
              ),
            );
            if (context.mounted && updated != null) {
              _reloadCurrentList(vm);
            }
            break;
          case 're_exam':
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ClinicalAssessmentView(patient: patient)),
            );
            if (mounted) {
              _reloadCurrentList(vm);
            }
            break;
          case 'history':
            _showClinicalHistoryPanel(context, patient, activeCamp);
            break;
          case 'pdf_summary':
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Generating ${patient.fullName} health summary PDF...'),
                duration: const Duration(seconds: 1),
              ),
            );
            final visit = await ref
                .read(clinicalAssessmentProvider.notifier)
                .loadPatientAssessment(patient.patientId, patientUuid: patient.id);
            final auth = ref.read(authStateProvider).currentUser;
            final saved = await ref.read(reportingViewModelProvider.notifier).exportIndividualPatientPdf(
                  patient: patient,
                  visit: visit,
                  camp: activeCamp,
                  userId: auth?.id ?? 'usr-data-taker',
                  userName: auth?.name ?? 'Health Worker',
                  userRole: auth?.role.toDbString() ?? 'DATA_TAKER',
                );
            if (context.mounted && saved != null) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Summary PDF downloaded for ${patient.fullName}')),
                    ],
                  ),
                  backgroundColor: AppTheme.successGreen,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            break;
          case 'follow_up_slip':
            await _downloadFollowUpSlip(context, patient, activeCamp);
            break;
        }
      },
      itemBuilder: (ctx) => [
        buildMenuHeader('CLINICAL WORKFLOW'),
        if (hasClinical && !isCampLocked)
          buildMenuItem(
            value: 're_exam',
            icon: Icons.assignment_outlined,
            iconColor: const Color(0xFF2563EB),
            iconBg: const Color(0xFFEFF6FF),
            title: 'Review / Edit Clinical Exam',
            subtitle: 'Station 2–6 examination & staging',
          ),
        buildMenuItem(
          value: 'history',
          icon: Icons.history_edu_rounded,
          iconColor: AppTheme.brandPurple,
          iconBg: AppTheme.brandPurpleLight,
          title: 'Clinical History & Dossier',
          subtitle: 'Encounter timeline, vitals & chart',
        ),
        const PopupMenuDivider(height: 10),
        buildMenuHeader('PATIENT ADMINISTRATION'),
        if (!isCampLocked)
          buildMenuItem(
            value: 'edit',
            icon: Icons.edit_note_rounded,
            iconColor: AppTheme.brandPurple,
            iconBg: AppTheme.brandPurpleLight,
            title: 'Edit Registration (Page 1)',
            subtitle: 'Demographics, address & consent',
          ),
        const PopupMenuDivider(height: 10),
        buildMenuHeader('EXPORTS & PRINTS'),
        buildMenuItem(
          value: 'pdf_summary',
          icon: Icons.picture_as_pdf_rounded,
          iconColor: const Color(0xFFE11D48),
          iconBg: const Color(0xFFFFF1F2),
          title: 'Health Summary (PDF)',
          subtitle: 'Complete medical report export',
        ),
        buildMenuItem(
          value: 'follow_up_slip',
          icon: Icons.receipt_long_rounded,
          iconColor: const Color(0xFF0284C7),
          iconBg: const Color(0xFFF0F9FF),
          title: 'Follow-Up Slip (PDF)',
          subtitle: 'Patient visit slip & barcode',
        ),
      ],
    );

    return Material(
      color: isEven ? Colors.white : const Color(0xFFFBFDFF),
      child: InkWell(
        onTap: () => _showClinicalHistoryPanel(context, patient, activeCamp),
        hoverColor: const Color(0xFFF1F5F9).withValues(alpha: 0.6),
        splashColor: AppTheme.primaryTeal.withValues(alpha: 0.05),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: statusColor, width: 3.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Col 1: PATIENT ID (flex: 15)
              Expanded(
                flex: 15,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    tokenIdBadge,
                    const SizedBox(height: 4),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shield_outlined, size: 10.5, color: Color(0xFF94A3B8)),
                        SizedBox(width: 3.5),
                        Text(
                          'Encrypted',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (isCampLocked) ...[
                      const SizedBox(height: 3),
                      campLockedBadge,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Col 2: PATIENT NAME & DETAILS (flex: 22)
              Expanded(
                flex: 22,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      patient.fullName,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3.5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 3.5,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Age ${patient.age}y',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                          ),
                        ),
                        if (maritalStr != 'N/A')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              maritalStr,
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: Color(0xFF475569)),
                            ),
                          ),
                        if (patient.isCouncilLevel)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.35)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.record_voice_over_rounded, size: 10, color: Color(0xFF7C3AED)),
                                SizedBox(width: 3),
                                Text(
                                  'Council Level (काउन्सिलिङ)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF7C3AED),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (patient.isFullCheckUp)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.35)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.medical_services_rounded, size: 10, color: Color(0xFF0D9488)),
                                SizedBox(width: 3),
                                Text(
                                  'Full Check Up (पूर्ण जाँच)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0D9488),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (hasPhone) ...[
                      const SizedBox(height: 3.5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.phone_outlined, size: 11, color: Color(0xFF64748B)),
                          const SizedBox(width: 3),
                          Text(
                            patient.mobile,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Col 3: HUSBAND / FATHER (flex: 16)
              Expanded(
                flex: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isFather ? Icons.escalator_warning_outlined : Icons.people_outline,
                          size: 11.5,
                          color: const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 3.5),
                        Text(
                          familyLabel.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasGuardian ? guardianName : '—',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: hasGuardian ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasGuardian &&
                        relType.isNotEmpty &&
                        relType.toLowerCase() != 'null' &&
                        relType.toLowerCase() != 'husband' &&
                        relType.toLowerCase() != 'father') ...[
                      const SizedBox(height: 2),
                      Text(
                        '($relType)',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Col 4: LOCATION & WARD (flex: 17)
              Expanded(
                flex: 17,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    wardBadge,
                    const SizedBox(height: 3.5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on_outlined, size: 11.5, color: Color(0xFF64748B)),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            locationStr,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Col 5: ENCOUNTER STATUS (flex: 18)
              Expanded(
                flex: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    statusPill,
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildCompactStageDot('S1', done: true),
                            _buildCompactStageLine(done: hasClinical),
                            _buildCompactStageDot('S2', done: hasClinical),
                            _buildCompactStageLine(done: hasClinical),
                            _buildCompactStageDot('S3-6', done: hasClinical),
                          ],
                        ),
                        chartCue,
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Col 6: ACTIONS (flex: 28)
              Expanded(
                flex: 28,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      slipBtn,
                      primaryCta,
                      moreMenu,
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

  Widget _buildCompactStageDot(String label, {required bool done}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
      decoration: BoxDecoration(
        color: done ? const Color(0xFF10B981).withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: done ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: done ? const Color(0xFF047857) : const Color(0xFF94A3B8),
        ),
      ),
    );
  }

  Widget _buildCompactStageLine({required bool done}) {
    return Container(
      width: 8,
      height: 1.5,
      color: done ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
    );
  }


    void _showScanTokenDialog(
    BuildContext context,
    String campId,
    PatientListViewModel vm,
    List<PatientModel> existingPatients,
  ) {
    final scanInputController = TextEditingController();
    PatientModel? matchedPatient;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          void checkMatch(String query) {
            final trimmed = query.trim().toUpperCase();
            if (trimmed.isEmpty) {
              setDialogState(() => matchedPatient = null);
              return;
            }
            try {
              final found = existingPatients.firstWhere(
                (p) =>
                    p.patientId.toUpperCase() == trimmed ||
                    p.id == trimmed ||
                    p.mobile == trimmed,
              );
              setDialogState(() => matchedPatient = found);
            } catch (_) {
              setDialogState(() => matchedPatient = null);
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(
                  Icons.qr_code_scanner_rounded,
                  color: AppTheme.primaryTeal,
                  size: 26,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Scan Patient QR / Barcode Token',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hardware Barcode Scanner & USB Wedge Status Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: matchedPatient != null
                              ? [
                                  const Color(0xFF065F46),
                                  const Color(0xFF047857),
                                ]
                              : [
                                  const Color(0xFF0F172A),
                                  const Color(0xFF1E293B),
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: matchedPatient != null
                              ? Colors.greenAccent
                              : AppTheme.primaryTeal.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                matchedPatient != null
                                    ? Icons.check_circle_rounded
                                    : Icons.qr_code_scanner_rounded,
                                color: matchedPatient != null
                                    ? Colors.greenAccent
                                    : AppTheme.primaryTeal,
                                size: 28,
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  matchedPatient != null
                                      ? 'TOKEN MATCHED: ${matchedPatient!.patientId}'
                                      : 'USB / Bluetooth Scanner Gun Ready',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: matchedPatient != null
                                        ? Colors.greenAccent
                                        : Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            matchedPatient != null
                                ? '${matchedPatient!.fullName} • Age: ${matchedPatient!.age} • Ward ${matchedPatient!.ward}'
                                : 'Trigger your physical handheld scanner gun at the patient slip, or tap a token below',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: matchedPatient != null
                                  ? Colors.white
                                  : Colors.white70,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Quick Optical / Camera Trigger Options
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              foregroundColor: AppTheme.primaryTeal,
                              side: const BorderSide(
                                color: AppTheme.primaryTeal,
                              ),
                            ),
                            icon: const Icon(Icons.camera_alt, size: 16),
                            label: const Text(
                              'Open Camera / File',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () async {
                              final docService = DocumentCaptureService();
                              final image = await docService
                                  .captureFromCamera();
                              if (image != null) {
                                final filename = image.name.toLowerCase();
                                PatientModel? matched;
                                for (final p in existingPatients) {
                                  if (filename.contains(
                                        p.patientId.toLowerCase(),
                                      ) ||
                                      filename.contains(
                                        p.patientId
                                            .replaceAll('-', '')
                                            .toLowerCase(),
                                      ) ||
                                      filename.contains(
                                        p.fullName.toLowerCase(),
                                      )) {
                                    matched = p;
                                    break;
                                  }
                                }

                                if (matched != null) {
                                  scanInputController.text = matched.patientId;
                                  checkMatch(matched.patientId);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '✓ Recognized Token from ${image.name}: ${matched.patientId}',
                                        ),
                                        backgroundColor: AppTheme.primaryTeal,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                } else {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Uploaded "${image.name}". No valid QR/Barcode token found in image. Aim your barcode gun at a printed slip or click a token below.',
                                        ),
                                        backgroundColor: Colors.orange.shade800,
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            icon: const Icon(Icons.document_scanner, size: 16),
                            label: const Text(
                              'Yellow Form OCR',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const FormScanView(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Input Field (Auto-focused for Hardware Barcode Scanner Guns)
                    TextField(
                      controller: scanInputController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Scanned Token / Barcode (हार्डवेयर वा क्यामेरा टोकन)',
                        hintText: 'e.g. GC-KTM01-2026-00001',
                        prefixIcon: const Icon(
                          Icons.qr_code,
                          color: AppTheme.primaryTeal,
                        ),
                        suffixIcon: scanInputController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  scanInputController.clear();
                                  setDialogState(() => matchedPatient = null);
                                },
                              )
                            : null,
                      ),
                      onChanged: (val) => checkMatch(val),
                      onSubmitted: (scanned) {
                        checkMatch(scanned);
                        if (matchedPatient != null) {
                          Navigator.of(ctx).pop();
                          _searchController.text = matchedPatient!.patientId;
                          vm.search(campId, matchedPatient!.patientId);
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Instant Matched Patient Card
                    if (matchedPatient != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.primaryTeal),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppTheme.primaryTeal,
                                  child: Text(
                                    matchedPatient!.fullName.isNotEmpty
                                        ? matchedPatient!.fullName[0]
                                        : 'P',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        matchedPatient!.fullName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        'Age: ${matchedPatient!.age}y • Ward ${matchedPatient!.ward} • ${matchedPatient!.mobile.isNotEmpty ? matchedPatient!.mobile : "No Phone"}',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppTheme.textSecondaryLight,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryTeal,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      minimumSize: Size.zero,
                                    ),
                                    icon: const Icon(
                                      Icons.medical_services,
                                      size: 15,
                                    ),
                                    label: const Text(
                                      'Start Clinical Intake',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.of(ctx).pop();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ClinicalAssessmentView(
                                                patient: matchedPatient!,
                                              ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    minimumSize: Size.zero,
                                  ),
                                  icon: const Icon(
                                    Icons.print_outlined,
                                    size: 15,
                                  ),
                                  label: const Text(
                                    'Slip',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    PatientFollowUpSlipModal.show(
                                      context,
                                      patient: matchedPatient!,
                                      camp: ref
                                          .read(campStateProvider)
                                          .activeCamp,
                                      organizationName: ref.read(effectiveOrganizationProvider),
                                      showProceedButton: false,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Quick-Tap Registered Test Tokens
                    if (existingPatients.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Registered Tokens in Active Camp:',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: existingPatients
                            .take(5)
                            .map(
                              (p) => ActionChip(
                                avatar: const Icon(
                                  Icons.qr_code_2,
                                  size: 14,
                                  color: AppTheme.primaryTeal,
                                ),
                                label: Text(
                                  '${p.fullName} (${p.patientId})',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor:
                                    scanInputController.text == p.patientId
                                    ? AppTheme.primaryTeal.withValues(
                                        alpha: 0.2,
                                      )
                                    : AppTheme.primaryTeal.withValues(
                                        alpha: 0.08,
                                      ),
                                onPressed: () {
                                  scanInputController.text = p.patientId;
                                  checkMatch(p.patientId);
                                },
                              ),
                            )
                            .toList(),
                      ),
                    ] else ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Colors.amber,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No patients registered yet. Tap "+ New Patient" to register and generate a QR token first.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF92400E),
                                ),
                              ),
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
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.filter_list, size: 16),
                label: const Text('Filter in List'),
                onPressed: () {
                  final scanned = scanInputController.text.trim();
                  if (scanned.isNotEmpty) {
                    Navigator.of(ctx).pop();
                    _searchController.text = scanned;
                    vm.search(campId, scanned);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Download Follow-Up Encounter Slip PDF ────────────────────────────────
  Future<void> _downloadFollowUpSlip(
    BuildContext context,
    PatientModel patient,
    CampModel? camp,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Generating follow-up slip for ${patient.fullName}...'),
          duration: const Duration(seconds: 2),
        ),
      );
      final visit = await ref
          .read(clinicalAssessmentProvider.notifier)
          .loadPatientAssessment(patient.patientId, patientUuid: patient.id);

      final effectiveOrg = ref.read(effectiveOrganizationProvider);
      final orgName = (camp?.organizationName.isNotEmpty == true &&
              !AppConstants.isLegacyDefaultOrganization(camp!.organizationName))
          ? camp.organizationName
          : effectiveOrg;

      final Uint8List bytes;
      if (visit != null) {
        bytes = await PdfReportService().generateFollowUpEncounterSlipPdf(
          patient: patient,
          visit: visit,
          camp: camp,
          organizationName: orgName,
        );
      } else {
        bytes = await PdfReportService().generateBlankFollowUpSlipPdf(
          camp: camp,
          organizationName: orgName,
        );
      }

      final result = await FileDownloadHelper.saveAndDownloadFile(
        bytes: bytes,
        filename: 'FollowUpSlip_${patient.patientId}.pdf',
        mimeType: 'application/pdf',
        autoOpen: true,
      );

      if (context.mounted) {
        FileDownloadHelper.showDownloadFeedback(context, result, forceForegroundModal: true);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to download follow-up slip: $e'),
          backgroundColor: AppTheme.dangerRose,
        ),
      );
    }
  }

  // ─── Professional Clinical History Full-Screen Panel ────────────────────────
  void _showClinicalHistoryPanel(
    BuildContext context,
    PatientModel patient,
    CampModel? camp,
  ) {
    final repo = ref.read(patientRepositoryProvider);
    final effectiveOrg = ref.read(effectiveOrganizationProvider);
    final orgName = (camp?.organizationName.isNotEmpty == true &&
            !AppConstants.isLegacyDefaultOrganization(camp!.organizationName))
        ? camp.organizationName
        : effectiveOrg;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close History',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 320),
      transitionBuilder: (ctx, anim, secondAnim, child) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        );
      },
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              top: true,
              bottom: true,
              child: Container(
                width: MediaQuery.of(context).size.width >= 700
                    ? MediaQuery.of(context).size.width * 0.88
                    : MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 24,
                      offset: Offset(-4, 0),
                    ),
                  ],
                ),
                child: ClinicalHistoryPanel(
                  patient: patient,
                  camp: camp,
                  orgName: orgName,
                  repo: repo,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}


