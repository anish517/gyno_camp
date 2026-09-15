import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../models/camp_report_summary_model.dart';
import '../../models/patient_model.dart';
import '../../models/user_model.dart';
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
      final campState = ref.read(campStateProvider);
      final activeCamp = campState.activeCamp ?? (campState.camps.isNotEmpty ? campState.camps.first : null);
      final targetCampId = widget.initialCampId ?? activeCamp?.id;
      ref.read(reportingViewModelProvider.notifier).loadSummary(campId: targetCampId);
      if (targetCampId != null) {
        ref.read(patientListProvider.notifier).loadPatients(targetCampId);
      }
      if (campState.camps.isEmpty) {
        ref.read(campStateProvider.notifier).loadCamps();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _patientSearchController.dispose();
    super.dispose();
  }

  void _onCampChanged(String? campId) {
    ref.read(reportingViewModelProvider.notifier).loadSummary(campId: campId);
    final campState = ref.read(campStateProvider);
    final targetCampId = campId ??
        campState.activeCamp?.id ??
        (campState.camps.isNotEmpty ? campState.camps.first.id : null);
    if (targetCampId != null) {
      ref.read(patientListProvider.notifier).loadPatients(targetCampId);
    }
  }

  void _onRefresh() {
    final reportState = ref.read(reportingViewModelProvider);
    final campState = ref.read(campStateProvider);
    final currentCampId = reportState.selectedCampId;
    ref.read(reportingViewModelProvider.notifier).loadSummary(campId: currentCampId);
    final targetCampId = currentCampId ??
        campState.activeCamp?.id ??
        (campState.camps.isNotEmpty ? campState.camps.first.id : null);
    if (targetCampId != null) {
      ref.read(patientListProvider.notifier).loadPatients(targetCampId);
    }
  }

  void _exportPdf(UserModel? user, String deviceId) {
    ref.read(reportingViewModelProvider.notifier).exportPdf(
      userId: user?.id ?? 'usr-analyst',
      userName: user?.name ?? 'Data Analyst',
      userRole: user?.role.toDbString() ?? 'DATA_ANALYST',
      deviceId: deviceId,
    );
  }

  void _exportExcel(UserModel? user, String deviceId) {
    ref.read(reportingViewModelProvider.notifier).exportExcel(
      userId: user?.id ?? 'usr-analyst',
      userName: user?.name ?? 'Data Analyst',
      userRole: user?.role.toDbString() ?? 'DATA_ANALYST',
      deviceId: deviceId,
    );
  }

  Future<void> _exportIndividualPatientPdf(
    PatientModel patient,
    CampState campState,
    UserModel? user,
    DeviceSecurityState deviceState,
  ) async {
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
        title: const Text(
          'Camp Clinical Reports',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Analytics',
            icon: const Icon(Icons.refresh),
            onPressed: _onRefresh,
          ),
        ],
      ),
      body: (reportState.isLoading && reportState.summary == null)
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.primaryTeal),
                  SizedBox(height: 16),
                  Text(
                    'Aggregating clinical camp records...',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Non-destructive smooth progress indicator during camp reload or refresh
                      if (reportState.isLoading)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.all(Radius.circular(4)),
                            child: LinearProgressIndicator(
                              color: AppTheme.primaryTeal,
                              backgroundColor: AppTheme.primaryLight,
                              minHeight: 4,
                            ),
                          ),
                        ),

                      // 1. Camp Selector & Export Bar
                      _buildCampSelectorAndExportBar(
                        reportState: reportState,
                        campState: campState,
                        user: user,
                        deviceId: deviceId,
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
                                    if (reportState.lastExportPath != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Saved: ${reportState.lastExportPath}',
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isCompact = constraints.maxWidth < 600;
                              final tabHeight = isCompact ? 460.0 : 540.0;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).cardColor,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                      border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
                                    ),
                                    child: TabBar(
                                      controller: _tabController,
                                      isScrollable: isCompact,
                                      tabAlignment: isCompact ? TabAlignment.start : TabAlignment.fill,
                                      labelColor: AppTheme.primaryTeal,
                                      unselectedLabelColor: AppTheme.textSecondaryLight,
                                      indicatorColor: AppTheme.primaryTeal,
                                      indicatorWeight: 3,
                                      tabs: const [
                                        Tab(icon: Icon(Icons.people), text: 'Demographics'),
                                        Tab(icon: Icon(Icons.healing), text: 'POP Staging'),
                                        Tab(icon: Icon(Icons.medication), text: 'Diagnoses'),
                                        Tab(icon: Icon(Icons.local_hospital), text: 'Treatment'),
                                        Tab(icon: Icon(Icons.folder_shared_rounded), text: 'Patient Records'),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    height: tabHeight,
                                    child: TabBarView(
                                      controller: _tabController,
                                      children: [
                                        _buildDemographicsTab(reportState.summary!),
                                        _buildPopStagingTab(reportState.summary!),
                                        _buildDiagnosesTab(reportState.summary!),
                                        _buildTreatmentTab(reportState.summary!),
                                        _buildPatientRecordsTab(
                                          reportState.selectedCampId ?? campState.activeCamp?.id,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ] else ...[
                        const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(
                            child: Text(
                              'No patient records found for the selected camp.',
                              style: TextStyle(color: AppTheme.textSecondaryLight),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCampSelectorAndExportBar({
    required ReportingState reportState,
    required CampState campState,
    required UserModel? user,
    required String deviceId,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 640;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Target Camp Selection
                if (isCompact) ...[
                  const Row(
                    children: [
                      Icon(Icons.location_on_outlined, color: AppTheme.primaryTeal, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Select Camp Target:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.borderLight),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: reportState.selectedCampId,
                        hint: const Text('All Camp Records (समग्र क्याम्प)'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('All Camp Records (समग्र क्याम्प)', overflow: TextOverflow.ellipsis),
                          ),
                          ...campState.camps.map(
                            (c) => DropdownMenuItem<String>(
                              value: c.id,
                              child: Text('${c.campCode} - ${c.name}', overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                        onChanged: _onCampChanged,
                      ),
                    ),
                  ),
                ] else ...[
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
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.borderLight),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: reportState.selectedCampId,
                              hint: const Text('All Camp Records (समग्र क्याम्प)'),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('All Camp Records (समग्र क्याम्प)', overflow: TextOverflow.ellipsis),
                                ),
                                ...campState.camps.map(
                                  (c) => DropdownMenuItem<String>(
                                    value: c.id,
                                    child: Text('${c.campCode} - ${c.name}', overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                              ],
                              onChanged: _onCampChanged,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const Divider(height: 24),
                // Export Action Buttons
                if (isCompact) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: reportState.isExportingPdf
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.picture_as_pdf),
                        label: Text(
                          reportState.isExportingPdf ? 'Generating PDF...' : 'Export PDF (पिडिएफ)',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: reportState.isExportingPdf || reportState.isExportingExcel
                            ? null
                            : () => _exportPdf(user, deviceId),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: reportState.isExportingExcel
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.table_view, color: AppTheme.successGreen),
                        label: Text(
                          reportState.isExportingExcel ? 'Generating Excel...' : 'Export Excel (एक्सेल)',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: reportState.isExportingPdf || reportState.isExportingExcel
                            ? null
                            : () => _exportExcel(user, deviceId),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryTeal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: reportState.isExportingPdf
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.picture_as_pdf),
                          label: Text(
                            reportState.isExportingPdf ? 'Generating PDF...' : 'Export PDF (पिडिएफ)',
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: reportState.isExportingPdf || reportState.isExportingExcel
                              ? null
                              : () => _exportPdf(user, deviceId),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: reportState.isExportingExcel
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.table_view, color: AppTheme.successGreen),
                          label: Text(
                            reportState.isExportingExcel ? 'Generating Excel...' : 'Export Excel (एक्सेल)',
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: reportState.isExportingPdf || reportState.isExportingExcel
                              ? null
                              : () => _exportExcel(user, deviceId),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExecutiveKpis(CampReportSummaryModel summary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        if (isMobile) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      title: 'Registered',
                      value: '${summary.totalPatientsRegistered}',
                      subtitle: 'Total Patients',
                      color: AppTheme.primaryTeal,
                      icon: Icons.people_outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricTile(
                      title: 'Examined',
                      value: '${summary.totalVisitsRecorded}',
                      subtitle: 'Yellow Forms',
                      color: AppTheme.accentCyan,
                      icon: Icons.assignment_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      title: 'POP Stage >= 2',
                      value: '${summary.significantPopPercentage}%',
                      subtitle: '${summary.significantPopCount} Significant',
                      color: AppTheme.warningAmber,
                      icon: Icons.warning_amber_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricTile(
                      title: 'Referrals',
                      value: '${summary.totalSurgicalReferrals}',
                      subtitle: 'Surgical Cases',
                      color: AppTheme.dangerRose,
                      icon: Icons.local_hospital_outlined,
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Registered',
                value: '${summary.totalPatientsRegistered}',
                subtitle: 'Total Patients',
                color: AppTheme.primaryTeal,
                icon: Icons.people_outline,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'Examined',
                value: '${summary.totalVisitsRecorded}',
                subtitle: 'Yellow Forms',
                color: AppTheme.accentCyan,
                icon: Icons.assignment_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'POP Stage >= 2',
                value: '${summary.significantPopPercentage}%',
                subtitle: '${summary.significantPopCount} Significant',
                color: AppTheme.warningAmber,
                icon: Icons.warning_amber_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'Referrals',
                value: '${summary.totalSurgicalReferrals}',
                subtitle: 'Surgical Cases',
                color: AppTheme.dangerRose,
                icon: Icons.local_hospital_outlined,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    IconData? icon,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 4),
            ],
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 9.5, color: AppTheme.textSecondaryLight),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
        const Text(
          'Age Group Distribution',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
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
                    Expanded(
                      child: Text(
                        'Age ${e.key}: ${e.value} patients',
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${(pct * 100).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: AppTheme.borderLight,
                    color: AppTheme.primaryTeal,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          );
        }),
        const Divider(height: 24),
        const Text(
          'Marital Status Distribution',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: summary.maritalStatusCounts.entries.map((e) {
            return Chip(
              label: Text('${e.key.toUpperCase()}: ${e.value}'),
              backgroundColor: AppTheme.primaryLight,
              padding: const EdgeInsets.symmetric(horizontal: 4),
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.warningAmber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.warningAmber.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: Colors.brown, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Clinically Significant Prolapse (Stage >= 2): ${summary.significantPopCount} of ${summary.totalVisitsRecorded} patients (${summary.significantPopPercentage}%)',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.brown, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Highest POP Stage (Baden-Walker / POP-Q)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ...summary.highestPopStages.entries.map((e) {
          final label = e.key == 0 ? 'Stage 0 (Normal / No Prolapse)' : 'Stage ${e.key}';
          final pct = summary.totalVisitsRecorded > 0 ? (e.value / summary.totalVisitsRecorded) : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: AppTheme.borderLight,
                      color: e.key >= 2 ? AppTheme.warningAmber : AppTheme.successGreen,
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${e.value}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
          );
        }),
        const Divider(height: 24),
        const Text(
          'Compartment Prolapse Frequency (Stage >= 1)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 10),
        _buildCompartmentTile(
          label: 'Anterior (Cystocele)',
          count: (summary.anteriorStages[1] ?? 0) +
              (summary.anteriorStages[2] ?? 0) +
              (summary.anteriorStages[3] ?? 0),
          totalVisits: summary.totalVisitsRecorded,
          color: AppTheme.accentCyan,
          icon: Icons.vertical_align_top,
        ),
        const SizedBox(height: 6),
        _buildCompartmentTile(
          label: 'Middle (Uterine / Apex)',
          count: (summary.middleStages[1] ?? 0) +
              (summary.middleStages[2] ?? 0) +
              (summary.middleStages[3] ?? 0) +
              (summary.middleStages[4] ?? 0),
          totalVisits: summary.totalVisitsRecorded,
          color: AppTheme.warningAmber,
          icon: Icons.vertical_align_center,
        ),
        const SizedBox(height: 6),
        _buildCompartmentTile(
          label: 'Posterior (Rectocele)',
          count: (summary.posteriorStages[1] ?? 0) +
              (summary.posteriorStages[2] ?? 0) +
              (summary.posteriorStages[3] ?? 0),
          totalVisits: summary.totalVisitsRecorded,
          color: AppTheme.primaryTeal,
          icon: Icons.vertical_align_bottom,
        ),
      ],
    );
  }

  Widget _buildCompartmentTile({
    required String label,
    required int count,
    required int totalVisits,
    required Color color,
    required IconData icon,
  }) {
    final pct = totalVisits > 0 ? (count / totalVisits * 100).toStringAsFixed(1) : '0.0';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count cases ($pct%)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosesTab(CampReportSummaryModel summary) {
    return summary.diagnosisCounts.isEmpty
        ? const Center(child: Text('No diagnoses recorded yet.'))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Ranked Pathologies Identified',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
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
                    child: Text(
                      '${e.value}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    e.key,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    '$pct%',
                    style: const TextStyle(color: AppTheme.textSecondaryLight),
                  ),
                );
              }),
            ],
          );
  }

  Widget _buildTreatmentTab(CampReportSummaryModel summary) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Interventions & Referrals',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 6),
        Text('• Pessaries Fitted: ${summary.totalPessariesInserted} patients'),
        if (summary.pessaryCounts.isNotEmpty)
          ...summary.pessaryCounts.entries.map((e) => Padding(
                padding: const EdgeInsets.only(left: 16, top: 2),
                child: Text('- ${e.key}: ${e.value}', style: const TextStyle(fontSize: 12)),
              )),
        const SizedBox(height: 4),
        Text('• Pelvic Floor Exercises: ${summary.pelvicFloorCounselingCount} counseled'),
        const SizedBox(height: 4),
        Text('• Surgical Referrals: ${summary.totalSurgicalReferrals} patients'),
        if (summary.surgicalReferralCounts.isNotEmpty)
          ...summary.surgicalReferralCounts.entries.map((e) => Padding(
                padding: const EdgeInsets.only(left: 16, top: 2),
                child: Text('- ${e.key}: ${e.value}', style: const TextStyle(fontSize: 12)),
              )),
        const Divider(height: 24),
        const Text(
          'Prescribed Medications Dispensed',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
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

    final effectiveCampId = campId ??
        campState.activeCamp?.id ??
        (campState.camps.isNotEmpty ? campState.camps.first.id : null);

    if (effectiveCampId != null &&
        (!patientState.hasLoaded || patientState.loadedCampId != effectiveCampId) &&
        !patientState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(patientListProvider.notifier).loadPatients(effectiveCampId);
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
        if (patientState.isLoading && patientState.patients.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(
              color: AppTheme.primaryTeal,
              backgroundColor: AppTheme.primaryLight,
              minHeight: 2,
            ),
          ),
        Expanded(
          child: (patientState.isLoading && patientState.patients.isEmpty)
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: AppTheme.primaryTeal),
                      SizedBox(height: 12),
                      Text(
                        'Loading patient records...',
                        style: TextStyle(color: AppTheme.textSecondaryLight, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : patients.isEmpty
                  ? Center(
                      child: Text(
                        _patientSearchController.text.isNotEmpty
                            ? 'No matching patients found.'
                            : 'No patient records found in this camp.',
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

                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 480;

                            if (isNarrow) {
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.borderLight),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.15),
                                          child: Text(
                                            patient.firstName.isNotEmpty
                                                ? patient.firstName[0].toUpperCase()
                                                : 'P',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.primaryTeal,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            patient.fullName,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            patient.patientId,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Age: ${patient.age}y • Ward: ${patient.ward} • Mobile: ${patient.mobile.isNotEmpty ? patient.mobile : "N/A"}',
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryTeal,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                        icon: isExporting
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                              )
                                            : const Icon(Icons.picture_as_pdf, size: 14),
                                        label: Text(
                                          isExporting ? 'Exporting...' : 'PDF Dossier',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                        onPressed: isExporting
                                            ? null
                                            : () => _exportIndividualPatientPdf(
                                                  patient,
                                                  campState,
                                                  user,
                                                  deviceState,
                                                ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.15),
                                child: Text(
                                  patient.firstName.isNotEmpty
                                      ? patient.firstName[0].toUpperCase()
                                      : 'P',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryTeal,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      patient.fullName,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      patient.patientId,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                'Age: ${patient.age}y • Ward: ${patient.ward} • Mobile: ${patient.mobile.isNotEmpty ? patient.mobile : "N/A"}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                                    : () => _exportIndividualPatientPdf(
                                          patient,
                                          campState,
                                          user,
                                          deviceState,
                                        ),
                              ),
                            );
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
