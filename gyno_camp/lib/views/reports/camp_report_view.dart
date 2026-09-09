import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../models/camp_report_summary_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../../viewmodels/reporting_viewmodel.dart';
import '../../viewmodels/patient_list_viewmodel.dart';
import '../../viewmodels/patient_registration_viewmodel.dart';

class CampReportView extends ConsumerStatefulWidget {
  final String? initialCampId;

  const CampReportView({super.key, this.initialCampId});

  @override
  ConsumerState<CampReportView> createState() => _CampReportViewState();
}

class _CampReportViewState extends ConsumerState<CampReportView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _patientSearchController = TextEditingController();
  String? _exportingPatientId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeCamp = ref.read(campStateProvider).activeCamp;
      final targetCampId = widget.initialCampId ?? activeCamp?.id;
      ref.read(reportingViewModelProvider.notifier).loadSummary(campId: targetCampId);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _patientSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reportState = ref.watch(reportingViewModelProvider);
    final reportVm = ref.read(reportingViewModelProvider.notifier);
    final campState = ref.watch(campStateProvider);
    final authState = ref.watch(authStateProvider);
    final deviceState = ref.watch(deviceSecurityProvider);

    final user = authState.currentUser;
    final deviceId = deviceState.device?.deviceId ?? 'dev-field';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Camp Clinical Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh Analytics',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              reportVm.loadSummary(campId: reportState.selectedCampId);
            },
          ),
        ],
      ),
      body: reportState.isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.primaryTeal),
                  SizedBox(height: 16),
                  Text('Aggregating clinical camp records...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Camp Selector & Export Bar
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, color: AppTheme.primaryTeal),
                              const SizedBox(width: 8),
                              const Text(
                                'Select Camp Target:',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: reportState.selectedCampId,
                                    hint: const Text('All Camp Records'),
                                    items: [
                                      const DropdownMenuItem<String>(
                                        value: null,
                                        child: Text('All Camp Records (समग्र क्याम्प)'),
                                      ),
                                      ...campState.camps.map(
                                        (c) => DropdownMenuItem<String>(
                                          value: c.id,
                                          child: Text('${c.campCode} - ${c.name}'),
                                        ),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      reportVm.loadSummary(campId: val);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          // Export Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryTeal,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  icon: reportState.isExportingPdf
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.picture_as_pdf),
                                  label: Text(
                                    reportState.isExportingPdf
                                        ? 'Generating PDF...'
                                        : 'Export PDF (पिडिएफ)',
                                  ),
                                  onPressed: reportState.isExportingPdf || reportState.isExportingExcel
                                      ? null
                                      : () {
                                          reportVm.exportPdf(
                                            userId: user?.id ?? 'usr-analyst',
                                            userName: user?.name ?? 'Data Analyst',
                                            userRole: user?.role.toDbString() ?? 'DATA_ANALYST',
                                            deviceId: deviceId,
                                          );
                                        },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  icon: reportState.isExportingExcel
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.table_view, color: AppTheme.successGreen),
                                  label: Text(
                                    reportState.isExportingExcel
                                        ? 'Generating Excel...'
                                        : 'Export Excel (एक्सेल)',
                                  ),
                                  onPressed: reportState.isExportingPdf || reportState.isExportingExcel
                                      ? null
                                      : () {
                                          reportVm.exportExcel(
                                            userId: user?.id ?? 'usr-analyst',
                                            userName: user?.name ?? 'Data Analyst',
                                            userRole: user?.role.toDbString() ?? 'DATA_ANALYST',
                                            deviceId: deviceId,
                                          );
                                        },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Success / Error Feedback Banner
                  if (reportState.successMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.successGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.successGreen),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: AppTheme.successGreen),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  reportState.successMessage!,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.successGreen,
                                    fontSize: 13,
                                  ),
                                ),
                                if (reportState.lastExportPath != null)
                                  Text(
                                    'Saved: ${reportState.lastExportPath}',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => reportVm.clearFeedback(),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (reportState.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerRose.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.dangerRose),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppTheme.dangerRose),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              reportState.errorMessage!,
                              style: const TextStyle(color: AppTheme.dangerRose, fontSize: 13),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => reportVm.clearFeedback(),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // 2. Executive KPI Cards
                  if (reportState.summary != null) ...[
                    _buildExecutiveKpis(reportState.summary!),
                    const SizedBox(height: 16),

                    // 3. Tabbed Detailed Analysis
                    Card(
                      elevation: 2,
                      child: Column(
                        children: [
                          TabBar(
                            controller: _tabController,
                            labelColor: AppTheme.primaryTeal,
                            unselectedLabelColor: AppTheme.textSecondaryLight,
                            indicatorColor: AppTheme.primaryTeal,
                            tabs: const [
                              Tab(icon: Icon(Icons.people), text: 'Demographics'),
                              Tab(icon: Icon(Icons.healing), text: 'POP Staging'),
                              Tab(icon: Icon(Icons.medication), text: 'Diagnoses'),
                              Tab(icon: Icon(Icons.local_hospital), text: 'Treatment'),
                              Tab(icon: Icon(Icons.folder_shared_rounded), text: 'Patient Records'),
                            ],
                          ),
                          SizedBox(
                            height: 380,
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                _buildDemographicsTab(reportState.summary!),
                                _buildPopStagingTab(reportState.summary!),
                                _buildDiagnosesTab(reportState.summary!),
                                _buildTreatmentTab(reportState.summary!),
                                _buildPatientRecordsTab(reportState.selectedCampId ?? campState.activeCamp?.id),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(child: Text('No patient records found for the selected camp.')),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildExecutiveKpis(CampReportSummaryModel summary) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            title: 'Registered',
            value: '${summary.totalPatientsRegistered}',
            subtitle: 'Total Patients',
            color: AppTheme.primaryTeal,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricTile(
            title: 'Examined',
            value: '${summary.totalVisitsRecorded}',
            subtitle: 'Yellow Forms',
            color: AppTheme.accentCyan,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricTile(
            title: 'POP Stage >= 2',
            value: '${summary.significantPopPercentage}%',
            subtitle: '${summary.significantPopCount} Significant',
            color: AppTheme.warningAmber,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricTile(
            title: 'Referrals',
            value: '${summary.totalSurgicalReferrals}',
            subtitle: 'Surgical Cases',
            color: AppTheme.dangerRose,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 9, color: AppTheme.textSecondaryLight),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemographicsTab(CampReportSummaryModel summary) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Age Group Distribution', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...summary.ageGroups.entries.map((e) {
          final pct = summary.totalPatientsRegistered > 0
              ? (e.value / summary.totalPatientsRegistered)
              : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Age ${e.key}: ${e.value} patients'),
                    Text('${(pct * 100).toStringAsFixed(1)}%'),
                  ],
                ),
                const SizedBox(height: 2),
                LinearProgressIndicator(
                  value: pct,
                  backgroundColor: AppTheme.borderLight,
                  color: AppTheme.primaryTeal,
                ),
              ],
            ),
          );
        }),
        const Divider(height: 24),
        const Text('Marital Status Distribution', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: summary.maritalStatusCounts.entries.map((e) {
            return Chip(
              label: Text('${e.key.toUpperCase()}: ${e.value}'),
              backgroundColor: AppTheme.primaryLight,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPopStagingTab(CampReportSummaryModel summary) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.warningAmber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Clinically Significant Prolapse (Stage >= 2): ${summary.significantPopCount} of ${summary.totalVisitsRecorded} patients (${summary.significantPopPercentage}%)',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.brown),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Highest POP Stage (Baden-Walker / POP-Q)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...summary.highestPopStages.entries.map((e) {
          final label = e.key == 0 ? 'Stage 0 (Normal / No Prolapse)' : 'Stage ${e.key}';
          final pct = summary.totalVisitsRecorded > 0 ? (e.value / summary.totalVisitsRecorded) : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text(label, style: const TextStyle(fontSize: 12))),
                Expanded(
                  flex: 4,
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: AppTheme.borderLight,
                    color: e.key >= 2 ? AppTheme.warningAmber : AppTheme.successGreen,
                  ),
                ),
                const SizedBox(width: 8),
                Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          );
        }),
        const Divider(height: 24),
        const Text('Compartment Prolapse Frequency (Stage >= 1)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Anterior (Cystocele): ${(summary.anteriorStages[1] ?? 0) + (summary.anteriorStages[2] ?? 0) + (summary.anteriorStages[3] ?? 0)} cases'),
        Text('Middle (Uterine/Apex): ${(summary.middleStages[1] ?? 0) + (summary.middleStages[2] ?? 0) + (summary.middleStages[3] ?? 0) + (summary.middleStages[4] ?? 0)} cases'),
        Text('Posterior (Rectocele): ${(summary.posteriorStages[1] ?? 0) + (summary.posteriorStages[2] ?? 0) + (summary.posteriorStages[3] ?? 0)} cases'),
      ],
    );
  }

  Widget _buildDiagnosesTab(CampReportSummaryModel summary) {
    return summary.diagnosisCounts.isEmpty
        ? const Center(child: Text('No diagnoses recorded yet.'))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Ranked Pathologies Identified', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...summary.diagnosisCounts.entries.map((e) {
                final pct = summary.totalVisitsRecorded > 0
                    ? ((e.value / summary.totalVisitsRecorded) * 100).toStringAsFixed(1)
                    : '0.0';
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: AppTheme.primaryLight,
                    child: Text('${e.value}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w500)),
                  trailing: Text('$pct%', style: const TextStyle(color: AppTheme.textSecondaryLight)),
                );
              }),
            ],
          );
  }

  Widget _buildTreatmentTab(CampReportSummaryModel summary) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Interventions & Referrals', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('• Pessaries Fitted: ${summary.totalPessariesInserted} patients'),
        if (summary.pessaryCounts.isNotEmpty)
          ...summary.pessaryCounts.entries.map((e) => Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text('- ${e.key}: ${e.value}', style: const TextStyle(fontSize: 12)),
              )),
        Text('• Pelvic Floor Exercises: ${summary.pelvicFloorCounselingCount} counseled'),
        Text('• Surgical Referrals: ${summary.totalSurgicalReferrals} patients'),
        if (summary.surgicalReferralCounts.isNotEmpty)
          ...summary.surgicalReferralCounts.entries.map((e) => Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text('- ${e.key}: ${e.value}', style: const TextStyle(fontSize: 12)),
              )),
        const Divider(height: 24),
        const Text('Prescribed Medications Dispensed', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (summary.medicationDispensedCounts.isEmpty)
          const Text('No medications dispensed', style: TextStyle(color: AppTheme.textSecondaryLight))
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: summary.medicationDispensedCounts.entries.map((e) {
              return Chip(
                label: Text('${e.key}: ${e.value}'),
                backgroundColor: AppTheme.accentCyan.withValues(alpha: 0.15),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildPatientRecordsTab(String? campId) {
    final patientState = ref.watch(patientListProvider);
    final user = ref.watch(authStateProvider).currentUser;
    final deviceState = ref.watch(deviceSecurityProvider);
    final campState = ref.watch(campStateProvider);

    if (campId != null &&
        (!patientState.hasLoaded || patientState.loadedCampId != campId) &&
        !patientState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(patientListProvider.notifier).loadPatients(campId);
      });
    }

    final query = _patientSearchController.text.trim().toLowerCase();
    final patients = patientState.patients.where((p) {
      if (query.isEmpty) return true;
      return p.fullName.toLowerCase().contains(query) ||
          p.patientId.toLowerCase().contains(query) ||
          p.mobile.contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _patientSearchController,
            decoration: InputDecoration(
              hintText: 'Search patients in this camp by name or ID...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _patientSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => setState(() => _patientSearchController.clear()),
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: patients.isEmpty
              ? Center(
                  child: Text(
                    patientState.isLoading
                        ? 'Loading patients...'
                        : 'No patient records found.',
                    style: const TextStyle(color: AppTheme.textSecondaryLight),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: patients.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final patient = patients[index];
                    final isExporting = _exportingPatientId == patient.patientId;

                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.15),
                        child: Text(
                          patient.firstName.isNotEmpty ? patient.firstName[0].toUpperCase() : 'P',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryTeal, fontSize: 13),
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(patient.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              patient.patientId,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        'Age: ${patient.age}y • Ward: ${patient.ward} • Mobile: ${patient.mobile.isNotEmpty ? patient.mobile : "N/A"}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                      ),
                      trailing: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        icon: isExporting
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.picture_as_pdf, size: 14),
                        label: Text(
                          isExporting ? 'Exporting...' : 'PDF Dossier',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        onPressed: isExporting
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                setState(() => _exportingPatientId = patient.patientId);
                                try {
                                  final visit = await ref.read(patientRepositoryProvider).getLatestClinicalVisit(
                                        patient.patientId,
                                        patientUuid: patient.id,
                                      );
                                  final targetCamp = campState.selectedCamp ??
                                      campState.activeCamp ??
                                      (campState.camps.isNotEmpty
                                          ? campState.camps.firstWhere((c) => c.id == patient.campId, orElse: () => campState.camps.first)
                                          : null);

                                  final saved = await ref.read(reportingViewModelProvider.notifier).exportIndividualPatientPdf(
                                        patient: patient,
                                        visit: visit,
                                        camp: targetCamp,
                                        userId: user?.id ?? 'usr-analyst',
                                        userName: user?.name ?? 'Data Analyst',
                                        userRole: user?.role.toDbString() ?? 'DATA_ANALYST',
                                        deviceId: deviceState.device?.deviceId ?? 'dev-field',
                                      );
                                  if (mounted && saved != null) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        backgroundColor: AppTheme.primaryTeal,
                                        content: Text('Saved dossier: $saved'),
                                        duration: const Duration(seconds: 4),
                                      ),
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => _exportingPatientId = null);
                                }
                              },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
