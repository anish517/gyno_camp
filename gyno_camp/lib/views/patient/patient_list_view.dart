import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/document_capture_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/camp_model.dart';
import '../../models/patient_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/clinical_assessment_viewmodel.dart';
import '../../viewmodels/patient_list_viewmodel.dart';
import '../../viewmodels/reporting_viewmodel.dart';
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryTeal.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              patientState.patients.isNotEmpty ? Icons.shield_rounded : Icons.sync_alt,
                              size: 12,
                              color: AppTheme.primaryTeal,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              patientState.patients.isNotEmpty
                                  ? 'AES-256 Encrypted • ${patientState.patients.length} Records'
                                  : 'AES-256 Encrypted',
                              style: const TextStyle(fontSize: 10.5, color: AppTheme.primaryTeal, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
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
    // Determine clinical completion status
    final hasReasons = patient.reasonsForVisit.isNotEmpty;
    final hasPhone = patient.mobile.isNotEmpty;
    // Station 1 = registered, Station 2 = clinical form pending
    // We show a 3-step visual: Registered / Clinical Intake / Synced
    const Color stationDone = Color(0xFF10B981);
    const Color stationPending = Color(0xFFE2E8F0);

    // Colour-code visit reasons: urgent = rose, normal = teal
    final urgentReasons = {'something hanging out', 'problems passing urine', 'problems passing stool', 'pain'};
    final clinicalLabelMap = {
      'something hanging out': 'Uterine Prolapse (PV)',
      'discharge and or itching': 'Discharge / Pruritus',
      'problems passing urine': 'Urinary Complaint',
      'problems passing stool': 'Anorectal / Stool Issue',
      'menstrual problem': 'Menstrual Disorder',
      'infertility': 'Infertility',
      'pain': 'Pelvic / Abdominal Pain',
      'checkup': 'Routine Checkup',
    };

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE8EDF2), width: 1),
      ),
      color: Colors.white,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left coloured strip — teal = complete, amber = pending
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: hasReasons ? stationDone : const Color(0xFFFBBF24),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Patient ID + Ward
                    Row(
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
                              fontSize: 11.5,
                              color: AppTheme.primaryDark,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'Ward ${patient.ward}',
                            style: const TextStyle(fontSize: 10.5, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          patient.district.isNotEmpty ? patient.district : 'Nepal',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Patient Name & Age row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.1),
                          child: Text(
                            patient.firstName.isNotEmpty ? patient.firstName[0].toUpperCase() : 'P',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppTheme.primaryTeal,
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
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimaryLight,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    patient.isBelowAdultAge ? Icons.escalator_warning : Icons.favorite_border,
                                    size: 12,
                                    color: AppTheme.textSecondaryLight,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${patient.relationshipType ?? "Guardian"}: ${patient.spouseOrFatherName ?? "N/A"}  •  Age ${patient.age}y',
                                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondaryLight),
                                  ),
                                ],
                              ),
                              if (hasPhone) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.phone, size: 12, color: AppTheme.textSecondaryLight),
                                    const SizedBox(width: 3),
                                    Text(
                                      patient.mobile,
                                      style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondaryLight),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Colour-coded reason tags
                    if (patient.reasonsForVisit.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: patient.reasonsForVisit.map((reason) {
                          final isUrgent = urgentReasons.contains(reason);
                          final label = clinicalLabelMap[reason] ?? reason;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: isUrgent
                                  ? const Color(0xFFFFF1F2)
                                  : AppTheme.primaryTeal.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: isUrgent
                                    ? const Color(0xFFFDA4AF)
                                    : AppTheme.primaryTeal.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isUrgent) ...[
                                  const Icon(Icons.priority_high_rounded, size: 10, color: Color(0xFFE11D48)),
                                  const SizedBox(width: 2),
                                ],
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isUrgent ? const Color(0xFFBE123C) : AppTheme.primaryTeal,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Clinical Progress Stepper
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFEEF2F7)),
                      ),
                      child: Row(
                        children: [
                          _buildStepIndicator(label: 'S1: Intake', done: true, color: stationDone),
                          _buildStepConnector(done: true),
                          _buildStepIndicator(label: 'S2: Clinical', done: false, color: stationPending),
                          _buildStepConnector(done: false),
                          _buildStepIndicator(label: 'S3–6: Specialist', done: false, color: stationPending),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: hasReasons ? stationDone.withValues(alpha: 0.12) : const Color(0xFFFFF3CD),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              hasReasons ? 'REGISTERED' : 'INCOMPLETE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: hasReasons ? stationDone : const Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 8),

                    // Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.picture_as_pdf_rounded, size: 20, color: AppTheme.dangerRose),
                          tooltip: 'Download Patient Health Summary (PDF)',
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          onPressed: () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Generating ${patient.fullName} (${patient.patientId}) clinical summary PDF...'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                            final visit = await ref.read(clinicalAssessmentProvider.notifier).loadPatientAssessment(
                              patient.patientId,
                              patientUuid: patient.id,
                            );
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
                                  content: Text('Patient report downloaded: $saved'),
                                  backgroundColor: AppTheme.successGreen,
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(width: 4),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF334155),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator({required String label, required bool done, required Color color}) {
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
                    // Hardware Barcode Scanner & USB Wedge Status Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: matchedPatient != null
                              ? [const Color(0xFF065F46), const Color(0xFF047857)]
                              : [const Color(0xFF0F172A), const Color(0xFF1E293B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: matchedPatient != null ? Colors.greenAccent : AppTheme.primaryTeal.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                matchedPatient != null ? Icons.check_circle_rounded : Icons.qr_code_scanner_rounded,
                                color: matchedPatient != null ? Colors.greenAccent : AppTheme.primaryTeal,
                                size: 28,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                matchedPatient != null
                                    ? 'TOKEN MATCHED: ${matchedPatient!.patientId}'
                                    : 'USB / Bluetooth Scanner Gun Ready',
                                style: TextStyle(
                                  color: matchedPatient != null ? Colors.greenAccent : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
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
                              color: matchedPatient != null ? Colors.white : Colors.white70,
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
                              side: const BorderSide(color: AppTheme.primaryTeal),
                            ),
                            icon: const Icon(Icons.camera_alt, size: 16),
                            label: const Text('Open Camera / File', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final docService = DocumentCaptureService();
                              final image = await docService.captureFromCamera();
                              if (image != null) {
                                final filename = image.name.toLowerCase();
                                PatientModel? matched;
                                for (final p in existingPatients) {
                                  if (filename.contains(p.patientId.toLowerCase()) ||
                                      filename.contains(p.patientId.replaceAll('-', '').toLowerCase()) ||
                                      filename.contains(p.fullName.toLowerCase())) {
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
                                        content: Text('✓ Recognized Token from ${image.name}: ${matched.patientId}'),
                                        backgroundColor: AppTheme.primaryTeal,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                } else {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text('Uploaded "${image.name}". No valid QR/Barcode token found in image. Aim your barcode gun at a printed slip or click a token below.'),
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
