import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../models/lookup_item_model.dart';
import '../../repositories/lookup_repository.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../../viewmodels/master_lookup_viewmodel.dart';

class MasterConfigView extends ConsumerStatefulWidget {
  const MasterConfigView({super.key});

  @override
  ConsumerState<MasterConfigView> createState() => _MasterConfigViewState();
}

class _MasterConfigViewState extends ConsumerState<MasterConfigView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _statusFilter = 'ALL'; // 'ALL', 'ACTIVE', 'INACTIVE'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
        final category = _getCategoryForIndex(_tabController.index);
        ref.read(masterLookupProvider.notifier).setCategory(category);
      }
    });
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
      default:
        return 'referral_hospital';
    }
  }

  Color _getCategoryThemeColor(int idx) {
    switch (idx) {
      case 0:
        return AppTheme.primaryTeal;
      case 1:
        return const Color(0xFF059669); // Emerald for Pharmacy / Medicine
      case 2:
      default:
        return const Color(0xFF4F46E5); // Indigo for Referral Hospitals
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(masterLookupProvider);
    final user = ref.watch(authStateProvider).currentUser;
    final deviceState = ref.watch(deviceSecurityProvider);

    final totalEntities = state.diagnoses.length + state.medicines.length + state.referralHospitals.length;
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
              isCompact
                  ? 'Clinical formulary & referral directory'
                  : 'Standardized clinical terminology, prescription formulary & hospital referral directory',
              style: const TextStyle(color: Color(0xFFCCFBF1), fontSize: 11, fontWeight: FontWeight.normal),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (!isCompact)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: Text('Add ${_getCategorySingularTitle(_tabController.index)}'),
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
                onPressed: () => _showAddEditDialog(context, null, _getCategoryForIndex(_tabController.index)),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.white),
              tooltip: 'Add ${_getCategorySingularTitle(_tabController.index)}',
              onPressed: () => _showAddEditDialog(context, null, _getCategoryForIndex(_tabController.index)),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            width: double.infinity,
            color: const Color(0xFF042F2E),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                        _buildCategoryContextBadge(_tabController.index),
                      ],
                    ),
                  ],
                ),
              ),

              // Tab View Content
              Expanded(
                child: state.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
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
      default:
        currentItems = state.referralHospitals;
        categoryName = 'Referral Hospitals';
        themeColor = const Color(0xFF4F46E5);
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
    // Apply local status filter (ALL, ACTIVE, INACTIVE)
    final filtered = items.where((i) {
      if (_statusFilter == 'ACTIVE' && !i.isActive) return false;
      if (_statusFilter == 'INACTIVE' && i.isActive) return false;
      return true;
    }).toList();

    final vm = ref.read(masterLookupProvider.notifier);
    final user = ref.read(authStateProvider).currentUser;
    final categoryColor = _getCategoryThemeColor(categoryIndex);

    final listWidget = filtered.isEmpty
        ? Center(
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
          )
        : ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = filtered[index];
              final isActive = item.isActive;
              final formattedTitle = _formatTitle(item.labelEn);
              final hasNepali = item.labelNe.isNotEmpty && item.labelNe != item.labelEn;

              return Card(
                elevation: 0,
                color: isActive ? Colors.white : const Color(0xFFF8FAFC),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isActive ? const Color(0xFFE2E8F0) : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
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

                      // Title, Nepali & Code Badge
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    formattedTitle,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: isActive ? const Color(0xFF1E293B) : Colors.grey.shade500,
                                      decoration: isActive ? null : TextDecoration.lineThrough,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
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
                              ],
                            ),
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
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

                      // Trailing Controls: Switch, Edit, Delete
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
                            onPressed: () => _showAddEditDialog(context, item, item.category),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.dangerRose),
                            tooltip: 'Delete Master Record',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _confirmDelete(context, item, adminUserId, deviceId),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );

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

  void _showAddEditDialog(BuildContext context, LookupItemModel? item, String category) {
    final isEditing = item != null;
    final enCtrl = TextEditingController(text: item?.labelEn ?? '');
    final neCtrl = TextEditingController(text: item?.labelNe ?? '');
    final codeCtrl = TextEditingController(text: item?.code ?? '');
    final user = ref.read(authStateProvider).currentUser;
    final deviceState = ref.read(deviceSecurityProvider);
    final vm = ref.read(masterLookupProvider.notifier);
    final singular = _getCategoryTitleSingular(category);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
                    : (category == 'medicine' ? Icons.medication_outlined : Icons.local_hospital_outlined),
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
                  code: sanitizedCode,
                  labelEn: enText,
                  labelNe: neCtrl.text.trim(),
                  isActive: true,
                  tenantId: user?.tenantId ?? 'tenant_default',
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
      ),
    );
  }

  void _confirmDelete(BuildContext context, LookupItemModel item, String adminUserId, String deviceId) {
    final vm = ref.read(masterLookupProvider.notifier);
    final user = ref.read(authStateProvider).currentUser;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.dangerRose, size: 24),
            SizedBox(width: 8),
            Text('Delete Master Item?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to permanently delete "${item.labelEn}"?',
              style: const TextStyle(fontWeight: FontWeight.w600),
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
              );
              if (mounted) {
                messenger.clearSnackBars();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Deactivated "${item.labelEn}" to preserve clinical history.'),
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
              );
              if (mounted) {
                messenger.clearSnackBars();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Deleted "${item.labelEn}".'),
                    backgroundColor: AppTheme.dangerRose,
                  ),
                );
              }
            },
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  String _getCategorySingularTitle(int idx) {
    switch (idx) {
      case 0:
        return 'Diagnosis';
      case 1:
        return 'Medicine';
      case 2:
      default:
        return 'Referral Hospital';
    }
  }

  String _getCategoryPluralTitle(int idx) {
    switch (idx) {
      case 0:
        return 'Diagnoses';
      case 1:
        return 'Medicines';
      case 2:
      default:
        return 'Referral Hospitals';
    }
  }

  String _getCategoryTitleSingular(String category) {
    switch (category) {
      case 'diagnosis':
        return 'Diagnosis';
      case 'medicine':
        return 'Medicine';
      case 'referral_hospital':
      default:
        return 'Referral Hospital';
    }
  }
}
