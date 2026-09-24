import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/clinical_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/lookup_item_model.dart';
import '../../repositories/lookup_repository.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../../viewmodels/master_lookup_viewmodel.dart';

class MasterConfigView extends ConsumerStatefulWidget {
  final String? initialCampId;
  const MasterConfigView({super.key, this.initialCampId});

  @override
  ConsumerState<MasterConfigView> createState() => _MasterConfigViewState();
}

class _MasterConfigViewState extends ConsumerState<MasterConfigView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _statusFilter = 'ALL'; // 'ALL', 'ACTIVE', 'INACTIVE'
  bool _groupByCategory = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
        final category = _getCategoryForIndex(_tabController.index);
        ref.read(masterLookupProvider.notifier).setCategory(category);
      }
    });
    if (widget.initialCampId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(masterLookupProvider.notifier).setCampScope(widget.initialCampId);
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _getCategoryForIndex(int idx) {
    switch (idx) {
      case 0:
        return 'diagnosis';
      case 1:
        return 'medicine';
      case 2:
        return 'referral_hospital';
      case 3:
        return 'visit_reason';
      case 4:
      default:
        return 'chief_complaint';
    }
  }

  Color _getCategoryThemeColor(int idx) {
    switch (idx) {
      case 0:
        return AppTheme.primaryTeal;
      case 1:
        return const Color(0xFF059669);
      case 2:
        return const Color(0xFF4F46E5);
      case 3:
        return const Color(0xFFD97706); // Amber for Visit Reasons
      case 4:
      default:
        return const Color(0xFFE11D48); // Rose for Chief Complaints
    }
  }

  String _formatTitle(String text) {
    if (text.isEmpty) return text;
    if (text == text.toUpperCase() || text.contains(RegExp(r'[A-Z]'))) {
      return text;
    }
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      if (word.startsWith('(') && word.length > 1) {
        return '(${word[1].toUpperCase()}${word.substring(2)}';
      }
      return '${word[0].toUpperCase()}${word.substring(1)}';
    }).join(' ');
  }

  String _getCategorySingularTitle(int idx) {
    switch (idx) {
      case 0:
        return 'Diagnosis';
      case 1:
        return 'Medicine';
      case 2:
        return 'Hospital';
      case 3:
        return 'Visit Reason';
      case 4:
      default:
        return 'Chief Complaint';
    }
  }

  String _getCategoryPluralTitle(int idx) {
    switch (idx) {
      case 0:
        return 'Diagnoses';
      case 1:
        return 'Medicines';
      case 2:
        return 'Referral Hospitals';
      case 3:
        return 'Visit Reasons';
      case 4:
      default:
        return 'Chief Complaints';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(masterLookupProvider);
    final user = ref.watch(authStateProvider).currentUser;
    final deviceState = ref.watch(deviceSecurityProvider);
    final campState = ref.watch(campStateProvider);

    final totalEntities = state.diagnoses.length +
        state.medicines.length +
        state.referralHospitals.length +
        state.visitReasons.length +
        state.chiefComplaints.length;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: isCompact ? 64 : 68,
        backgroundColor: const Color(0xFF0F766E),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.dataset_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    isCompact ? 'Master Data & Formulary' : 'Clinical Master Data & Formulary',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isCompact ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$totalEntities Entities',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Unified Master Database & Standard Clinical Dictionary ($totalEntities Active / Cataloged Entries)',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Reload Master Catalog',
            onPressed: () {
              ref.read(masterLookupProvider.notifier).loadAll();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Refreshing Master Data Catalog from central repository...'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          if (!isCompact)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Center(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primaryTeal,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(
                    'Add ${_getCategorySingularTitle(_tabController.index)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: () => _showAddEditDialog(
                    context,
                    null,
                    _getCategoryForIndex(_tabController.index),
                  ),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: _getCategoryThemeColor(_tabController.index),
              unselectedLabelColor: Colors.blueGrey.shade600,
              indicatorColor: _getCategoryThemeColor(_tabController.index),
              indicatorWeight: 3.0,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
              tabs: [
                Tab(
                  icon: const Icon(Icons.healing_outlined, size: 17),
                  text: 'Diagnoses (${state.diagnoses.length})',
                ),
                Tab(
                  icon: const Icon(Icons.medication_outlined, size: 17),
                  text: 'Medicines (${state.medicines.length})',
                ),
                Tab(
                  icon: const Icon(Icons.local_hospital_outlined, size: 17),
                  text: 'Referral Hospitals (${state.referralHospitals.length})',
                ),
                Tab(
                  icon: const Icon(Icons.checklist_outlined, size: 17),
                  text: 'Visit Reasons (${state.visitReasons.length})',
                ),
                Tab(
                  icon: const Icon(Icons.sick_outlined, size: 17),
                  text: 'Chief Complaints (${state.chiefComplaints.length})',
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: isCompact
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: Text('Add ${_getCategorySingularTitle(_tabController.index)}'),
              backgroundColor: AppTheme.primaryTeal,
              foregroundColor: Colors.white,
              onPressed: () => _showAddEditDialog(context, null, _getCategoryForIndex(_tabController.index)),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              // Responsive KPI Metric Cards
              _buildCategoryKpiCards(state, _tabController.index),

              // Search & Filter Toolbar Card
              Container(
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderLight),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Camp Scope Selector
                    Row(
                      children: [
                        const Icon(Icons.domain_outlined, size: 18, color: AppTheme.primaryTeal),
                        const SizedBox(width: 8),
                        const Text(
                          'Configuration Scope:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.borderLight),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                value: state.selectedCampId,
                                isExpanded: true,
                                icon: const Icon(Icons.arrow_drop_down, size: 20),
                                style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('🌐 Global Defaults (All Camps)'),
                                  ),
                                  ...campState.camps.map(
                                    (c) => DropdownMenuItem<String?>(
                                      value: c.id,
                                      child: Text('🏕️ ${c.campCode} - ${c.name}'),
                                    ),
                                  ),
                                  if (state.selectedCampId != null &&
                                      !campState.camps.any((c) => c.id == state.selectedCampId))
                                    DropdownMenuItem<String?>(
                                      value: state.selectedCampId,
                                      child: Text('🏕️ Selected Camp (${state.selectedCampId})'),
                                    ),
                                ],
                                onChanged: (val) {
                                  ref.read(masterLookupProvider.notifier).setCampScope(val);
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Search Bar
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.primaryTeal),
                        hintText: 'Search in ${_getCategoryPluralTitle(_tabController.index)} (English or Nepali)...',
                        hintStyle: const TextStyle(fontSize: 13, color: Colors.blueGrey),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(masterLookupProvider.notifier).setSearchQuery('');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.borderLight),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.borderLight),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onChanged: (val) {
                        ref.read(masterLookupProvider.notifier).setSearchQuery(val);
                      },
                    ),
                    const SizedBox(height: 10),

                    // Filter Chips & Category Subtitle (Responsive Wrap to prevent overflow)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildStatusChip('ALL', 'All Items'),
                        _buildStatusChip('ACTIVE', 'Active Only'),
                        _buildStatusChip('INACTIVE', 'Disabled'),
                        if (state.selectedCampId != null && state.excludedFromCurrentCamp.isNotEmpty)
                          _buildStatusChip(
                            'EXCLUDED',
                            'Excluded (${state.excludedFromCurrentCamp.where((i) => i.category == _getCategoryForIndex(_tabController.index)).length})',
                          ),
                        if (_tabController.index != 2)
                          ActionChip(
                            avatar: Icon(
                              _groupByCategory ? Icons.category_rounded : Icons.view_list_rounded,
                              size: 14,
                              color: AppTheme.primaryTeal,
                            ),
                            label: Text(
                              _groupByCategory ? 'Grouped by Category' : 'Flat List',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
                            ),
                            backgroundColor: AppTheme.primaryLight,
                            side: const BorderSide(color: AppTheme.primaryTeal),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _groupByCategory = !_groupByCategory),
                          ),
                        _buildCategoryContextBadge(_tabController.index),
                      ],
                    ),
                  ],
                ),
              ),

              // Tab View Content
              Expanded(
                child: (state.isLoading && state.diagnoses.isEmpty)
                    ? const Center(child: CircularProgressIndicator())
                    : Stack(
                        children: [
                          TabBarView(
                            controller: _tabController,
                            children: [
                              _buildItemsList(
                                context,
                                state.filteredDiagnoses,
                                user?.id ?? 'admin-user',
                                deviceState.device?.deviceId ?? 'dev-admin',
                                categoryIndex: 0,
                              ),
                              _buildItemsList(
                                context,
                                state.filteredMedicines,
                                user?.id ?? 'admin-user',
                                deviceState.device?.deviceId ?? 'dev-admin',
                                categoryIndex: 1,
                              ),
                              _buildItemsList(
                                context,
                                state.filteredReferralHospitals,
                                user?.id ?? 'admin-user',
                                deviceState.device?.deviceId ?? 'dev-admin',
                                categoryIndex: 2,
                              ),
                              _buildItemsList(
                                context,
                                state.filteredVisitReasons,
                                user?.id ?? 'admin-user',
                                deviceState.device?.deviceId ?? 'dev-admin',
                                categoryIndex: 3,
                              ),
                              _buildItemsList(
                                context,
                                state.filteredChiefComplaints,
                                user?.id ?? 'admin-user',
                                deviceState.device?.deviceId ?? 'dev-admin',
                                categoryIndex: 4,
                              ),
                            ],
                          ),
                          if (state.isLoading)
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
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryKpiCards(MasterLookupState state, int tabIndex) {
    List<LookupItemModel> currentItems;
    String categoryName;
    Color themeColor;

    switch (tabIndex) {
      case 0:
        currentItems = state.diagnoses;
        categoryName = 'Diagnoses';
        themeColor = AppTheme.primaryTeal;
        break;
      case 1:
        currentItems = state.medicines;
        categoryName = 'Medicines';
        themeColor = const Color(0xFF059669);
        break;
      case 2:
        currentItems = state.referralHospitals;
        categoryName = 'Referral Hospitals';
        themeColor = const Color(0xFF4F46E5);
        break;
      case 3:
        currentItems = state.visitReasons;
        categoryName = 'Visit Reasons';
        themeColor = const Color(0xFFD97706);
        break;
      case 4:
      default:
        currentItems = state.chiefComplaints;
        categoryName = 'Chief Complaints';
        themeColor = const Color(0xFFE11D48);
        break;
    }

    final activeCount = currentItems.where((i) => i.isActive).length;
    final inactiveCount = currentItems.length - activeCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 620;

          final card1 = _buildKpiCard(
            label: 'Active $categoryName',
            count: '$activeCount',
            icon: Icons.check_circle_outline,
            color: const Color(0xFF059669),
            bgColor: const Color(0xFFECFDF5),
            borderColor: const Color(0xFFA7F3D0),
          );

          final card2 = _buildKpiCard(
            label: 'Disabled / Inactive',
            count: '$inactiveCount',
            icon: Icons.pause_circle_outline,
            color: const Color(0xFFD97706),
            bgColor: const Color(0xFFFFFBEB),
            borderColor: const Color(0xFFFDE68A),
          );

          final card3 = _buildKpiCard(
            label: 'Total $categoryName',
            count: '${currentItems.length}',
            icon: Icons.folder_outlined,
            color: themeColor,
            bgColor: themeColor.withValues(alpha: 0.08),
            borderColor: themeColor.withValues(alpha: 0.25),
          );

          if (isNarrow) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(width: 140, child: card1),
                  const SizedBox(width: 8),
                  SizedBox(width: 140, child: card2),
                  const SizedBox(width: 8),
                  SizedBox(width: 140, child: card3),
                ],
              ),
            );
          }

          return Row(
            children: [
              Expanded(child: card1),
              const SizedBox(width: 12),
              Expanded(child: card2),
              const SizedBox(width: 12),
              Expanded(child: card3),
            ],
          );
        },
      ),
    );
  }

  Widget _buildKpiCard({
    required String label,
    required String count,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondaryLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String filterKey, String label) {
    final isSelected = _statusFilter == filterKey;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppTheme.primaryDark : Colors.blueGrey,
        ),
      ),
      selected: isSelected,
      selectedColor: AppTheme.primaryLight,
      backgroundColor: const Color(0xFFF1F5F9),
      side: BorderSide(color: isSelected ? AppTheme.primaryTeal : Colors.transparent),
      visualDensity: VisualDensity.compact,
      onSelected: (_) {
        setState(() {
          _statusFilter = filterKey;
        });
      },
    );
  }

  Widget _buildCategoryContextBadge(int idx) {
    String text;
    IconData icon;
    Color color = _getCategoryThemeColor(idx);

    switch (idx) {
      case 0:
        text = 'WHO / MoHP Standard Clinical Diagnoses';
        icon = Icons.verified_user_outlined;
        break;
      case 1:
        text = 'Outreach Formulary & Dispensary Core';
        icon = Icons.local_pharmacy_outlined;
        break;
      case 2:
      default:
        text = 'Secondary & Tertiary Referral Centers';
        icon = Icons.domain_outlined;
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(
            text,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildItemsList(
    BuildContext context,
    List<LookupItemModel> items,
    String adminUserId,
    String deviceId, {
    required int categoryIndex,
  }) {
    final state = ref.watch(masterLookupProvider);
    final categoryName = _getCategoryForIndex(categoryIndex);
    final isExcludedMode = _statusFilter == 'EXCLUDED';

    // Apply local status filter (ALL, ACTIVE, INACTIVE, EXCLUDED)
    final filtered = isExcludedMode
        ? state.excludedFromCurrentCamp.where((i) => i.category == categoryName).toList()
        : items.where((i) {
            if (_statusFilter == 'ACTIVE' && !i.isActive) return false;
            if (_statusFilter == 'INACTIVE' && i.isActive) return false;
            return true;
          }).toList();

    final vm = ref.read(masterLookupProvider.notifier);
    final user = ref.read(authStateProvider).currentUser;
    final categoryColor = _getCategoryThemeColor(categoryIndex);

    Widget listWidget;

    if (filtered.isEmpty) {
      listWidget = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Icon(Icons.inventory_2_outlined, size: 40, color: Colors.blueGrey.shade400),
              ),
              const SizedBox(height: 12),
              Text(
                _searchController.text.isNotEmpty
                    ? 'No ${_getCategoryPluralTitle(categoryIndex)} match "${_searchController.text}".'
                    : 'No ${_getCategoryPluralTitle(categoryIndex)} found for the selected filter.',
                style: const TextStyle(color: Colors.blueGrey, fontSize: 13, fontWeight: FontWeight.w500),
              ),
              if (_searchController.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: TextButton.icon(
                    icon: const Icon(Icons.clear, size: 14),
                    label: const Text('Clear Search'),
                    onPressed: () {
                      _searchController.clear();
                      ref.read(masterLookupProvider.notifier).setSearchQuery('');
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    } else if (_groupByCategory && (categoryIndex == 0 || categoryIndex == 1)) {
      // Categorized Accordion View
      final definedCategories = categoryIndex == 0
          ? ClinicalConstants.diagnosisCategories
          : ClinicalConstants.medicationCategories;

      final Map<String, List<LookupItemModel>> grouped = {};
      for (final cat in definedCategories) {
        grouped[cat] = [];
      }

      for (final item in filtered) {
        final fallback = categoryIndex == 0
            ? (ClinicalConstants.diagnosisCategoryMap[item.labelEn] ?? 'General / Other')
            : (ClinicalConstants.medicationCategoryMap[item.labelEn] ?? 'Other / Custom');
        final cat = (item.subCategory != null && item.subCategory!.isNotEmpty)
            ? item.subCategory!
            : fallback;
        grouped.putIfAbsent(cat, () => []).add(item);
      }

      final activeGroups = grouped.entries.where((e) => e.value.isNotEmpty).toList();

      listWidget = ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        itemCount: activeGroups.length,
        itemBuilder: (context, gIdx) {
          final groupName = activeGroups[gIdx].key;
          final groupItems = activeGroups[gIdx].value;
          final activeCount = groupItems.where((i) => i.isActive).length;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: activeCount > 0 ? categoryColor.withValues(alpha: 0.3) : const Color(0xFFE2E8F0),
                width: 1.2,
              ),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: true,
                leading: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    categoryIndex == 0 ? Icons.medical_services_outlined : Icons.medication_outlined,
                    size: 18,
                    color: categoryColor,
                  ),
                ),
                title: Text(
                  groupName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.textPrimaryLight),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$activeCount / ${groupItems.length} Active',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: categoryColor),
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: Column(
                      children: List.generate(groupItems.length, (idx) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: _buildItemCard(
                            context,
                            groupItems[idx],
                            idx,
                            categoryColor,
                            adminUserId,
                            deviceId,
                            vm,
                            user,
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      // Flat List View
      listWidget = ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = filtered[index];
          return _buildItemCard(
            context,
            item,
            index,
            categoryColor,
            adminUserId,
            deviceId,
            vm,
            user,
          );
        },
      );
    }

    return Column(
      children: [
        if (categoryIndex == 2)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFC7D2FE)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Color(0xFF4338CA)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Surgical Referral Centers: Configure tertiary surgical partner hospitals for Station 5 (Referral for Surgery). Community follow-up destinations (Local Health Post, GynaeSupport Nurse) in Station 6 follow standardized medical protocols.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF3730A3), height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        Expanded(child: listWidget),
      ],
    );
  }

  Widget _buildItemCard(
    BuildContext context,
    LookupItemModel item,
    int index,
    Color categoryColor,
    String adminUserId,
    String deviceId,
    MasterLookupViewModel vm,
    dynamic user,
  ) {
    final isActive = item.isActive;
    final formattedTitle = _formatTitle(item.labelEn);
    final hasNepali = item.labelNe.isNotEmpty && item.labelNe != item.labelEn;

    return Card(
      elevation: 0,
      color: isActive ? Colors.white : const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(
              color: isActive ? categoryColor : Colors.grey.shade400,
              width: 4,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        child: Row(
          children: [
            // Leading Index Number Badge
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isActive ? categoryColor.withValues(alpha: 0.1) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isActive ? categoryColor : Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Title, Nepali, Sub-Category & Code Badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formattedTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: isActive ? const Color(0xFF1E293B) : Colors.grey.shade500,
                      decoration: isActive ? null : TextDecoration.lineThrough,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF059669).withValues(alpha: 0.1)
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isActive ? 'ACTIVE' : 'INACTIVE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isActive ? const Color(0xFF059669) : Colors.grey.shade600,
                          ),
                        ),
                      ),
                      if (hasNepali)
                        Text(
                          item.labelNe,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: isActive ? const Color(0xFF0D9488) : Colors.grey.shade500,
                          ),
                        )
                      else
                        Text(
                          'Nepali translation pending',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      if (item.subCategory != null && item.subCategory!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: categoryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: categoryColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            item.subCategory!,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: categoryColor,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFFF1F5F9) : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Text(
                          'CODE: ${item.code.toUpperCase()}',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: isActive ? const Color(0xFF334155) : Colors.grey.shade500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Trailing Controls: Switch, Edit, Delete / Restore
            if (_statusFilter == 'EXCLUDED') ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.restore_from_trash, size: 14, color: Color(0xFF059669)),
                label: const Text('Restore', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF059669)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () async {
                  await vm.restoreItemToCamp(
                    item.id,
                    userId: adminUserId,
                    userName: user?.name ?? 'Super Admin',
                    deviceId: deviceId,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Restored "${item.labelEn}" to this camp.'),
                        backgroundColor: AppTheme.successGreen,
                      ),
                    );
                  }
                },
              ),
            ] else ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: isActive,
                    activeTrackColor: categoryColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (val) {
                      vm.toggleItemStatus(
                        item.id,
                        val,
                        userId: adminUserId,
                        userName: user?.name ?? 'Super Admin',
                        deviceId: deviceId,
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: AppTheme.primaryDark,
                    tooltip: 'Edit Master Record',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    onPressed: () => _showAddEditDialog(context, item, item.category),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.dangerRose),
                    tooltip: 'Delete Master Record',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    onPressed: () => _confirmDelete(context, item, adminUserId, deviceId),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAddEditDialog(BuildContext context, LookupItemModel? item, String category) {
    final isEditing = item != null;
    final enCtrl = TextEditingController(text: item?.labelEn ?? '');
    final neCtrl = TextEditingController(text: item?.labelNe ?? '');
    final codeCtrl = TextEditingController(text: item?.code ?? '');
    final customCategoryCtrl = TextEditingController();
    bool isCustomCategoryMode = false;

    final lookupState = ref.read(masterLookupProvider);
    final List<String> availableCategories = [];
    if (category == 'diagnosis') {
      availableCategories.addAll(ClinicalConstants.diagnosisCategories);
      for (final d in lookupState.diagnoses) {
        if (d.subCategory != null && d.subCategory!.isNotEmpty && !availableCategories.contains(d.subCategory)) {
          availableCategories.add(d.subCategory!);
        }
      }
    } else if (category == 'medicine') {
      availableCategories.addAll(ClinicalConstants.medicationCategories);
      for (final m in lookupState.medicines) {
        if (m.subCategory != null && m.subCategory!.isNotEmpty && !availableCategories.contains(m.subCategory)) {
          availableCategories.add(m.subCategory!);
        }
      }
    } else if (category == 'chief_complaint') {
      availableCategories.addAll([
        'Pelvic & Abdominal',
        'Infections & Discharge',
        'Pelvic Floor & Prolapse',
        'Urinary Symptoms',
        'Reproductive & Sexual',
        'Bleeding & Neoplasms',
        'Musculoskeletal & General',
      ]);
      for (final c in lookupState.chiefComplaints) {
        if (c.subCategory != null && c.subCategory!.isNotEmpty && !availableCategories.contains(c.subCategory)) {
          availableCategories.add(c.subCategory!);
        }
      }
    }

    String selectedSubCategory = item?.subCategory ??
        (availableCategories.isNotEmpty ? availableCategories.first : 'General / Other');
    if (!availableCategories.contains(selectedSubCategory) && selectedSubCategory.isNotEmpty) {
      availableCategories.add(selectedSubCategory);
    }

    const String addCustomCategorySentinel = '__ADD_CUSTOM_CATEGORY__';

    final user = ref.read(authStateProvider).currentUser;
    final deviceState = ref.read(deviceSecurityProvider);
    final vm = ref.read(masterLookupProvider.notifier);
    final singular = _getCategoryTitleSingular(category);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    category == 'diagnosis'
                        ? Icons.healing_outlined
                        : (category == 'medicine'
                            ? Icons.medication_outlined
                            : (category == 'chief_complaint'
                                ? Icons.sick_outlined
                                : (category == 'visit_reason'
                                    ? Icons.checklist_outlined
                                    : Icons.local_hospital_outlined))),
                    size: 22,
                    color: AppTheme.primaryTeal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isEditing ? 'Edit $singular Record' : 'Add New $singular',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Standard Clinical Master Entity',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.sync, size: 16, color: Color(0xFF16A34A)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Changes automatically synchronize with all offline tablets and outreach workstations.',
                              style: TextStyle(fontSize: 11, color: Colors.green.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: enCtrl,
                      decoration: const InputDecoration(
                        labelText: 'English Name / Term *',
                        hintText: 'e.g. Polycystic Ovary Syndrome',
                        prefixIcon: Icon(Icons.language, size: 18),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: neCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nepali Translation (नेपाली नाम)',
                        hintText: 'e.g. पाठेघरको समस्या',
                        prefixIcon: Icon(Icons.translate, size: 18),
                      ),
                    ),
                    if (category == 'diagnosis' || category == 'medicine' || category == 'chief_complaint') ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        key: ValueKey(isCustomCategoryMode ? addCustomCategorySentinel : selectedSubCategory),
                        isExpanded: true,
                        initialValue: isCustomCategoryMode ? addCustomCategorySentinel : selectedSubCategory,
                        decoration: const InputDecoration(
                          labelText: 'Clinical Sub-Category / Group *',
                          prefixIcon: Icon(Icons.category_outlined, size: 18),
                        ),
                        items: [
                          ...availableCategories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))),
                          const DropdownMenuItem(
                            value: addCustomCategorySentinel,
                            child: Row(
                              children: [
                                Icon(Icons.add_circle_outline, size: 16, color: AppTheme.primaryTeal),
                                SizedBox(width: 6),
                                Text(
                                  '+ Add Custom Category...',
                                  style: TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val == addCustomCategorySentinel) {
                            setDialogState(() {
                              isCustomCategoryMode = true;
                            });
                          } else if (val != null) {
                            setDialogState(() {
                              selectedSubCategory = val;
                              isCustomCategoryMode = false;
                            });
                          }
                        },
                      ),
                      if (isCustomCategoryMode) ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: customCategoryCtrl,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: 'New Custom Category Name *',
                            hintText: 'e.g. Specialized Endocrine / Oncology',
                            prefixIcon: const Icon(Icons.playlist_add, size: 18, color: AppTheme.primaryTeal),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              tooltip: 'Cancel Custom Category',
                              onPressed: () {
                                setDialogState(() {
                                  isCustomCategoryMode = false;
                                  customCategoryCtrl.clear();
                                });
                              },
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF0FDFA),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: AppTheme.primaryTeal),
                            ),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: codeCtrl,
                      decoration: InputDecoration(
                        labelText: 'Code / Identifier (कोड)',
                        hintText: isEditing ? item.code : 'e.g. HOSP_MODEL_HOSPITAL',
                        prefixIcon: const Icon(Icons.tag, size: 18),
                        helperText: 'Standardized clinical identifier (auto-derived if blank)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final enText = enCtrl.text.trim();
                  if (enText.isEmpty) {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please provide an English label.'),
                        backgroundColor: AppTheme.dangerRose,
                      ),
                    );
                    return;
                  }

                  final finalSubCategory = isCustomCategoryMode
                      ? (customCategoryCtrl.text.trim().isNotEmpty
                          ? customCategoryCtrl.text.trim()
                          : 'Other / Custom')
                      : selectedSubCategory;

                  var rawCode = codeCtrl.text.trim();
                  if (rawCode.isEmpty) {
                    rawCode = enText.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
                  }
                  final sanitizedCode = LookupRepository.sanitizeCode(rawCode, enText, category);

                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);
                  if (isEditing) {
                    final updated = item.copyWith(
                      labelEn: enText,
                      labelNe: neCtrl.text.trim(),
                      code: sanitizedCode,
                      subCategory: finalSubCategory,
                    );
                    await vm.updateItem(
                      updated,
                      userId: user?.id ?? 'admin-user',
                      userName: user?.name ?? 'Super Admin',
                      deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                    );
                  } else {
                    final newItem = LookupItemModel(
                      id: 'lookup-${DateTime.now().millisecondsSinceEpoch}',
                      category: category,
                      subCategory: finalSubCategory,
                      code: sanitizedCode,
                      labelEn: enText,
                      labelNe: neCtrl.text.trim(),
                      isActive: true,
                      tenantId: user?.tenantId ?? 'tenant_default',
                      campId: lookupState.selectedCampId,
                    );
                    await vm.addItem(
                      newItem,
                      userId: user?.id ?? 'admin-user',
                      userName: user?.name ?? 'Super Admin',
                      deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                    );
                  }

                  if (mounted) {
                    messenger.clearSnackBars();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Saved "$enText" successfully.'),
                        backgroundColor: AppTheme.successGreen,
                      ),
                    );
                  }
                },
                child: Text(isEditing ? 'Save Changes' : 'Add Item'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, LookupItemModel item, String adminUserId, String deviceId) {
    final vm = ref.read(masterLookupProvider.notifier);
    final user = ref.read(authStateProvider).currentUser;
    final state = ref.read(masterLookupProvider);
    final isScopedToCamp = state.selectedCampId != null;
    final isCampSpecific = item.campId == state.selectedCampId;

    final String title;
    final String body;
    final String actionText;
    final String successText;

    if (isScopedToCamp && !isCampSpecific) {
      title = 'Remove from Selected Camp?';
      body = 'Remove "${item.labelEn}" from this camp roster?\n\nThis will ONLY remove it for this specific camp. It will remain active and untouched as a global default for all other camps.';
      actionText = 'Remove from Camp';
      successText = 'Removed "${item.labelEn}" from this camp.';
    } else if (isScopedToCamp && isCampSpecific) {
      title = 'Delete Camp-Specific Item?';
      body = 'Are you sure you want to permanently delete "${item.labelEn}" from this camp?';
      actionText = 'Delete Permanently';
      successText = 'Deleted "${item.labelEn}" from this camp.';
    } else {
      title = 'Delete Master Item?';
      body = 'Are you sure you want to permanently delete "${item.labelEn}" from all camps?';
      actionText = 'Delete Permanently';
      successText = 'Deleted "${item.labelEn}" permanently.';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.dangerRose, size: 24),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              body,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: const Text(
                'Clinical Safety Note: If this item is already recorded in completed patient visits, deactivating it is strongly recommended instead of deletion to preserve historical medical integrity.',
                style: TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          OutlinedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              await vm.toggleItemStatus(
                item.id,
                false,
                userId: adminUserId,
                userName: user?.name ?? 'Super Admin',
                deviceId: deviceId,
                campId: state.selectedCampId,
              );
              if (mounted) {
                messenger.clearSnackBars();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Disabled "${item.labelEn}".'),
                    backgroundColor: const Color(0xFFD97706),
                  ),
                );
              }
            },
            child: const Text('Deactivate Instead'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose, foregroundColor: Colors.white),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              await vm.deleteItem(
                item.id,
                userId: adminUserId,
                userName: user?.name ?? 'Super Admin',
                deviceId: deviceId,
                campId: state.selectedCampId,
              );
              if (mounted) {
                messenger.clearSnackBars();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(successText),
                    backgroundColor: AppTheme.dangerRose,
                  ),
                );
              }
            },
            child: Text(actionText),
          ),
        ],
      ),
    );
  }

  String _getCategoryTitleSingular(String category) {
    switch (category) {
      case 'diagnosis':
        return 'Diagnosis';
      case 'medicine':
        return 'Medicine';
      case 'referral_hospital':
        return 'Referral Hospital';
      case 'visit_reason':
        return 'Visit Reason';
      case 'chief_complaint':
      default:
        return 'Chief Complaint';
    }
  }
}
