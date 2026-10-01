import 'dart:math' as math;
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
      final targetCampId = widget.campId ?? ref.read(userActiveCampProvider)?.id;
      final currentFilters = ref.read(patientListProvider).filters;
      if (currentFilters.campId == null && targetCampId != null) {
        ref.read(patientListProvider.notifier).updateFilters(
          currentFilters.copyWith(campId: targetCampId),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    final campState = ref.watch(campStateProvider);
    final patientState = ref.watch(patientListProvider);
    final vm = ref.read(patientListProvider.notifier);
    // Use user-scoped camp so staff see their assigned camp, not the global one
    final activeCamp = ref.watch(userActiveCampProvider);
    final effectiveCamp = widget.campId != null
        ? campState.camps.cast<CampModel?>().firstWhere(
              (c) => c?.id == widget.campId,
              orElse: () => activeCamp,
            )
        : activeCamp;
    final effectiveCampId = effectiveCamp?.id;

    // Only auto-switch patient roll on activeCamp change if not explicitly bound to a campId
    if (widget.campId == null) {
      ref.listen<CampModel?>(userActiveCampProvider, (previous, next) {
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
        if (effectiveCampId != null) {
          if (_searchController.text.trim().isNotEmpty) {
            ref.read(patientListProvider.notifier).search(effectiveCampId, _searchController.text.trim());
          } else {
            ref.read(patientListProvider.notifier).loadPatients(effectiveCampId);
          }
        }
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
                  onTap: effectiveCampId == null
                      ? null
                      : () => vm.loadPatients(effectiveCampId),
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
        backgroundColor: effectiveCamp == null ? Colors.grey.shade400 : const Color(0xFF81005D),
        elevation: 4,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text(
          'New Patient',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        onPressed: effectiveCamp == null
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
                if (mounted && effectiveCampId != null) {
                  vm.loadPatients(effectiveCampId);
                }
              },
      ),
      body: effectiveCamp == null
          ? const Center(
              child: Text(
                'No active camp selected. Please activate a camp first.',
              ),
            )          : LayoutBuilder(
              builder: (context, viewportConstraints) {
                final isDesktop = viewportConstraints.maxWidth >= 900;

                if (isDesktop) {
                  return Column(
                    children: [
                      // Full-width Header Toolbar with Edge Padding (No artificial maxWidth cage)
                      _buildSearchAndActionHeader(
                        effectiveCampId: effectiveCampId,
                        patientState: patientState,
                        vm: vm,
                        isWide: true,
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
                                effectiveCamp,
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
                      patientState: patientState,
                      vm: vm,
                      isWide: viewportConstraints.maxWidth >= 700,
                    ),

                    // Dedicated Filter Section (Collapsible with safe bounded height)
                    if (_showFilterPanel) ...[
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: math.min(
                            viewportConstraints.maxHeight * 0.45,
                            300.0,
                          ),
                        ),
                        child: _buildDedicatedFilterSection(
                          context,
                          campState,
                          patientState,
                          vm,
                          isSidebar: false,
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    ],

                    // Patient Roll Statistics Bar
                    _buildStatisticsBar(patientState, vm, isWide: false),

                    // Patient Cards List
                    Expanded(
                      child: _buildPatientCardsList(
                        effectiveCampId,
                        effectiveCamp,
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
    required PatientListState patientState,
    required PatientListViewModel vm,
    required bool isWide,
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
                  vm.search(effectiveCampId, '');
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
      onChanged: (val) => vm.search(effectiveCampId, val),
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
        _showFilterPanel ? Icons.filter_alt_off_rounded : Icons.filter_alt_rounded,
        size: 17,
      ),
      label: Text(
        patientState.filters.hasActiveFilters
            ? 'Filters (${patientState.filters.activeFilterCount})'
            : 'Filters',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      onPressed: () {
        setState(() => _showFilterPanel = !_showFilterPanel);
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
      onPressed: effectiveCampId == null
          ? null
          : () => _showScanTokenDialog(
              context,
              effectiveCampId,
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
          targetCamp = campState.camps.firstWhere((c) => c.id == effectiveCampId);
        } catch (_) {
          targetCamp = campState.activeCamp;
        }
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
                  if (effectiveCampId != null) {
                    await vm.loadPatients(effectiveCampId);
                  }
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth = constraints.maxWidth;
                    // Multi-column responsive layout logic:
                    // 3 columns if available width >= 1450 (ultra-wide desktop without sidebar)
                    // 2 columns if available width >= 800 (standard desktop & wide tablets)
                    // 1 column if available width < 800 (mobile & narrow viewports)
                    final int columnCount;
                    if (availableWidth >= 1450) {
                      columnCount = 3;
                    } else if (availableWidth >= 800) {
                      columnCount = 2;
                    } else {
                      columnCount = 1;
                    }

                    final double horizontalPadding = availableWidth >= 900 ? 24.0 : 16.0;

                    if (columnCount == 1) {
                      return ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                          vertical: 14,
                        ),
                        itemCount: patientState.patients.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final patient = patientState.patients[index];
                          return _buildPatientCard(
                            context,
                            patient,
                            effectiveCamp,
                            vm,
                            campState,
                          );
                        },
                      );
                    }

                    // Multi-column responsive masonry-style side-by-side columns
                    const double colSpacing = 16.0;
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 14,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List.generate(columnCount, (colIndex) {
                          final columnPatients = [
                            for (int i = colIndex; i < patientState.patients.length; i += columnCount)
                              patientState.patients[i]
                          ];
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: colIndex == 0 ? 0 : colSpacing / 2,
                                right: colIndex == columnCount - 1 ? 0 : colSpacing / 2,
                              ),
                              child: Column(
                                children: columnPatients.map((patient) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: _buildPatientCard(
                                      context,
                                      patient,
                                      effectiveCamp,
                                      vm,
                                      campState,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          );
                        }),
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

    // Clinical Intake
    if (filters.clinicalIntake != null && filters.clinicalIntake != 'all') {
      pills.add(_buildFilterPill('Intake: ${filters.clinicalIntake}', () {
        vm.updateFilters(filters.copyWith(clinicalIntake: 'all'));
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

  Widget _buildDedicatedFilterSection(
    BuildContext context,
    CampState campState,
    PatientListState patientState,
    PatientListViewModel vm, {
    bool isSidebar = false,
  }) {
    final filters = patientState.filters;
    // Scope visible camps: Super Admin sees all; Data Takers only see assigned camps
    final currentUser = ref.watch(authStateProvider).currentUser;
    final visibleCamps = (currentUser?.isSuperAdmin ?? true)
        ? campState.camps
        : campState.camps
            .where((c) =>
                c.isStaffAssigned(currentUser!.id) ||
                currentUser.assignedCampIds.contains(c.id))
            .toList();

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

    // Dynamic Diagnoses: active camp lookups + patient records + current filter (NO hardcoded static defaults)
    final activeDiagnoses = ref.watch(activeDiagnosesProvider);
    final allDiagnoses = <String>{};
    for (final d in activeDiagnoses) {
      if (d.labelEn.trim().isNotEmpty) {
        allDiagnoses.add(d.labelNe.isNotEmpty ? '${d.labelEn} (${d.labelNe})' : d.labelEn);
      }
    }
    for (final p in patientState.rawPatients) {
      allDiagnoses.addAll(p.diagnoses.map((d) => d.trim()).where((d) => d.isNotEmpty));
    }
    for (final p in patientState.patients) {
      allDiagnoses.addAll(p.diagnoses.map((d) => d.trim()).where((d) => d.isNotEmpty));
    }
    if (filters.disease != null && filters.disease!.trim().isNotEmpty && filters.disease != 'all') {
      allDiagnoses.add(filters.disease!.trim());
    }
    final sortedDiagnoses = allDiagnoses.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // Dynamic Complaints & Visit Reasons: active master lookups + patient records
    final activeVisitReasons = ref.watch(activeVisitReasonsProvider);
    final activeChiefComplaints = ref.watch(activeChiefComplaintsProvider);
    final dynamicComplaintsMap = <String, String>{};
    for (final item in [...activeVisitReasons, ...activeChiefComplaints]) {
      final key = item.code.trim().isNotEmpty ? item.code.trim() : item.labelEn.trim();
      final label = item.labelNe.isNotEmpty
          ? '${item.labelEn} (${item.labelNe})'
          : item.labelEn;
      if (key.isNotEmpty && !dynamicComplaintsMap.containsKey(key)) {
        dynamicComplaintsMap[key] = label;
      }
    }
    for (final p in patientState.rawPatients) {
      for (final r in p.reasonsForVisit) {
        final cleanR = r.trim();
        if (cleanR.isNotEmpty && !dynamicComplaintsMap.keys.any((k) => k.toLowerCase() == cleanR.toLowerCase())) {
          final normR = cleanR.toLowerCase().replaceAll('_', ' ');
          final label = _clinicalLabelMap[normR] ??
              _clinicalLabelMap[cleanR] ??
              _clinicalLabelMap[normR.replaceAll(' ', '_')] ??
              (normR.contains('hanging') || normR.contains('prolapse') ? 'Prolapse / Something Hanging Out (आङ खस्ने)' : cleanR);
          dynamicComplaintsMap[cleanR] = label;
        }
      }
    }
    if (filters.chiefComplaint != null &&
        filters.chiefComplaint!.isNotEmpty &&
        filters.chiefComplaint != 'all' &&
        !dynamicComplaintsMap.containsKey(filters.chiefComplaint)) {
      final normC = filters.chiefComplaint!.toLowerCase().replaceAll('_', ' ');
      final label = _clinicalLabelMap[normC] ??
          _clinicalLabelMap[filters.chiefComplaint] ??
          filters.chiefComplaint!;
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.tune,
                        size: 18,
                        color: AppTheme.primaryTeal,
                      ),
                      const SizedBox(width: 8),
                      const Flexible(
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
                      if (filters.hasActiveFilters) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryTeal,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${filters.activeFilterCount} Active',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (filters.hasActiveFilters)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.dangerRose,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.refresh, size: 14),
                        label: const Text(
                          'Reset All',
                          style: TextStyle(
                            fontSize: 11.5,
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
              ],
            ),
            const SizedBox(height: 10),

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
                        final campDropdown = DropdownButtonFormField<String>(
                          key: ValueKey('camp_dropdown_${filters.campId}'),
                          initialValue: filters.campId ?? 'all',
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
                                  '${c.name} (${c.campCode})',
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
                              vm.loadPatients(null);
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
                        key: const ValueKey('surgery_type_dropdown'),
                        initialValue: filters.surgeryType,
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
                  if (mounted && campId != null) {
                    vm.loadPatients(campId);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientCard(
    BuildContext context,
    PatientModel patient,
    CampModel? activeCamp,
    PatientListViewModel vm,
    CampState campState,
  ) {
    // CAMP LOCK CHECK: check if this patient's specific camp is closed/archived
    CampModel? patientCamp;
    try {
      patientCamp = campState.camps.firstWhere((c) => c.id == patient.campId);
    } catch (_) {}
    final isCampLocked = patientCamp != null && patientCamp.status.isLocked;

    // Determine clinical completion status
    final hasReasons = patient.reasonsForVisit.isNotEmpty;
    final hasPhone = patient.mobile.isNotEmpty;
    final hasClinical = patient.hasClinicalVisit;

    // Status colors: Emerald = Clinical completed, Teal = Registered, Amber = Intake Pending
    final Color statusColor = hasClinical
        ? const Color(0xFF10B981)
        : hasReasons
            ? AppTheme.brandPurple
            : const Color(0xFFF59E0B);

    final urgentReasons = {
      'something hanging out',
      'something_hanging_out',
      'problems passing urine',
      'problems_passing_urine',
      'problems passing stool',
      'problems_passing_stool',
      'pain',
      'lower_abdominal_pain',
      'post_menopausal_bleeding',
    };

    final clinicalLabelMap = {
      'routine_checkup': 'Routine Checkup (नियमित जाँच)',
      'checkup': 'Routine Checkup (नियमित जाँच)',
      'something hanging out': 'Uterine Prolapse / आङ खस्ने',
      'something_hanging_out': 'Uterine Prolapse / आङ खस्ने',
      'discharge and or itching': 'Discharge & Itching / सेतो पानी',
      'discharge_and_or_itching': 'Discharge & Itching / सेतो पानी',
      'discharge_itching': 'Discharge & Itching / सेतो पानी',
      'problems passing urine': 'Urinary Issue / पिसाबको समस्या',
      'problems_passing_urine': 'Urinary Issue / पिसाबको समस्या',
      'problems passing stool': 'Anorectal Issue / दिसाको समस्या',
      'problems_passing_stool': 'Anorectal Issue / दिसाको समस्या',
      'menstrual problem': 'Menstrual Disorder / महिनावारी गडबडी',
      'menstrual_problem': 'Menstrual Disorder / महिनावारी गडबडी',
      'infertility': 'Infertility / निसन्तान समस्या',
      'pain': 'Pelvic / Abdominal Pain / पेट दुख्ने',
      'lower_abdominal_pain': 'Lower Abdominal Pain / तल्लो पेट दुख्ने',
      'post_menopausal_bleeding': 'Post-Menopausal Bleeding',
    };

    // Format guardian info gracefully — never print empty "Father: "
    final guardianName = patient.spouseOrFatherName?.trim() ?? '';
    final hasGuardian = guardianName.isNotEmpty && guardianName.toLowerCase() != 'null';
    final relType = patient.relationshipType?.trim() ?? 'Guardian';

    final String subInfoText;
    final maritalStr = patient.maritalStatus.isNotEmpty ? patient.maritalStatus : 'N/A';
    if (hasGuardian) {
      subInfoText = '$relType: $guardianName  •  Age ${patient.age}y  •  $maritalStr';
    } else {
      subInfoText = 'Age ${patient.age}y  •  Female  •  $maritalStr';
    }

    // Resolve location
    final locationParts = <String>[];
    if (patient.municipality.isNotEmpty) locationParts.add(patient.municipality);
    if (patient.district.isNotEmpty) locationParts.add(patient.district);
    final locationStr = locationParts.isNotEmpty ? locationParts.join(', ') : 'Nepal';

    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brandPurple.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          const BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _showClinicalHistoryPanel(context, patient, activeCamp),
          hoverColor: const Color(0xFFF8FAFC),
          splashColor: AppTheme.primaryTeal.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: statusColor, width: 5),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // ── TOP ROW: Token ID (copyable) + Ward + Location ──
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                // Token ID Badge (tap to copy)
                InkWell(
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE9D5FF)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
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
                        const SizedBox(width: 4),
                        const Icon(Icons.copy_rounded, size: 12, color: AppTheme.brandPurple),
                      ],
                    ),
                  ),
                ),

                // Ward Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    'Ward ${patient.ward}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // Location Chip
                if (locationStr.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFF64748B)),
                      const SizedBox(width: 3),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: Text(
                          locationStr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),

                // Interactive Chart Cue
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryTeal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.25)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_edu_rounded, size: 12, color: AppTheme.primaryTeal),
                      SizedBox(width: 4),
                      Text(
                        'View Chart →',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

              // ── PATIENT PROFILE ROW: Avatar + Full Name + Demographics + Phone ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Gradient avatar
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF30026E), Color(0xFF81005D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.brandPurple.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      patient.firstName.isNotEmpty ? patient.firstName[0].toUpperCase() : 'P',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patient.fullName,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.2,
                          ),
                        ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            hasGuardian
                                ? (patient.isBelowAdultAge ? Icons.escalator_warning : Icons.favorite_border)
                                : Icons.person_outline,
                            size: 13,
                            color: const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              subInfoText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (hasPhone) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined, size: 12.5, color: Color(0xFF64748B)),
                            const SizedBox(width: 4),
                            Text(
                              patient.mobile,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // ── REASONS FOR VISIT TAGS (Formatted & Localized) ──
            if (patient.reasonsForVisit.isNotEmpty) ...[
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final activeVisitReasons = ref.watch(activeVisitReasonsProvider);
                  final activeChiefComplaints = ref.watch(activeChiefComplaintsProvider);
                  final combinedLookups = [...activeVisitReasons, ...activeChiefComplaints];
                  return Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: patient.reasonsForVisit.map((reason) {
                      final normReason = reason.toLowerCase().trim().replaceAll('_', ' ');
                      final matchingItems = combinedLookups.where((item) =>
                          item.code.toLowerCase().trim().replaceAll('_', ' ') == normReason ||
                          item.labelEn.toLowerCase().trim().replaceAll('_', ' ') == normReason ||
                          item.labelNe.toLowerCase().trim() == normReason);

                      final String label;
                      final bool isUrgent;

                      if (matchingItems.isNotEmpty) {
                        final item = matchingItems.first;
                        label = item.labelNe.isNotEmpty ? '${item.labelEn} (${item.labelNe})' : item.labelEn;
                        isUrgent = item.subCategory?.toLowerCase().contains('urgent') == true ||
                            normReason == 'post menopausal bleeding';
                      } else {
                        label = clinicalLabelMap[normReason] ??
                            clinicalLabelMap[reason] ??
                            clinicalLabelMap[normReason.replaceAll(' ', '_')] ??
                            reason.replaceAll('_', ' ');
                        isUrgent = urgentReasons.contains(normReason) ||
                            urgentReasons.contains(reason) ||
                            urgentReasons.contains(normReason.replaceAll(' ', '_'));
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isUrgent ? const Color(0xFFFFF1F2) : const Color(0xFFF5F3FF),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isUrgent ? const Color(0xFFFDA4AF) : const Color(0xFFE9D5FF),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isUrgent) ...[
                              const Icon(Icons.priority_high_rounded, size: 11, color: Color(0xFFE11D48)),
                              const SizedBox(width: 3),
                            ],
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 240),
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: isUrgent ? const Color(0xFFBE123C) : AppTheme.brandPurple,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],

            // ── CLINICAL BADGES: Doctor, POP Stage, Surgery, Diagnoses ──
            if (patient.highestPopStage != null ||
                patient.surgeryDone == true ||
                patient.diagnoses.isNotEmpty ||
                patient.primaryDoctorName != null ||
                patient.attendingDoctorNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  // Examining Doctor Badge
                  if ((patient.primaryDoctorName != null && patient.primaryDoctorName!.trim().isNotEmpty) ||
                      patient.attendingDoctorNames.any((d) => d.trim().isNotEmpty)) ...[
                    Builder(
                      builder: (_) {
                        final docRaw = (patient.primaryDoctorName != null && patient.primaryDoctorName!.trim().isNotEmpty)
                            ? patient.primaryDoctorName!
                            : patient.attendingDoctorNames.firstWhere((d) => d.trim().isNotEmpty);
                        final docProf = DoctorProfile.parse(docRaw);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.medical_services_outlined, size: 11.5, color: Color(0xFF2563EB)),
                              const SizedBox(width: 4),
                              Text(
                                docProf.formattedLabel,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1D4ED8),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],

                  // POP Severity Badge
                  if (patient.highestPopStage != null)
                    Builder(
                      builder: (_) {
                        final stage = patient.highestPopStage!;
                        final Color badgeBg = stage >= 3
                            ? const Color(0xFFFEE2E2)
                            : stage == 2
                                ? const Color(0xFFFEF3C7)
                                : const Color(0xFFF0FDF4);
                        final Color badgeBorder = stage >= 3
                            ? const Color(0xFFFCA5A5)
                            : stage == 2
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFFBBF7D0);
                        final Color badgeText = stage >= 3
                            ? const Color(0xFF991B1B)
                            : stage == 2
                                ? const Color(0xFF92400E)
                                : const Color(0xFF166534);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: badgeBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.healing_rounded, size: 11, color: badgeText),
                              const SizedBox(width: 4),
                              Text(
                                'POP Stage $stage',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: badgeText,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                  // Surgery Done Badge
                  if (patient.surgeryDone == true)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_outline_rounded, size: 11.5, color: Color(0xFF166534)),
                          const SizedBox(width: 4),
                          Text(
                            'Surgery: ${patient.surgeryType ?? "Done"}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF166534),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Diagnosis Pills
                  ...patient.diagnoses.take(2).map(
                        (dx) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            dx,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF334155),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            // ── STREAMLINED CLINICAL PROGRESS STEPPER & STATUS BADGE ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildStepIndicator(
                            label: 'S1: Intake',
                            done: true,
                            color: const Color(0xFF10B981),
                          ),
                          _buildStepConnector(done: true),
                          _buildStepIndicator(
                            label: 'S2: Clinical',
                            done: hasClinical,
                            color: hasClinical ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                          ),
                          _buildStepConnector(done: hasClinical),
                          _buildStepIndicator(
                            label: 'S3–6: Specialist',
                            done: hasClinical,
                            color: hasClinical ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: hasClinical
                          ? const Color(0xFFECFDF5)
                          : hasReasons
                              ? const Color(0xFFEFF6FF)
                              : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(6),
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
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: hasClinical
                            ? const Color(0xFF047857)
                            : hasReasons
                                ? const Color(0xFF1D4ED8)
                                : const Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 10),

            // ── ACTION BAR (Primary CTA + Quick Actions + More Menu) ──
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 500;

                final primaryCta = !hasClinical
                    ? ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.brandPurple,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.assignment_rounded, size: 16),
                        label: const Text('Clinical Intake', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ClinicalAssessmentView(patient: patient)),
                          );
                          if (mounted && activeCamp != null) {
                            vm.loadPatients(activeCamp.id);
                          }
                        },
                      )
                    : ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.brandMagenta,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.replay_rounded, size: 16),
                        label: const Text('Follow-Up', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          final updated = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PatientFollowUpFormView(patient: patient, camp: activeCamp),
                            ),
                          );
                          if (updated == true && mounted && activeCamp != null) {
                            vm.loadPatients(activeCamp.id);
                          }
                        },
                      );


                final slipBtn = OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 16, color: AppTheme.brandPurple),
                  label: const Text('Slip / QR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                      if (activeCamp != null) {
                        vm.loadPatients(activeCamp.id);
                      }
                    }
                  },
                );

                PopupMenuItem<String> buildMenuItem({
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.more_horiz_rounded, size: 17, color: Color(0xFF334155)),
                        SizedBox(width: 4),
                        Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: Color(0xFF64748B)),
                      ],
                    ),
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
                        if (context.mounted && updated != null && activeCamp != null) {
                          vm.loadPatients(activeCamp.id);
                        }
                        break;
                      case 're_exam':
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ClinicalAssessmentView(patient: patient)),
                        );
                        if (mounted && activeCamp != null) {
                          vm.loadPatients(activeCamp.id);
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Summary PDF downloaded: $saved'),
                              backgroundColor: AppTheme.successGreen,
                            ),
                          );
                        }
                        break;
                      case 'follow_up_slip':
                        await _downloadFollowUpSlip(context, patient, activeCamp);
                        break;
                      case 'print_reg_form':
                        await _printRegistrationForm(context, patient, activeCamp);
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    buildMenuHeader('CLINICAL WORKFLOW'),
                    if (hasClinical)
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
                    buildMenuItem(
                      value: 'print_reg_form',
                      icon: Icons.print_outlined,
                      iconColor: const Color(0xFF475569),
                      iconBg: const Color(0xFFF1F5F9),
                      title: 'Registration Form (Yellow)',
                      subtitle: 'Reprint physical block form',
                    ),
                  ],
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      primaryCta,
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: slipBtn),
                          const SizedBox(width: 8),
                          moreMenu,
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        primaryCta,
                        const SizedBox(width: 10),
                        slipBtn,
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isCampLocked)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFF87171)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_rounded, size: 12, color: Color(0xFFDC2626)),
                                SizedBox(width: 4),
                                Text(
                                  'Camp Closed',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                                ),
                              ],
                            ),
                          ),
                        moreMenu,
                      ],
                    ),
                  ],
                );
              },
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator({
    required String label,
    required bool done,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: done ? const Color(0xFF065F46) : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnector({required bool done}) {
    return Container(
      width: 16,
      height: 1.5,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: done ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
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
            content: SizedBox(
              width: 500,
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

  // ─── Print Block-Letter Registration Form ─────────────────────────────────
  Future<void> _printRegistrationForm(
    BuildContext context,
    PatientModel patient,
    CampModel? camp,
  ) async {
    final effectiveOrg = ref.read(effectiveOrganizationProvider);
    final orgName = (camp?.organizationName.isNotEmpty == true &&
            !AppConstants.isLegacyDefaultOrganization(camp!.organizationName))
        ? camp.organizationName
        : effectiveOrg;

    DoctorProfile? chosenDoctor;
    final doctors = camp?.doctorProfiles ?? [];
    final showDoctor = camp?.showDoctorOnForms ?? true;

    if (showDoctor && doctors.length > 1) {
      chosenDoctor = await showDialog<DoctorProfile?>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              const Icon(Icons.print_outlined, color: AppTheme.brandPurple, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Select Doctor for ${patient.fullName}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose which doctor\'s name and NMC registration number to stamp on this form:',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 12),
              ...doctors.map(
                (doc) => ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  leading: const Icon(Icons.medical_services_outlined, color: AppTheme.brandPurple, size: 18),
                  title: Text(doc.displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(doc.hasNmc ? 'NMC: ${doc.nmcNumber}' : 'NMC Certified', style: const TextStyle(fontSize: 11)),
                  onTap: () => Navigator.pop(ctx, doc),
                ),
              ),
              const Divider(),
              ListTile(
                dense: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                leading: const Icon(Icons.edit_outlined, color: Color(0xFF64748B), size: 18),
                title: const Text('Blank Doctor Field', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: const Text('Leave doctor & NMC line blank for handwritten on-site signature', style: TextStyle(fontSize: 11)),
                onTap: () => Navigator.pop(ctx, const DoctorProfile(name: '')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (chosenDoctor == null) return;
      if (chosenDoctor.name.isEmpty) chosenDoctor = null;
    } else if (doctors.length == 1) {
      chosenDoctor = doctors.first;
    }

    if (!context.mounted) return;

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generating registration form PDF...'),
          duration: Duration(seconds: 2),
        ),
      );
      final masterState = ref.read(masterLookupProvider);
      final bytes = await PdfReportService().generatePatientRegistrationFormPdf(
        patient: patient,
        camp: camp,
        doctor: chosenDoctor,
        organizationName: orgName,
        diagnoses: masterState.activeDiagnoses,
        medications: masterState.activeMedicines,
        referralHospitals: masterState.activeReferralHospitals,
        visitReasons: masterState.activeVisitReasons,
        chiefComplaints: masterState.activeChiefComplaints,
      );
      await FileDownloadHelper.saveAndDownloadFile(
        bytes: bytes,
        filename: 'RegistrationForm_${patient.patientId}.pdf',
        mimeType: 'application/pdf',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Registration form downloaded: RegistrationForm_${patient.patientId}.pdf',
            ),
            backgroundColor: AppTheme.successGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating form: $e'),
            backgroundColor: AppTheme.dangerRose,
          ),
        );
      }
    }
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

      await FileDownloadHelper.saveAndDownloadFile(
        bytes: bytes,
        filename: 'FollowUpSlip_${patient.patientId}.pdf',
        mimeType: 'application/pdf',
      );

      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Follow-up slip downloaded: FollowUpSlip_${patient.patientId}.pdf'),
          backgroundColor: AppTheme.successGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
            child: Container(
              width: MediaQuery.of(context).size.width * 0.88,
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
        );
      },
    );
  }
}


