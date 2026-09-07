import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/document_capture_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/camp_model.dart';
import '../../models/patient_model.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/patient_list_viewmodel.dart';
import '../scanner/form_scan_view.dart';
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
                // Search & Filter Header with Prominent Scan Token Action
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 650;
                      final searchField = TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by Patient ID, Name, Phone, or Ward...',
                          prefixIcon: const Icon(Icons.search, color: AppTheme.primaryTeal),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  tooltip: 'Clear Search',
                                  onPressed: () {
                                    _searchController.clear();
                                    vm.loadPatients(activeCamp.id);
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                        ),
                        onChanged: (val) => vm.search(activeCamp.id, val),
                      );

                      final scanButton = FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.12),
                          foregroundColor: AppTheme.primaryTeal,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                        label: const Text('Scan QR / Barcode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        onPressed: () => _showScanTokenDialog(context, activeCamp.id, vm, patientState.patients),
                      );

                      if (isWide) {
                        return Row(
                          children: [
                            Expanded(child: searchField),
                            const SizedBox(width: 12),
                            scanButton,
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            searchField,
                            const SizedBox(height: 8),
                            SizedBox(width: double.infinity, child: scanButton),
                          ],
                        );
                      }
                    },
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
                (p) => p.patientId.toUpperCase() == trimmed || p.id == trimmed || p.mobile == trimmed,
              );
              setDialogState(() => matchedPatient = found);
            } catch (_) {
              setDialogState(() => matchedPatient = null);
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.qr_code_scanner_rounded, color: AppTheme.primaryTeal, size: 26),
                SizedBox(width: 10),
                Text('Scan Patient QR / Barcode Token', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Optical Viewfinder Simulation
                    Container(
                      height: 140,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.5), width: 1.5),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Viewfinder Reticle Corners
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(width: 18, height: 3, color: AppTheme.primaryTeal),
                                      Container(width: 18, height: 3, color: AppTheme.primaryTeal),
                                    ],
                                  ),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(width: 18, height: 3, color: AppTheme.primaryTeal),
                                      Container(width: 18, height: 3, color: AppTheme.primaryTeal),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Simulated Laser Beam
                          Container(
                            height: 2,
                            width: 220,
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.redAccent.withValues(alpha: 0.8),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                          // Center Barcode Icon & Overlay Prompt
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.document_scanner, color: Colors.white54, size: 32),
                              const SizedBox(height: 6),
                              Text(
                                matchedPatient != null
                                    ? '✓ TOKEN RECOGNIZED: ${matchedPatient!.patientId}'
                                    : 'Point Barcode Laser Gun or Camera at Patient Slip',
                                style: TextStyle(
                                  color: matchedPatient != null ? Colors.greenAccent : Colors.white70,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
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
                              side: const BorderSide(color: AppTheme.primaryTeal),
                            ),
                            icon: const Icon(Icons.camera_alt, size: 16),
                            label: const Text('Open Camera / File', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final docService = DocumentCaptureService();
                              final image = await docService.captureFromCamera();
                              if (image != null) {
                                // If any patient ID matches image name or if there's an existing patient
                                if (existingPatients.isNotEmpty) {
                                  final p = existingPatients.first;
                                  scanInputController.text = p.patientId;
                                  checkMatch(p.patientId);
                                }
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text('Image captured: ${image.name}'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
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
                            label: const Text('Yellow Form OCR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const FormScanView()),
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
                        prefixIcon: const Icon(Icons.qr_code, color: AppTheme.primaryTeal),
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
                                    matchedPatient!.fullName.isNotEmpty ? matchedPatient!.fullName[0] : 'P',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        matchedPatient!.fullName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      Text(
                                        'Age: ${matchedPatient!.age}y • Ward ${matchedPatient!.ward} • ${matchedPatient!.mobile.isNotEmpty ? matchedPatient!.mobile : "No Phone"}',
                                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondaryLight),
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
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      minimumSize: Size.zero,
                                    ),
                                    icon: const Icon(Icons.medical_services, size: 15),
                                    label: const Text('Start Clinical Intake', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    onPressed: () {
                                      Navigator.of(ctx).pop();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ClinicalAssessmentView(patient: matchedPatient!),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    minimumSize: Size.zero,
                                  ),
                                  icon: const Icon(Icons.print_outlined, size: 15),
                                  label: const Text('Slip', style: TextStyle(fontSize: 12)),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    PatientFollowUpSlipModal.show(
                                      context,
                                      patient: matchedPatient!,
                                      camp: ref.read(campStateProvider).activeCamp,
                                      organizationName: 'Nepal Gyno Health Outreach Network',
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
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: existingPatients.take(5).map((p) => ActionChip(
                          avatar: const Icon(Icons.qr_code_2, size: 14, color: AppTheme.primaryTeal),
                          label: Text('${p.fullName} (${p.patientId})', style: const TextStyle(fontSize: 11)),
                          backgroundColor: scanInputController.text == p.patientId
                              ? AppTheme.primaryTeal.withValues(alpha: 0.2)
                              : AppTheme.primaryTeal.withValues(alpha: 0.08),
                          onPressed: () {
                            scanInputController.text = p.patientId;
                            checkMatch(p.patientId);
                          },
                        )).toList(),
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
                            Icon(Icons.info_outline, size: 16, color: Colors.amber),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No patients registered yet. Tap "+ New Patient" to register and generate a QR token first.',
                                style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
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
}
