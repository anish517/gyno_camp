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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(masterLookupProvider);
    final user = ref.watch(authStateProvider).currentUser;
    final deviceState = ref.watch(deviceSecurityProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinical Master Data & Formulary'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: [
            Tab(icon: const Icon(Icons.healing_outlined), text: 'Diagnoses (${state.diagnoses.length})'),
            Tab(icon: const Icon(Icons.medication_outlined), text: 'Medicines (${state.medicines.length})'),
            Tab(icon: const Icon(Icons.local_hospital_outlined), text: 'Hospitals (${state.referralHospitals.length})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text('Add ${_getCategorySingularTitle(_tabController.index)}'),
        backgroundColor: AppTheme.primaryTeal,
        onPressed: () => _showAddEditDialog(context, null, _getCategoryForIndex(_tabController.index)),
      ),
      body: Column(
        children: [
          // Search & Filter Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Search in ${_getCategoryPluralTitle(_tabController.index)} (English or Nepali)...',
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(masterLookupProvider.notifier).setSearchQuery('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onChanged: (val) {
                ref.read(masterLookupProvider.notifier).setSearchQuery(val);
              },
            ),
          ),
          const Divider(height: 1),

          // Tab Content
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildItemsList(context, state.filteredDiagnoses, user?.id ?? 'admin-user', deviceState.device?.deviceId ?? 'dev-admin'),
                      _buildItemsList(context, state.filteredMedicines, user?.id ?? 'admin-user', deviceState.device?.deviceId ?? 'dev-admin'),
                      _buildItemsList(context, state.filteredReferralHospitals, user?.id ?? 'admin-user', deviceState.device?.deviceId ?? 'dev-admin'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList(
    BuildContext context,
    List<LookupItemModel> items,
    String adminUserId,
    String deviceId,
  ) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            const Text('No items found.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final vm = ref.read(masterLookupProvider.notifier);
    final user = ref.read(authStateProvider).currentUser;

    return ListView.separated(
      padding: const EdgeInsets.all(16.0),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final isActive = item.isActive;

        return Card(
          elevation: isActive ? 1.5 : 0.5,
          color: isActive ? Colors.white : Colors.grey.shade100,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isActive ? AppTheme.primaryTeal.withValues(alpha: 0.3) : Colors.grey.shade300,
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isActive ? AppTheme.primaryTeal.withValues(alpha: 0.12) : Colors.grey.shade300,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isActive ? AppTheme.primaryTeal : Colors.grey,
                ),
              ),
            ),
            title: Text(
              item.labelEn,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                decoration: isActive ? null : TextDecoration.lineThrough,
                color: isActive ? Colors.black87 : Colors.grey,
              ),
            ),
            subtitle: item.labelNe.isNotEmpty
                ? Text(
                    item.labelNe,
                    style: TextStyle(
                      fontSize: 12,
                      color: isActive ? AppTheme.primaryDark : Colors.grey,
                    ),
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: isActive,
                  activeTrackColor: AppTheme.primaryTeal,
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
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Edit',
                  onPressed: () => _showAddEditDialog(context, item, item.category),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.dangerRose),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(context, item, adminUserId, deviceId),
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEditing ? 'Edit Item' : 'Add New ${_getCategoryTitleSingular(category)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: enCtrl,
              decoration: const InputDecoration(
                labelText: 'English Name / Term *',
                hintText: 'e.g. Polycystic Ovary Syndrome',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: neCtrl,
              decoration: const InputDecoration(
                labelText: 'Nepali Translation (नेपाली नाम)',
                hintText: 'e.g. पाठेघरको समस्या',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
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
        title: const Text('Delete Master Item?'),
        content: Text('Are you sure you want to permanently delete "${item.labelEn}"?\n\nTip: You can deactivate it instead to preserve historical records.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose),
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
