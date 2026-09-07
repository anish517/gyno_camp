import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../models/camp_model.dart';
import '../../models/patient_model.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/patient_list_viewmodel.dart';
import 'clinical_assessment_view.dart';
import 'patient_follow_up_slip_modal.dart';
import 'patient_registration_view.dart';

class PatientListView extends ConsumerStatefulWidget {
  final String? initialQuery;
  const PatientListView({super.key, this.initialQuery});

  @override
  ConsumerState<PatientListView> createState() => _PatientListViewState();
}

class _PatientListViewState extends ConsumerState<PatientListView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeCamp = ref.read(campStateProvider).activeCamp;
      if (activeCamp != null) {
        if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
          _searchController.text = widget.initialQuery!.trim();
          ref.read(patientListProvider.notifier).search(activeCamp.id, widget.initialQuery!.trim());
        } else {
          ref.read(patientListProvider.notifier).loadPatients(activeCamp.id);
        }
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final campState = ref.watch(campStateProvider);
    final patientState = ref.watch(patientListProvider);
    final vm = ref.read(patientListProvider.notifier);
    final activeCamp = campState.activeCamp;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Camp Patient Roll'),
            if (activeCamp != null)
              Text(
                '${activeCamp.name} (${activeCamp.campCode})',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Patient List',
            onPressed: activeCamp == null
                ? null
                : () => vm.loadPatients(activeCamp.id),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryTeal,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('New Patient', style: TextStyle(color: Colors.white)),
        onPressed: activeCamp == null
            ? null
            : () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PatientRegistrationView()),
                );
                if (mounted) {
                  vm.loadPatients(activeCamp.id);
                }
              },
      ),
      body: activeCamp == null
          ? const Center(
              child: Text('No active camp selected. Please activate a camp first.'),
            )
          : Column(
              children: [
                // Search & Filter Header
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by Patient ID, Name, Phone, or Ward...',
                      prefixIcon: const Icon(Icons.search, color: AppTheme.primaryTeal),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                vm.loadPatients(activeCamp.id);
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    ),
                    onChanged: (val) => vm.search(activeCamp.id, val),
                  ),
                ),
                const Divider(height: 1),

                // Patient Roll Statistics Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppTheme.backgroundLight,
                  child: Row(
                    children: [
                      Text(
                        'Total Registered: ${patientState.patients.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimaryLight),
                      ),
                      const Spacer(),
                      const Icon(Icons.sync_alt, size: 14, color: AppTheme.textSecondaryLight),
                      const SizedBox(width: 4),
                      const Text('Local SQLite Encrypted', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight)),
                    ],
                  ),
                ),

                // Patient Cards List
                Expanded(
                  child: patientState.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : patientState.patients.isEmpty
                          ? _buildEmptyState(context, activeCamp.id, vm)
                          : RefreshIndicator(
                              onRefresh: () => vm.loadPatients(activeCamp.id),
                              child: ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: patientState.patients.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final patient = patientState.patients[index];
                                  return _buildPatientCard(context, patient, activeCamp, vm);
                                },
                              ),
                            ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String campId, PatientListViewModel vm) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No Patients Found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimaryLight),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isNotEmpty
                  ? 'No patient matched query "${_searchController.text}".'
                  : 'Start registering patients at this camp station using the button below.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondaryLight),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text('Register Patient Now'),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PatientRegistrationView()),
                );
                if (mounted) {
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
  ) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppTheme.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Patient ID Badge & Ward
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    patient.patientId,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                ),
                Text(
                  'Ward ${patient.ward} • ${patient.district.isNotEmpty ? patient.district : "Nepal"}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Patient Name & Age
            Text(
              patient.fullName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimaryLight),
            ),
            const SizedBox(height: 4),

            // Relative & Mobile Details
            Row(
              children: [
                Icon(
                  patient.isBelowAdultAge ? Icons.escalator_warning : Icons.favorite_border,
                  size: 14,
                  color: AppTheme.textSecondaryLight,
                ),
                const SizedBox(width: 4),
                Text(
                  '${patient.relationshipType ?? "Guardian"}: ${patient.spouseOrFatherName ?? "N/A"}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.phone, size: 14, color: AppTheme.textSecondaryLight),
                const SizedBox(width: 4),
                Text(
                  patient.mobile.isNotEmpty ? patient.mobile : 'No Phone',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
                ),
                const Spacer(),
                Text(
                  'Age: ${patient.age}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryTeal),
                ),
              ],
            ),

            if (patient.reasonsForVisit.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: patient.reasonsForVisit.map((reason) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Text(reason, style: const TextStyle(fontSize: 10, color: AppTheme.textPrimaryLight)),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Action Buttons: Follow-up Slip (QR) & Open Clinical Intake Form
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 16, color: AppTheme.primaryTeal),
                  label: const Text('Slip / QR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    final proceed = await PatientFollowUpSlipModal.show(
                      context,
                      patient: patient,
                      camp: activeCamp,
                      organizationName: activeCamp?.organizationName.isNotEmpty == true
                          ? activeCamp!.organizationName
                          : 'Nepal Gyno Health Outreach Network',
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
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.assignment, size: 16),
                  label: const Text('Clinical Intake', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ClinicalAssessmentView(patient: patient),
                      ),
                    );
                    if (mounted && activeCamp != null) {
                      vm.loadPatients(activeCamp.id);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
