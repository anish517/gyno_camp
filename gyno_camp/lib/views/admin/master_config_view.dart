import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../models/lookup_item_model.dart';
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

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: const Color(0xFF0F766E),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dataset_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Clinical Master Data & Formulary',
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
                    '$totalEntities Entities',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Standardized clinical terminology, prescription formulary & hospital referral directory',
              style: TextStyle(color: Color(0xFFCCFBF1), fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
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
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            width: double.infinity,
            color: const Color(0xFF042F2E),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                  icon: const Icon(Icons.healing_outlined, size: 18),
                  text: 'Diagnoses (${state.diagnoses.length})',
                ),
                Tab(
                  icon: const Icon(Icons.medication_outlined, size: 18),
                  text: 'Medicines (${state.medicines.length})',
                ),
                Tab(
                  icon: const Icon(Icons.local_hospital_outlined, size: 18),
                  text: 'Hospitals (${state.referralHospitals.length})',
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text('Add ${_getCategorySingularTitle(_tabController.index)}'),
        backgroundColor: AppTheme.primaryTeal,
        onPressed: () => _showAddEditDialog(context, null, _getCategoryForIndex(_tabController.index)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              // Search & Filter Toolbar Card
              Container(
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
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

                    // Filter Chips & Category Subtitle Row
                    Row(
                      children: [
                        _buildStatusChip('ALL', 'All Items'),
                        const SizedBox(width: 8),
                        _buildStatusChip('ACTIVE', 'Active Only'),
                        const SizedBox(width: 8),
                        _buildStatusChip('INACTIVE', 'Disabled'),
                        const Spacer(),
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
        Text(
          text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
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

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isNotEmpty
                  ? 'No ${_getCategoryPluralTitle(categoryIndex)} match "${_searchController.text}".'
                  : 'No items found for the selected filter.',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            if (_searchController.text.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.clear, size: 14),
                label: const Text('Clear Search'),
                onPressed: () {
                  _searchController.clear();
                  ref.read(masterLookupProvider.notifier).setSearchQuery('');
                },
              ),
          ],
        ),
      );
    }

    final vm = ref.read(masterLookupProvider.notifier);
    final user = ref.read(authStateProvider).currentUser;
    final categoryColor = _getCategoryThemeColor(categoryIndex);

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
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
              color: isActive ? Colors.grey.shade200 : Colors.grey.shade300,
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
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
            child: Row(
              children: [
                // Leading Index Number Badge
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isActive ? categoryColor.withValues(alpha: 0.1) : Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isActive ? categoryColor : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Title, Nepali Translation & Category Tag
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              formattedTitle,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                decoration: isActive ? null : TextDecoration.lineThrough,
                                color: isActive ? AppTheme.primaryDark : Colors.grey.shade600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Status Pill Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isActive ? const Color(0xFFECFDF5) : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isActive ? const Color(0xFFA7F3D0) : Colors.grey.shade300,
                              ),
                            ),
                            child: Text(
                              isActive ? 'Active' : 'Disabled',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: isActive ? const Color(0xFF059669) : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (hasNepali)
                            Text(
                              item.labelNe,
                              style: TextStyle(
                                fontSize: 12,
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
                          const SizedBox(width: 10),
                          Text(
                            '•  Code: ${item.code}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Trailing Controls: Switch, Edit, Delete
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: isActive,
                      activeTrackColor: categoryColor,
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
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      color: AppTheme.primaryDark,
                      tooltip: 'Edit Master Record',
                      onPressed: () => _showAddEditDialog(context, item, item.category),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 19, color: AppTheme.dangerRose),
                      tooltip: 'Delete Master Record',
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
  }

  void _showAddEditDialog(BuildContext context, LookupItemModel? item, String category) {
    final isEditing = item != null;
    final enCtrl = TextEditingController(text: item?.labelEn ?? '');
    final neCtrl = TextEditingController(text: item?.labelNe ?? '');
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
        content: SizedBox(
          width: 480,
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
            ],
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please provide an English label.')),
                );
                return;
              }

              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              if (isEditing) {
                final updated = item.copyWith(
                  labelEn: enText,
                  labelNe: neCtrl.text.trim(),
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
                  code: enText.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_'),
                  labelEn: enText,
                  labelNe: neCtrl.text.trim(),
                  isActive: true,
                );
                await vm.addItem(
                  newItem,
                  userId: user?.id ?? 'admin-user',
                  userName: user?.name ?? 'Super Admin',
                  deviceId: deviceState.device?.deviceId ?? 'dev-admin',
                );
              }

              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Saved "$enText" successfully.')),
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
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.dangerRose, size: 24),
            const SizedBox(width: 8),
            const Text('Delete Master Item?'),
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
                messenger.showSnackBar(
                  SnackBar(content: Text('Deactivated "${item.labelEn}" to preserve clinical history.')),
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
                messenger.showSnackBar(
                  SnackBar(content: Text('Deleted "${item.labelEn}".')),
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
        return 'Hospital';
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
        return 'Hospital';
    }
  }
}
