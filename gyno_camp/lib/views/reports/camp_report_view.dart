import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/file_download_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../models/camp_model.dart';
import '../../models/camp_report_summary_model.dart';
import '../../models/clinical_visit_model.dart';
import '../../models/lookup_item_model.dart';
import '../../models/patient_model.dart';
import '../../models/user_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../../viewmodels/master_lookup_viewmodel.dart';
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

  // ── Filters & Master-Detail Selection ─────────────────────────────────────
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedDoctor;
  String? _selectedDiagnosis;
  String? _selectedPopStage;
  String? _selectedTreatment;
  String? _selectedVisitReason;
  String? _selectedComplaint;
  PatientModel? _selectedPatient;

  // ── Master Lookup Data for Selected Camp ──────────────────────────────────
  List<LookupItemModel> _campDiagnoses = [];
  List<LookupItemModel> _campChiefComplaints = [];
  List<LookupItemModel> _campVisitReasons = [];
  List<LookupItemModel> _campMedicines = [];
  List<LookupItemModel> _campReferralHospitals = [];

  Future<void> _loadCampMasterData(String? campId) async {
    final cleanCampId = (campId == null || campId == 'all' || campId.trim().isEmpty) ? null : campId.trim();
    try {
      final repo = ref.read(lookupRepositoryProvider);
      final tenantId = ref.read(authStateProvider).currentUser?.tenantId;
      final diags = await repo.getItemsByCategory('diagnosis', tenantId: tenantId, campId: cleanCampId, activeOnly: true);
      final complaints = await repo.getItemsByCategory('chief_complaint', tenantId: tenantId, campId: cleanCampId, activeOnly: true);
      final reasons = await repo.getItemsByCategory('visit_reason', tenantId: tenantId, campId: cleanCampId, activeOnly: true);
      final meds = await repo.getItemsByCategory('medicine', tenantId: tenantId, campId: cleanCampId, activeOnly: true);
      final hosps = await repo.getItemsByCategory('referral_hospital', tenantId: tenantId, campId: cleanCampId, activeOnly: true);
      if (mounted) {
        setState(() {
          _campDiagnoses = diags;
          _campChiefComplaints = complaints;
          _campVisitReasons = reasons;
          _campMedicines = meds;
          _campReferralHospitals = hosps;
        });
      }
    } catch (e) {
      debugPrint('Error loading master lookup data for camp reports: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final campState = ref.read(campStateProvider);
      final activeCamp = campState.activeCamp ?? (campState.camps.isNotEmpty ? campState.camps.first : null);
      final targetCampId = widget.initialCampId ?? activeCamp?.id;
      _loadCampMasterData(targetCampId);
      ref.read(reportingViewModelProvider.notifier).loadSummary(
        campId: targetCampId,
        doctorFilter: _selectedDoctor,
        diagnosisFilter: _selectedDiagnosis,
        popStageFilter: _selectedPopStage,
        treatmentFilter: _selectedTreatment,
        visitReasonFilter: _selectedVisitReason,
        complaintFilter: _selectedComplaint,
      );
      if (targetCampId != null) {
        ref.read(patientListProvider.notifier).loadPatients(targetCampId);
      }
      if (campState.camps.isEmpty) {
        ref.read(campStateProvider.notifier).loadCamps(silent: true);
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
    setState(() {
      _selectedDoctor = null;
      _selectedDiagnosis = null;
      _selectedPopStage = null;
      _selectedTreatment = null;
      _selectedVisitReason = null;
      _selectedComplaint = null;
      _selectedPatient = null;
    });
    _loadCampMasterData(campId);
    ref.read(reportingViewModelProvider.notifier).loadSummary(
      campId: campId,
      startDate: _startDate,
      endDate: _endDate,
      doctorFilter: null,
      diagnosisFilter: null,
      popStageFilter: null,
      treatmentFilter: null,
      visitReasonFilter: null,
      complaintFilter: null,
    );
    // When null or 'all', load all patients across all camps without filtering
    ref.read(patientListProvider.notifier).loadPatients(campId == 'all' ? null : campId);
  }

  void _onRefresh() {
    final reportState = ref.read(reportingViewModelProvider);
    final currentCampId = reportState.selectedCampId;
    _loadCampMasterData(currentCampId);
    ref.read(reportingViewModelProvider.notifier).loadSummary(
      campId: currentCampId,
      startDate: _startDate,
      endDate: _endDate,
      doctorFilter: _selectedDoctor,
      diagnosisFilter: _selectedDiagnosis,
      popStageFilter: _selectedPopStage,
      treatmentFilter: _selectedTreatment,
      visitReasonFilter: _selectedVisitReason,
      complaintFilter: _selectedComplaint,
    );
    ref.read(patientListProvider.notifier).loadPatients(currentCampId == 'all' ? null : currentCampId);
  }

  Future<void> _pickStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select Start Date',
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select End Date',
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  void _applyDateFilter() => _onRefresh();

  void _clearAllFilters() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _selectedDoctor = null;
      _selectedDiagnosis = null;
      _selectedPopStage = null;
      _selectedTreatment = null;
      _selectedVisitReason = null;
      _selectedComplaint = null;
      _selectedPatient = null;
    });
    _onRefresh();
  }

  // ── Dynamic Filter Counts ───────────────────────────────────────────────
  int _getDoctorCount(String doc, CampReportSummaryModel? summary) {
    if (summary == null) return 0;
    bool docMatch(String a, String b) {
      final cleanA = a.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim().toLowerCase();
      final cleanB = b.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim().toLowerCase();
      return cleanA.isNotEmpty && cleanB.isNotEmpty && (cleanA == cleanB || cleanA.contains(cleanB) || cleanB.contains(cleanA));
    }
    final matchingVisits = summary.visits.where((v) =>
        (v.primaryDoctorName != null && docMatch(v.primaryDoctorName!, doc)) ||
        v.attendingDoctorNames.any((d) => docMatch(d, doc)));
    final matchingPatientIds = matchingVisits.map((v) => v.patientId).toSet();
    final matchingFromPatients = summary.patients.where((p) =>
        p.primaryDoctorName != null && docMatch(p.primaryDoctorName!, doc)).map((p) => p.patientId);
    matchingPatientIds.addAll(matchingFromPatients);
    return matchingPatientIds.length;
  }

  int _getDiagnosisCount(String dx, CampReportSummaryModel? summary) {
    if (summary == null) return 0;
    final dxLower = dx.trim().toLowerCase();
    final matchingVisits = summary.visits.where((v) {
      return v.diagnoses.any((d) {
        final dLower = d.trim().toLowerCase();
        return dLower == dxLower || dLower.contains(dxLower) || dxLower.contains(dLower);
      });
    });
    return matchingVisits.map((v) => v.patientId).toSet().length;
  }

  int _getPopStageCount(String stageKey, CampReportSummaryModel? summary) {
    if (summary == null) return 0;
    final matchingVisits = summary.visits.where((v) {
      if (stageKey == '0') return v.highestPopStage == 0;
      if (stageKey == '1') return v.highestPopStage == 1;
      if (stageKey == '2+') return v.highestPopStage >= 2;
      if (stageKey == '3+') return v.highestPopStage >= 3;
      return true;
    });
    return matchingVisits.map((v) => v.patientId).toSet().length;
  }

  int _getTreatmentCount(String txKey, CampReportSummaryModel? summary) {
    if (summary == null) return 0;
    final matchingVisits = summary.visits.where((v) {
      if (txKey == 'pessary') {
        return (v.pessaryType != null && v.pessaryType!.trim().isNotEmpty) ||
            (v.pessarySize != null && v.pessarySize!.trim().isNotEmpty);
      }
      if (txKey == 'surgery') {
        return (v.surgicalReferral != null && v.surgicalReferral!.trim().isNotEmpty) ||
            v.surgeryDone == true;
      }
      if (txKey == 'counseling') {
        return v.counseling.isNotEmpty;
      }
      if (txKey == 'medications') {
        return v.medications.isNotEmpty ||
            (v.customMedication != null && v.customMedication!.trim().isNotEmpty);
      }
      if (txKey.startsWith('med:')) {
        final targetMed = txKey.substring(4).toLowerCase().trim();
        final hasStandard = v.medications.any((m) => m.toLowerCase().contains(targetMed));
        final hasCustom = v.customMedication?.toLowerCase().contains(targetMed) ?? false;
        return hasStandard || hasCustom;
      }
      if (txKey.startsWith('hosp:')) {
        final targetHosp = txKey.substring(5).toLowerCase().trim();
        return v.surgicalReferral?.toLowerCase().contains(targetHosp) ?? false;
      }
      return true;
    });
    return matchingVisits.map((v) => v.patientId).toSet().length;
  }

  int _getVisitReasonCount(String reasonKey, CampReportSummaryModel? summary) {
    if (summary == null) return 0;
    final target = reasonKey.toLowerCase().trim();
    final matchingLookup = _campVisitReasons.where((r) =>
        r.code.toLowerCase().trim() == target ||
        r.labelEn.toLowerCase().trim() == target ||
        r.labelNe.toLowerCase().trim() == target);
    final lookupAliases = matchingLookup.isNotEmpty
        ? [
            matchingLookup.first.code.toLowerCase().trim(),
            matchingLookup.first.labelEn.toLowerCase().trim(),
            if (matchingLookup.first.labelNe.trim().isNotEmpty) matchingLookup.first.labelNe.toLowerCase().trim(),
          ]
        : <String>[];

    return summary.patients.where((p) {
      final reasons = p.reasonsForVisit.map((r) => r.toLowerCase().trim()).toList();
      if (reasons.any((r) => r == target || r.contains(target) || target.contains(r))) return true;
      if (lookupAliases.any((alias) => reasons.any((r) => r == alias || r.contains(alias) || alias.contains(r)))) return true;
      if (target == 'prolapse' || target.contains('hanging') || target.contains('खस्ने') || target.contains('खसेको')) {
        return reasons.any((r) => r.contains('hanging') || r.contains('prolapse') || r.contains('खस्ने') || r.contains('खसेको'));
      }
      if (target == 'discharge' || target.contains('itching') || target.contains('स्राव') || target.contains('चिलाउने') || target.contains('सेतो')) {
        return reasons.any((r) => r.contains('discharge') || r.contains('itching') || r.contains('स्राव') || r.contains('चिलाउने') || r.contains('सेतो'));
      }
      if (target == 'urine' || target.contains('dysuria') || target.contains('पिसाब')) {
        return reasons.any((r) => r.contains('urine') || r.contains('dysuria') || r.contains('पिसाब'));
      }
      if (target == 'stool' || target.contains('bowel') || target.contains('constipation') || target.contains('दिसा')) {
        return reasons.any((r) => r.contains('stool') || r.contains('bowel') || r.contains('constipation') || r.contains('दिसा'));
      }
      if (target == 'pain' || target.contains('दुखाई') || target.contains('दुख्ने') || target.contains('तल्लो पेट')) {
        return reasons.any((r) => r.contains('pain') || r.contains('दुखाई') || r.contains('दुख्ने') || r.contains('तल्लो पेट'));
      }
      if (target == 'menstrual' || target.contains('महिनावारी') || target.contains('bleeding')) {
        return reasons.any((r) => r.contains('menstrual') || r.contains('महिनावारी') || r.contains('bleeding'));
      }
      if (target == 'infertility' || target.contains('बाँझोपन') || target.contains('निःसन्तान')) {
        return reasons.any((r) => r.contains('infertility') || r.contains('बाँझोपन') || r.contains('निःसन्तान'));
      }
      if (target == 'checkup' || target.contains('routine') || target.contains('जाँच')) {
        return reasons.any((r) => r.contains('checkup') || r.contains('routine') || r.contains('जाँच'));
      }
      return false;
    }).length;
  }

  int _getComplaintCount(String compKey, CampReportSummaryModel? summary) {
    if (summary == null) return 0;
    final target = compKey.toLowerCase().trim();
    final matchingLookup = _campChiefComplaints.where((c) =>
        c.code.toLowerCase().trim() == target ||
        c.labelEn.toLowerCase().trim() == target ||
        c.labelNe.toLowerCase().trim() == target);
    final lookupAliases = matchingLookup.isNotEmpty
        ? [
            matchingLookup.first.code.toLowerCase().trim(),
            matchingLookup.first.labelEn.toLowerCase().trim(),
            if (matchingLookup.first.labelNe.trim().isNotEmpty) matchingLookup.first.labelNe.toLowerCase().trim(),
          ]
        : <String>[];

    final visitMap = {for (final v in summary.visits) v.patientId: v};
    return summary.patients.where((p) {
      final visit = visitMap[p.patientId];
      if (visit == null) return false;
      final anamnesis = visit.anamnesisComplaints.toString().toLowerCase();
      final clinicalComplaints = (visit.anamnesisComplaints['clinicalComplaints'] as List?)
          ?.map((e) => e.toString().toLowerCase())
          .toList() ?? [];

      if (clinicalComplaints.any((c) => c == target || c.contains(target) || target.contains(c))) {
        return true;
      }
      if (lookupAliases.any((alias) =>
          clinicalComplaints.any((c) => c == alias || c.contains(alias) || alias.contains(c)) ||
          anamnesis.contains(alias))) {
        return true;
      }
      if (target == 'something hanging out' || target == 'prolapse' || target == 'pelvic_organ_prolapse') {
        return anamnesis.contains('hanging') || anamnesis.contains('prolapse') || anamnesis.contains('खस्ने') || anamnesis.contains('pelvic_organ_prolapse');
      } else if (target == 'discharge and or itching' || target == 'discharge') {
        return anamnesis.contains('discharge') || anamnesis.contains('itching') || anamnesis.contains('स्राव') || anamnesis.contains('चिलाउने') || anamnesis.contains('सेतो');
      } else if (target == 'problems passing urine' || target == 'urine') {
        return anamnesis.contains('urine') || anamnesis.contains('dysuria') || anamnesis.contains('पिसाब');
      } else if (target == 'problems passing stool' || target == 'stool') {
        return anamnesis.contains('stool') || anamnesis.contains('bowel') || anamnesis.contains('constipation') || anamnesis.contains('दिसा');
      } else if (target == 'pain') {
        return anamnesis.contains('pain') || anamnesis.contains('दुखाई') || anamnesis.contains('दुख्ने') || anamnesis.contains('तल्लो पेट');
      } else if (target == 'menstrual problem' || target == 'menstrual' || target == 'menstrual_disorder') {
        return anamnesis.contains('menstrual') || anamnesis.contains('महिनावारी') || anamnesis.contains('bleeding') || anamnesis.contains('menstrual_disorder');
      } else if (target == 'infertility' || target == 'infertility_screening') {
        return anamnesis.contains('infertility') || anamnesis.contains('बाँझोपन') || anamnesis.contains('निःसन्तान') || anamnesis.contains('infertility_screening');
      } else if (target == 'checkup' || target == 'routine_checkup') {
        return anamnesis.contains('checkup') || anamnesis.contains('routine') || anamnesis.contains('जाँच') || anamnesis.contains('routine_checkup');
      } else if (target == 'gynaecological_oncology' || target == 'oncology' || target == 'cancer') {
        return anamnesis.contains('cancer') || anamnesis.contains('oncology') || anamnesis.contains('क्यान्सर') || anamnesis.contains('gynaecological_oncology');
      } else {
        return anamnesis.contains(target);
      }
    }).length;
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
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.primaryTeal,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Patient dossier exported: ${patient.fullName}')),
                if (!kIsWeb) ...[
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => FileDownloadHelper.openFile(saved),
                    child: const Text('Review', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
            duration: const Duration(seconds: 5),
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

    final isSuperAdmin = user?.role == UserRole.superAdmin;
    final visibleCamps = !isSuperAdmin && user != null
        ? campState.camps.where((c) => user.assignedCampIds.contains(c.id)).toList()
        : campState.camps;

    final selectedCampObj = reportState.selectedCampId != null
        ? campState.camps.where((c) => c.id == reportState.selectedCampId).firstOrNull
        : null;
    final relevantCamps = selectedCampObj != null ? [selectedCampObj] : visibleCamps;

    // 1. DYNAMIC DOCTORS: Strictly scoped to the selected camp (or visible camps if All Camps)
    final scopedDoctors = <String>{};
    for (final camp in relevantCamps) {
      if (camp.doctorNames.isNotEmpty) {
        scopedDoctors.addAll(camp.doctorNames.map((d) => d.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim()).where((d) => d.isNotEmpty));
      } else if (camp.doctorName.trim().isNotEmpty) {
        scopedDoctors.add(camp.doctorName.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim());
      }
    }
    final docSummary = reportState.unfilteredSummary ?? reportState.summary;
    if (docSummary != null) {
      for (final v in docSummary.visits) {
        if (v.primaryDoctorName != null && v.primaryDoctorName!.trim().isNotEmpty) {
          final clean = v.primaryDoctorName!.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim();
          if (clean.isNotEmpty) scopedDoctors.add(clean);
        }
        for (final d in v.attendingDoctorNames) {
          final clean = d.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim();
          if (clean.isNotEmpty) scopedDoctors.add(clean);
        }
      }
      for (final p in docSummary.patients) {
        if (p.primaryDoctorName != null && p.primaryDoctorName!.trim().isNotEmpty) {
          final clean = p.primaryDoctorName!.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim();
          if (clean.isNotEmpty) scopedDoctors.add(clean);
        }
        for (final d in p.attendingDoctorNames) {
          final clean = d.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim();
          if (clean.isNotEmpty) scopedDoctors.add(clean);
        }
      }
    }

    // Only show doctors who actually worked in this camp scope (or are currently selected)
    final activeDoctors = scopedDoctors
        .where((doc) => _getDoctorCount(doc, docSummary) > 0 || _selectedDoctor == doc)
        .toList();
    // Fall back to assigned camp doctors only if no examinations recorded yet
    final finalDoctors = activeDoctors.isNotEmpty
        ? (activeDoctors..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
        : (scopedDoctors.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
    if (_selectedDoctor != null && !finalDoctors.contains(_selectedDoctor)) {
      _selectedDoctor = null;
    }
    final allDoctors = finalDoctors.toSet();

    // 2. DYNAMIC DIAGNOSES: Master Data + Clinical Records
    final dynamicDiagnoses = <String>{};
    for (final m in _campDiagnoses) {
      if (m.labelEn.trim().isNotEmpty) dynamicDiagnoses.add(m.labelEn.trim());
    }
    if (docSummary != null) {
      dynamicDiagnoses.addAll(docSummary.diagnosisCounts.keys.where((d) => d.trim().isNotEmpty));
      for (final v in docSummary.visits) {
        dynamicDiagnoses.addAll(v.diagnoses.map((d) => d.trim()).where((d) => d.isNotEmpty));
      }
    }
    if (_selectedDiagnosis != null && _selectedDiagnosis!.trim().isNotEmpty) {
      dynamicDiagnoses.add(_selectedDiagnosis!.trim());
    }
    final sortedDiagnoses = dynamicDiagnoses.toList()
      ..sort((a, b) {
        final countA = _getDiagnosisCount(a, docSummary);
        final countB = _getDiagnosisCount(b, docSummary);
        if (countA > 0 && countB == 0) return -1;
        if (countA == 0 && countB > 0) return 1;
        if (countA != countB) return countB.compareTo(countA);
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    if (_selectedDiagnosis != null && !sortedDiagnoses.contains(_selectedDiagnosis)) {
      _selectedDiagnosis = null;
    }

    // 3. DYNAMIC TREATMENTS: Standard Interventions + Master Data Formulary (Medicines & Referral Hospitals)
    final dynamicTreatments = <Map<String, String>>[
      {'key': 'pessary', 'label': 'Pessary Fitted (रिङ पेसरी)'},
      {'key': 'surgery', 'label': 'Surgical Referral (शल्यक्रिया)'},
      {'key': 'counseling', 'label': 'Pelvic Floor Exercises (कौन्सिलिङ)'},
      {'key': 'medications', 'label': 'All Medications Dispensed (औषधि)'},
    ];
    final seenMedKeys = <String>{};
    for (final med in _campMedicines) {
      final key = 'med:${med.labelEn.trim().toLowerCase()}';
      if (seenMedKeys.add(key)) {
        final nepaliSuffix = med.labelNe.trim().isNotEmpty ? ' (${med.labelNe.trim()})' : '';
        dynamicTreatments.add({
          'key': key,
          'label': 'Rx: ${med.labelEn.trim()}$nepaliSuffix',
        });
      }
    }
    final seenHospKeys = <String>{};
    for (final hosp in _campReferralHospitals) {
      final key = 'hosp:${hosp.labelEn.trim().toLowerCase()}';
      if (seenHospKeys.add(key)) {
        final nepaliSuffix = hosp.labelNe.trim().isNotEmpty ? ' (${hosp.labelNe.trim()})' : '';
        dynamicTreatments.add({
          'key': key,
          'label': 'Ref: ${hosp.labelEn.trim()}$nepaliSuffix',
        });
      }
    }
    if (_selectedTreatment != null && !dynamicTreatments.any((t) => t['key'] == _selectedTreatment)) {
      _selectedTreatment = null;
    }

    // 4. DYNAMIC VISIT REASONS: Master Data Visit Reasons (with fallback only if all camps & empty)
    final dynamicVisitReasons = <Map<String, String>>[];
    final seenReasonKeys = <String>{};
    for (final reason in _campVisitReasons.where((r) => r.isActive)) {
      final key = (reason.code.isNotEmpty ? reason.code : reason.labelEn).trim().toLowerCase();
      if (seenReasonKeys.add(key)) {
        final nepaliSuffix = reason.labelNe.trim().isNotEmpty ? ' (${reason.labelNe.trim()})' : '';
        dynamicVisitReasons.add({
          'key': key,
          'label': '${reason.labelEn.trim()}$nepaliSuffix',
        });
      }
    }
    // Only fall back to standard reasons if viewing all camps and no master reasons exist
    if (dynamicVisitReasons.isEmpty && (reportState.selectedCampId == null || reportState.selectedCampId == 'all')) {
      final standardVisitReasons = <Map<String, String>>[
        {'key': 'prolapse', 'label': 'Pelvic Organ Prolapse (आङ खस्ने)'},
        {'key': 'discharge', 'label': 'Discharge / Itching (स्राव/चिलाउने)'},
        {'key': 'urine', 'label': 'Urinary Difficulties (पिसाब समस्या)'},
        {'key': 'stool', 'label': 'Bowel / Constipation (दिसा समस्या)'},
        {'key': 'pain', 'label': 'Lower Abdominal Pain (तल्लो पेट दुखाई)'},
        {'key': 'menstrual', 'label': 'Menstrual Disorder (महिनावारी)'},
        {'key': 'infertility', 'label': 'Infertility Screening (बाँझोपन)'},
        {'key': 'checkup', 'label': 'Routine Checkup (नियमित जाँच)'},
      ];
      dynamicVisitReasons.addAll(standardVisitReasons);
    }
    dynamicVisitReasons.sort((a, b) {
      final countA = _getVisitReasonCount(a['key']!, docSummary);
      final countB = _getVisitReasonCount(b['key']!, docSummary);
      if (countA > 0 && countB == 0) return -1;
      if (countA == 0 && countB > 0) return 1;
      if (countA != countB) return countB.compareTo(countA);
      return 0;
    });
    if (_selectedVisitReason != null && !dynamicVisitReasons.any((r) => r['key'] == _selectedVisitReason)) {
      _selectedVisitReason = null;
    }

    // 5. DYNAMIC CHIEF COMPLAINTS: Master Data Chief Complaints (with fallback only if all camps & empty)
    final dynamicComplaints = <Map<String, String>>[];
    final seenCompKeys = <String>{};
    for (final comp in _campChiefComplaints.where((c) => c.isActive)) {
      final key = (comp.code.isNotEmpty ? comp.code : comp.labelEn).trim().toLowerCase();
      if (seenCompKeys.add(key)) {
        final nepaliSuffix = comp.labelNe.trim().isNotEmpty ? ' (${comp.labelNe.trim()})' : '';
        dynamicComplaints.add({
          'key': key,
          'label': '${comp.labelEn.trim()}$nepaliSuffix',
        });
      }
    }
    // Only fall back to standard complaints if viewing all camps and no master complaints exist
    if (dynamicComplaints.isEmpty && (reportState.selectedCampId == null || reportState.selectedCampId == 'all')) {
      final standardComplaints = <Map<String, String>>[
        {'key': 'prolapse', 'label': 'Pelvic Organ Prolapse (आङ खस्ने)'},
        {'key': 'discharge', 'label': 'Discharge / Itching (स्राव/चिलाउने)'},
        {'key': 'urine', 'label': 'Urinary Difficulties (पिसाब समस्या)'},
        {'key': 'stool', 'label': 'Bowel / Constipation (दिसा समस्या)'},
        {'key': 'pain', 'label': 'Lower Abdominal Pain (तल्लो पेट दुखाई)'},
        {'key': 'menstrual', 'label': 'Menstrual Disorder (महिनावारी)'},
        {'key': 'infertility', 'label': 'Infertility Screening (बाँझोपन)'},
        {'key': 'checkup', 'label': 'Routine Checkup (नियमित जाँच)'},
      ];
      dynamicComplaints.addAll(standardComplaints);
    }
    dynamicComplaints.sort((a, b) {
      final countA = _getComplaintCount(a['key']!, docSummary);
      final countB = _getComplaintCount(b['key']!, docSummary);
      if (countA > 0 && countB == 0) return -1;
      if (countA == 0 && countB > 0) return 1;
      if (countA != countB) return countB.compareTo(countA);
      return 0;
    });
    if (_selectedComplaint != null && !dynamicComplaints.any((c) => c['key'] == _selectedComplaint)) {
      _selectedComplaint = null;
    }

    final allCampsLabel = isSuperAdmin
        ? 'All Camp Records (समग्र क्याम्प)'
        : 'All My Assigned Camps (${visibleCamps.length})';

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: AppTheme.brandAppBarFlexibleSpace,
        bottom: AppTheme.brandAppBarBottomLine,
        iconTheme: const IconThemeData(color: Color(0xFF1E0A38)),
        title: const Text(
          'Camp Clinical Reports',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Color(0xFF1E0A38),
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: -0.3,
          ),
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth >= 960;

                    if (isDesktop) {
                      return _buildDesktopLayout(
                        reportState: reportState,
                        reportVm: reportVm,
                        campState: campState,
                        user: user,
                        deviceId: deviceId,
                        deviceState: deviceState,
                        allDoctors: allDoctors,
                        sortedDiagnoses: sortedDiagnoses,
                        dynamicTreatments: dynamicTreatments,
                        dynamicVisitReasons: dynamicVisitReasons,
                        dynamicComplaints: dynamicComplaints,
                        visibleCamps: visibleCamps,
                        allCampsLabel: allCampsLabel,
                      );
                    }

                    return _buildMobileStackedLayout(
                      reportState: reportState,
                      reportVm: reportVm,
                      campState: campState,
                      user: user,
                      deviceId: deviceId,
                      deviceState: deviceState,
                      allDoctors: allDoctors,
                      sortedDiagnoses: sortedDiagnoses,
                      dynamicTreatments: dynamicTreatments,
                      dynamicVisitReasons: dynamicVisitReasons,
                      dynamicComplaints: dynamicComplaints,
                      visibleCamps: visibleCamps,
                      allCampsLabel: allCampsLabel,
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildDesktopLayout({
    required ReportingState reportState,
    required ReportingViewModel reportVm,
    required CampState campState,
    required UserModel? user,
    required String deviceId,
    required DeviceSecurityState deviceState,
    required Set<String> allDoctors,
    required List<String> sortedDiagnoses,
    required List<Map<String, String>> dynamicTreatments,
    required List<Map<String, String>> dynamicVisitReasons,
    required List<Map<String, String>> dynamicComplaints,
    required List<CampModel> visibleCamps,
    required String allCampsLabel,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Left Sidebar: Dropdowns & Export Action Controls ──────────
              SizedBox(
                width: 320,
                child: _buildFilterSidebarCard(
                  reportState: reportState,
                  campState: campState,
                  user: user,
                  deviceId: deviceId,
                  allDoctors: allDoctors,
                  sortedDiagnoses: sortedDiagnoses,
                  dynamicTreatments: dynamicTreatments,
                  dynamicVisitReasons: dynamicVisitReasons,
                  dynamicComplaints: dynamicComplaints,
                  visibleCamps: visibleCamps,
                  allCampsLabel: allCampsLabel,
                ),
              ),
              const SizedBox(width: 16),
              // ── Right Workspace (Expanded): KPIs + Tabs + Patient Master-Detail ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFeedbackBanner(reportState, reportVm),
                    if (reportState.summary != null) ...[
                      _buildExecutiveKpis(reportState.summary!),
                      const SizedBox(height: 12),
                      _buildActiveFiltersBar(reportState),
                      const SizedBox(height: 4),
                      _buildTabbedAnalysisCard(
                        reportState: reportState,
                        campState: campState,
                        user: user,
                        deviceState: deviceState,
                        isDesktop: true,
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
        ],
      ),
    );
  }

  Widget _buildMobileStackedLayout({
    required ReportingState reportState,
    required ReportingViewModel reportVm,
    required CampState campState,
    required UserModel? user,
    required String deviceId,
    required DeviceSecurityState deviceState,
    required Set<String> allDoctors,
    required List<String> sortedDiagnoses,
    required List<Map<String, String>> dynamicTreatments,
    required List<Map<String, String>> dynamicVisitReasons,
    required List<Map<String, String>> dynamicComplaints,
    required List<CampModel> visibleCamps,
    required String allCampsLabel,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          _buildCampSelectorAndExportBar(
            reportState: reportState,
            campState: campState,
            user: user,
            deviceId: deviceId,
          ),
          _buildFeedbackBanner(reportState, reportVm),
          const SizedBox(height: 12),
          _buildMobileFilterBar(
            reportState: reportState,
            allDoctors: allDoctors,
            sortedDiagnoses: sortedDiagnoses,
            dynamicTreatments: dynamicTreatments,
            dynamicVisitReasons: dynamicVisitReasons,
            dynamicComplaints: dynamicComplaints,
          ),
          const SizedBox(height: 16),
          if (reportState.summary != null) ...[
            _buildExecutiveKpis(reportState.summary!),
            const SizedBox(height: 12),
            _buildActiveFiltersBar(reportState),
            const SizedBox(height: 4),
            _buildTabbedAnalysisCard(
              reportState: reportState,
              campState: campState,
              user: user,
              deviceState: deviceState,
              isDesktop: false,
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
    );
  }

  Widget _buildFeedbackBanner(ReportingState reportState, ReportingViewModel reportVm) {
    if (reportState.successMessage != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
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
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          kIsWeb ? 'Saved to browser Downloads folder' : 'Saved to ${reportState.lastExportPath}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!kIsWeb && reportState.lastExportPath!.isNotEmpty) ...[
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.primaryTeal,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.open_in_new_rounded, size: 14),
                            label: const Text('Review', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () => FileDownloadHelper.openFile(reportState.lastExportPath!),
                          ),
                          IconButton(
                            icon: const Icon(Icons.share_rounded, size: 16, color: AppTheme.primaryTeal),
                            tooltip: 'Share / Print',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => FileDownloadHelper.shareFile(reportState.lastExportPath!),
                          ),
                        ],
                      ],
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
      );
    }
    if (reportState.errorMessage != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
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
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildActiveFiltersBar(ReportingState reportState) {
    final activeFilters = <Widget>[];

    if (_startDate != null || _endDate != null) {
      final dateText = (_startDate != null && _endDate != null)
          ? '${_startDate!.day}/${_startDate!.month} - ${_endDate!.day}/${_endDate!.month}'
          : (_startDate != null ? 'From ${_startDate!.day}/${_startDate!.month}' : 'To ${_endDate!.day}/${_endDate!.month}');
      activeFilters.add(_buildFilterChip(
        label: 'Date: $dateText',
        icon: Icons.calendar_today_outlined,
        onDeleted: () {
          setState(() {
            _startDate = null;
            _endDate = null;
          });
          _onRefresh();
        },
      ));
    }

    if (_selectedDoctor != null) {
      activeFilters.add(_buildFilterChip(
        label: 'Dr. $_selectedDoctor',
        icon: Icons.medical_services_outlined,
        onDeleted: () {
          setState(() => _selectedDoctor = null);
          _onRefresh();
        },
      ));
    }

    if (_selectedDiagnosis != null) {
      activeFilters.add(_buildFilterChip(
        label: _selectedDiagnosis!,
        icon: Icons.healing,
        onDeleted: () {
          setState(() => _selectedDiagnosis = null);
          _onRefresh();
        },
      ));
    }

    if (_selectedPopStage != null) {
      final stageLabel = _selectedPopStage == '0'
          ? 'POP: Stage 0'
          : (_selectedPopStage == '1'
              ? 'POP: Stage 1'
              : (_selectedPopStage == '2+' ? 'POP: Stage >= 2' : 'POP: Stage 3-4'));
      activeFilters.add(_buildFilterChip(
        label: stageLabel,
        icon: Icons.straighten_outlined,
        onDeleted: () {
          setState(() => _selectedPopStage = null);
          _onRefresh();
        },
      ));
    }

    if (_selectedTreatment != null) {
      final txMap = {
        'pessary': 'Pessary Fitted',
        'surgery': 'Surgical Referral',
        'counseling': 'Counseled',
        'medications': 'Medications',
      };
      String txLabel = txMap[_selectedTreatment] ?? _selectedTreatment!;
      if (_selectedTreatment!.startsWith('med:')) {
        final medName = _selectedTreatment!.substring(4);
        final found = _campMedicines.where((m) => m.labelEn.toLowerCase() == medName).firstOrNull;
        txLabel = 'Rx: ${found?.labelEn ?? medName}';
      } else if (_selectedTreatment!.startsWith('hosp:')) {
        final hospName = _selectedTreatment!.substring(5);
        final found = _campReferralHospitals.where((h) => h.labelEn.toLowerCase() == hospName).firstOrNull;
        txLabel = 'Ref: ${found?.labelEn ?? hospName}';
      }
      activeFilters.add(_buildFilterChip(
        label: txLabel,
        icon: Icons.local_hospital_outlined,
        onDeleted: () {
          setState(() => _selectedTreatment = null);
          _onRefresh();
        },
      ));
    }

    if (_selectedVisitReason != null) {
      final reasonMap = {
        'prolapse': 'Prolapse / Mass',
        'discharge': 'Discharge / Itching',
        'urine': 'Urinary Problem',
        'stool': 'Bowel Problem',
        'pain': 'Lower Abdominal Pain',
        'menstrual': 'Menstrual Problem',
        'infertility': 'Infertility',
        'checkup': 'Routine Checkup',
      };
      String reasonLabel = reasonMap[_selectedVisitReason] ?? _selectedVisitReason!;
      final found = _campVisitReasons.where((r) =>
          r.code.toLowerCase() == _selectedVisitReason!.toLowerCase() ||
          r.labelEn.toLowerCase() == _selectedVisitReason!.toLowerCase()).firstOrNull;
      if (found != null) {
        reasonLabel = found.labelEn;
      }
      activeFilters.add(_buildFilterChip(
        label: 'Reason: $reasonLabel',
        icon: Icons.how_to_reg_outlined,
        onDeleted: () {
          setState(() => _selectedVisitReason = null);
          _onRefresh();
        },
      ));
    }

    if (_selectedComplaint != null) {
      final compMap = {
        'prolapse': 'Mass / Prolapse',
        'discharge': 'Discharge / Itching',
        'urine': 'Urinary Problem',
        'stool': 'Bowel Problem',
        'pain': 'Pelvic Pain',
        'menstrual': 'Menstrual Problem',
        'infertility': 'Infertility',
        'checkup': 'Routine Checkup',
      };
      String compLabel = compMap[_selectedComplaint] ?? _selectedComplaint!;
      final found = _campChiefComplaints.where((c) =>
          c.code.toLowerCase() == _selectedComplaint!.toLowerCase() ||
          c.labelEn.toLowerCase() == _selectedComplaint!.toLowerCase()).firstOrNull;
      if (found != null) {
        compLabel = found.labelEn;
      }
      activeFilters.add(_buildFilterChip(
        label: 'Complaint: $compLabel',
        icon: Icons.report_problem_outlined,
        onDeleted: () {
          setState(() => _selectedComplaint = null);
          _onRefresh();
        },
      ));
    }

    if (activeFilters.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryTeal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_alt, size: 16, color: AppTheme.primaryTeal),
          const SizedBox(width: 8),
          const Text(
            'Active Filters:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: activeFilters,
            ),
          ),
          TextButton(
            onPressed: _clearAllFilters,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              foregroundColor: AppTheme.dangerRose,
            ),
            child: const Text('Clear All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    IconData? icon,
    required VoidCallback onDeleted,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: AppTheme.primaryTeal),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryDark),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onDeleted,
            borderRadius: BorderRadius.circular(10),
            child: const Icon(Icons.close, size: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSidebarCard({
    required ReportingState reportState,
    required CampState campState,
    required UserModel? user,
    required String deviceId,
    required Set<String> allDoctors,
    required List<String> sortedDiagnoses,
    required List<Map<String, String>> dynamicTreatments,
    required List<Map<String, String>> dynamicVisitReasons,
    required List<Map<String, String>> dynamicComplaints,
    required List<CampModel> visibleCamps,
    required String allCampsLabel,
  }) {
    final activeFiltersCount = (_startDate != null ? 1 : 0) +
        (_endDate != null ? 1 : 0) +
        (_selectedDoctor != null ? 1 : 0) +
        (_selectedDiagnosis != null ? 1 : 0) +
        (_selectedPopStage != null ? 1 : 0) +
        (_selectedVisitReason != null ? 1 : 0) +
        (_selectedTreatment != null ? 1 : 0) +
        (_selectedComplaint != null ? 1 : 0);
    final hasActiveFilter = activeFiltersCount > 0;
    final baseSummary = reportState.unfilteredSummary ?? reportState.summary;
    final totalPatients = baseSummary?.totalPatientsRegistered ?? 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_rounded, color: AppTheme.primaryTeal, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      const Text(
                        'Filters & Export',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.primaryDark),
                      ),
                      if (hasActiveFilter) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryTeal,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$activeFiltersCount',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (hasActiveFilter)
                  TextButton.icon(
                    onPressed: _clearAllFilters,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppTheme.dangerRose,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    icon: const Icon(Icons.clear_all, size: 14),
                    label: const Text('Reset', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const Divider(height: 20),

            // 1. Target Camp Dropdown
            const Row(
              children: [
                Icon(Icons.location_on_outlined, color: AppTheme.primaryTeal, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text('Select Camp Target:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.borderLight),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: visibleCamps.any((c) => c.id == reportState.selectedCampId) ? reportState.selectedCampId : null,
                  hint: Text(allCampsLabel, style: const TextStyle(fontSize: 12)),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(allCampsLabel, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                    ),
                    ...visibleCamps.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text('${c.campCode} - ${c.name}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: _onCampChanged,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 2. Date Range Filter
            const Row(
              children: [
                Icon(Icons.date_range_outlined, color: AppTheme.primaryTeal, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text('Date Range Filter:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickStartDate(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _startDate != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 12, color: AppTheme.primaryTeal),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _startDate != null ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}' : 'From date',
                              style: TextStyle(
                                fontSize: 11,
                                color: _startDate != null ? AppTheme.primaryDark : Colors.grey,
                                fontWeight: _startDate != null ? FontWeight.w600 : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('→', style: TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickEndDate(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _endDate != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 12, color: AppTheme.primaryTeal),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _endDate != null ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}' : 'To date',
                              style: TextStyle(
                                fontSize: 11,
                                color: _endDate != null ? AppTheme.primaryDark : Colors.grey,
                                fontWeight: _endDate != null ? FontWeight.w600 : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_startDate != null || _endDate != null) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _applyDateFilter,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                  icon: const Icon(Icons.filter_alt_outlined, size: 13),
                  label: const Text('Apply Date Filter', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
            const SizedBox(height: 14),

            // 3. Attending Doctor Filter (with dynamic count)
            const Row(
              children: [
                Icon(Icons.medical_services_outlined, color: AppTheme.primaryTeal, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text('Doctor Filter (Dynamic):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _selectedDoctor != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: allDoctors.contains(_selectedDoctor) ? _selectedDoctor : null,
                  isDense: true,
                  isExpanded: true,
                  hint: const Text('All Doctors', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'All Doctors',
                              style: TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('$totalPatients', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                          ),
                        ],
                      ),
                    ),
                    ...allDoctors.map((doc) {
                      final count = _getDoctorCount(doc, baseSummary);
                      return DropdownMenuItem<String?>(
                        value: doc,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Dr. $doc',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: count > 0 ? AppTheme.primaryTeal.withValues(alpha: 0.12) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: count > 0 ? AppTheme.primaryTeal : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedDoctor = val);
                    _onRefresh();
                    if (val != null && _tabController.index != 4) {
                      _tabController.animateTo(4);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 4. Dynamic Diagnosis Filter (with dynamic count)
            const Row(
              children: [
                Icon(Icons.healing, color: AppTheme.primaryTeal, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text('Diagnosis Filter (Dynamic):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _selectedDiagnosis != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: sortedDiagnoses.contains(_selectedDiagnosis) ? _selectedDiagnosis : null,
                  isDense: true,
                  isExpanded: true,
                  hint: const Text('All Diagnoses', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'All Diagnoses',
                              style: TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('$totalPatients', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                          ),
                        ],
                      ),
                    ),
                    ...sortedDiagnoses.map((dx) {
                      final count = _getDiagnosisCount(dx, baseSummary);
                      return DropdownMenuItem<String?>(
                        value: dx,
                        child: Row(
                          children: [
                            Expanded(child: Text(dx, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: count > 0 ? AppTheme.primaryTeal.withValues(alpha: 0.12) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: count > 0 ? AppTheme.primaryTeal : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedDiagnosis = val);
                    _onRefresh();
                    if (val != null && _tabController.index != 4) {
                      _tabController.animateTo(4);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 5. POP Staging Filter (with dynamic count)
            const Row(
              children: [
                Icon(Icons.straighten_outlined, color: AppTheme.primaryTeal, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text('POP Prolapse Stage:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _selectedPopStage != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedPopStage,
                  isDense: true,
                  isExpanded: true,
                  hint: const Text('All POP Stages', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Row(
                        children: [
                          const Expanded(child: Text('All POP Stages', style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                            child: Text('$totalPatients', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                          ),
                        ],
                      ),
                    ),
                    ...[
                      {'key': '0', 'label': 'Stage 0 (Normal / No Prolapse)'},
                      {'key': '1', 'label': 'Stage 1 (Mild Prolapse)'},
                      {'key': '2+', 'label': 'Stage >= 2 (Significant Prolapse)'},
                      {'key': '3+', 'label': 'Stage 3-4 (Severe / Procidentia)'},
                    ].map((item) {
                      final count = _getPopStageCount(item['key']!, baseSummary);
                      return DropdownMenuItem<String?>(
                        value: item['key'],
                        child: Row(
                          children: [
                            Expanded(child: Text(item['label']!, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: count > 0 ? AppTheme.primaryTeal.withValues(alpha: 0.12) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: count > 0 ? AppTheme.primaryTeal : Colors.grey.shade600),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedPopStage = val);
                    _onRefresh();
                    if (val != null && _tabController.index != 4) {
                      _tabController.animateTo(4);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 6. Reason for Visit Filter (Dynamic with live count)
            const Row(
              children: [
                Icon(Icons.how_to_reg_outlined, color: AppTheme.primaryTeal, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text('Reason for Visit (Dynamic):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _selectedVisitReason != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: dynamicVisitReasons.any((r) => r['key'] == _selectedVisitReason) ? _selectedVisitReason : null,
                  isDense: true,
                  isExpanded: true,
                  hint: const Text('All Visit Reasons', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Row(
                        children: [
                          const Expanded(child: Text('All Visit Reasons', style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                            child: Text('$totalPatients', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                          ),
                        ],
                      ),
                    ),
                    ...dynamicVisitReasons.map((item) {
                      final count = _getVisitReasonCount(item['key']!, baseSummary);
                      return DropdownMenuItem<String?>(
                        value: item['key'],
                        child: Row(
                          children: [
                            Expanded(child: Text(item['label']!, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: count > 0 ? AppTheme.primaryTeal.withValues(alpha: 0.12) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: count > 0 ? AppTheme.primaryTeal : Colors.grey.shade600),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedVisitReason = val);
                    _onRefresh();
                    if (val != null && _tabController.index != 4) {
                      _tabController.animateTo(4);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 7. Treatment & Formulary Filter (with dynamic count)
            const Row(
              children: [
                Icon(Icons.local_hospital_outlined, color: AppTheme.primaryTeal, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text('Treatment & Formulary (Dynamic):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _selectedTreatment != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: dynamicTreatments.any((t) => t['key'] == _selectedTreatment) ? _selectedTreatment : null,
                  isDense: true,
                  isExpanded: true,
                  hint: const Text('All Treatments', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Row(
                        children: [
                          const Expanded(child: Text('All Treatments', style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                            child: Text('$totalPatients', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                          ),
                        ],
                      ),
                    ),
                    ...dynamicTreatments.map((item) {
                      final count = _getTreatmentCount(item['key']!, baseSummary);
                      return DropdownMenuItem<String?>(
                        value: item['key'],
                        child: Row(
                          children: [
                            Expanded(child: Text(item['label']!, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: count > 0 ? AppTheme.primaryTeal.withValues(alpha: 0.12) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: count > 0 ? AppTheme.primaryTeal : Colors.grey.shade600),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedTreatment = val);
                    _onRefresh();
                    if (val != null && _tabController.index != 4) {
                      _tabController.animateTo(4);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 7. Chief Complaints Filter (with dynamic count)
            const Row(
              children: [
                Icon(Icons.report_problem_outlined, color: AppTheme.primaryTeal, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text('Chief Complaint (Dynamic):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _selectedComplaint != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: dynamicComplaints.any((c) => c['key'] == _selectedComplaint) ? _selectedComplaint : null,
                  isDense: true,
                  isExpanded: true,
                  hint: const Text('All Complaints', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Row(
                        children: [
                          const Expanded(child: Text('All Complaints', style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                            child: Text('$totalPatients', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                          ),
                        ],
                      ),
                    ),
                    ...dynamicComplaints.map((item) {
                      final count = _getComplaintCount(item['key']!, baseSummary);
                      return DropdownMenuItem<String?>(
                        value: item['key'],
                        child: Row(
                          children: [
                            Expanded(child: Text(item['label']!, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: count > 0 ? AppTheme.primaryTeal.withValues(alpha: 0.12) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: count > 0 ? AppTheme.primaryTeal : Colors.grey.shade600),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedComplaint = val);
                    _onRefresh();
                    if (val != null && _tabController.index != 4) {
                      _tabController.animateTo(4);
                    }
                  },
                ),
              ),
            ),

            const Divider(height: 28),

            // 8. Export Action Buttons
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
                  : const Icon(Icons.picture_as_pdf, size: 18),
              label: Text(
                reportState.isExportingPdf ? 'Generating PDF...' : 'Export PDF (पिडिएफ)',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
                  : const Icon(Icons.table_view, color: AppTheme.successGreen, size: 18),
              label: Text(
                reportState.isExportingExcel ? 'Generating Excel...' : 'Export Excel (एक्सेल)',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: reportState.isExportingPdf || reportState.isExportingExcel
                  ? null
                  : () => _exportExcel(user, deviceId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileFilterBar({
    required ReportingState reportState,
    required Set<String> allDoctors,
    required List<String> sortedDiagnoses,
    required List<Map<String, String>> dynamicTreatments,
    required List<Map<String, String>> dynamicVisitReasons,
    required List<Map<String, String>> dynamicComplaints,
  }) {
    final activeFiltersCount = (_startDate != null ? 1 : 0) +
        (_endDate != null ? 1 : 0) +
        (_selectedDoctor != null ? 1 : 0) +
        (_selectedDiagnosis != null ? 1 : 0) +
        (_selectedPopStage != null ? 1 : 0) +
        (_selectedVisitReason != null ? 1 : 0) +
        (_selectedTreatment != null ? 1 : 0) +
        (_selectedComplaint != null ? 1 : 0);
    final hasActiveFilter = activeFiltersCount > 0;
    final baseSummary = reportState.unfilteredSummary ?? reportState.summary;
    final totalPatients = baseSummary?.totalPatientsRegistered ?? 0;

    return Card(
      elevation: 0,
      color: AppTheme.brandPurpleLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppTheme.brandPurpleBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Wrap(
          alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            const Icon(Icons.date_range_outlined, size: 16, color: AppTheme.primaryTeal),
            const Text('Date Range Filter:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppTheme.primaryDark)),
            GestureDetector(
              onTap: () => _pickStartDate(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _startDate != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.calendar_today_outlined, size: 13, color: AppTheme.primaryTeal),
                  const SizedBox(width: 5),
                  Text(
                    _startDate != null ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}' : 'From date',
                    style: TextStyle(
                      fontSize: 12,
                      color: _startDate != null ? AppTheme.primaryDark : Colors.grey,
                      fontWeight: _startDate != null ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ]),
              ),
            ),
            const Text('→', style: TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold)),
            GestureDetector(
              onTap: () => _pickEndDate(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _endDate != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.calendar_today_outlined, size: 13, color: AppTheme.primaryTeal),
                  const SizedBox(width: 5),
                  Text(
                    _endDate != null ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}' : 'To date',
                    style: TextStyle(
                      fontSize: 12,
                      color: _endDate != null ? AppTheme.primaryDark : Colors.grey,
                      fontWeight: _endDate != null ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ]),
              ),
            ),
            FilledButton.icon(
              onPressed: (_startDate != null || _endDate != null) ? _applyDateFilter : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.filter_alt_outlined, size: 14),
              label: const Text('Apply', style: TextStyle(fontSize: 12)),
            ),
            // Doctor Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              constraints: const BoxConstraints(maxWidth: 175),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _selectedDoctor != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: allDoctors.contains(_selectedDoctor) ? _selectedDoctor : null,
                  isDense: true,
                  isExpanded: true,
                  hint: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.medical_services_outlined, size: 13, color: AppTheme.primaryTeal),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'All Doctors',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'All Doctors ($totalPatients)',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...allDoctors.map((doc) {
                      final count = _getDoctorCount(doc, baseSummary);
                      return DropdownMenuItem<String?>(
                        value: doc,
                        child: Text('Dr. $doc ($count)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedDoctor = val);
                    _onRefresh();
                  },
                ),
              ),
            ),
            // Diagnosis Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              constraints: const BoxConstraints(maxWidth: 175),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _selectedDiagnosis != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: sortedDiagnoses.contains(_selectedDiagnosis) ? _selectedDiagnosis : null,
                  isDense: true,
                  isExpanded: true,
                  hint: const Text('All Diagnoses', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'All Diagnoses ($totalPatients)',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...sortedDiagnoses.map((dx) {
                      final count = _getDiagnosisCount(dx, baseSummary);
                      return DropdownMenuItem<String?>(
                        value: dx,
                        child: Text('$dx ($count)', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedDiagnosis = val);
                    _onRefresh();
                  },
                ),
              ),
            ),
            // POP Stage Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              constraints: const BoxConstraints(maxWidth: 175),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _selectedPopStage != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: ['0', '1', '2+', '3+'].contains(_selectedPopStage) ? _selectedPopStage : null,
                  isDense: true,
                  isExpanded: true,
                  hint: const Text('All POP Stages', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'All POP Stages ($totalPatients)',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...[
                      {'key': '0', 'label': 'Stage 0'},
                      {'key': '1', 'label': 'Stage 1'},
                      {'key': '2+', 'label': 'Stage >= 2'},
                      {'key': '3+', 'label': 'Stage 3-4'},
                    ].map((item) {
                      final count = _getPopStageCount(item['key']!, baseSummary);
                      return DropdownMenuItem<String?>(
                        value: item['key'],
                        child: Text('${item['label']} ($count)', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedPopStage = val);
                    _onRefresh();
                  },
                ),
              ),
            ),
            // Treatment Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              constraints: const BoxConstraints(maxWidth: 175),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _selectedTreatment != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: dynamicTreatments.any((t) => t['key'] == _selectedTreatment) ? _selectedTreatment : null,
                  isDense: true,
                  isExpanded: true,
                  hint: const Text('All Treatments', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'All Treatments ($totalPatients)',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...dynamicTreatments.map((item) {
                      final count = _getTreatmentCount(item['key']!, baseSummary);
                      return DropdownMenuItem<String?>(
                        value: item['key'],
                        child: Text('${item['label']} ($count)', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedTreatment = val);
                    _onRefresh();
                  },
                ),
              ),
            ),
            // Reason for Visit Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              constraints: const BoxConstraints(maxWidth: 175),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _selectedVisitReason != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: dynamicVisitReasons.any((r) => r['key'] == _selectedVisitReason) ? _selectedVisitReason : null,
                  isDense: true,
                  isExpanded: true,
                  hint: const Text('All Visit Reasons', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'All Visit Reasons ($totalPatients)',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...dynamicVisitReasons.map((item) {
                      final count = _getVisitReasonCount(item['key']!, baseSummary);
                      return DropdownMenuItem<String?>(
                        value: item['key'],
                        child: Text('${item['label']} ($count)', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedVisitReason = val);
                    _onRefresh();
                  },
                ),
              ),
            ),
            // Chief Complaint Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              constraints: const BoxConstraints(maxWidth: 175),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _selectedComplaint != null ? AppTheme.primaryTeal : const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: dynamicComplaints.any((c) => c['key'] == _selectedComplaint) ? _selectedComplaint : null,
                  isDense: true,
                  isExpanded: true,
                  hint: const Text('All Complaints', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'All Complaints ($totalPatients)',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...dynamicComplaints.map((item) {
                      final count = _getComplaintCount(item['key']!, baseSummary);
                      return DropdownMenuItem<String?>(
                        value: item['key'],
                        child: Text('${item['label']} ($count)', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedComplaint = val);
                    _onRefresh();
                  },
                ),
              ),
            ),
            if (hasActiveFilter)
              TextButton.icon(
                onPressed: _clearAllFilters,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.close, size: 13),
                label: const Text('Clear All', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabbedAnalysisCard({
    required ReportingState reportState,
    required CampState campState,
    required UserModel? user,
    required DeviceSecurityState deviceState,
    required bool isDesktop,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 600;
          final tabHeight = isCompact ? 460.0 : (isDesktop ? 680.0 : 540.0);

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
                      reportState.selectedCampId,
                      summary: reportState.summary,
                      campState: campState,
                      user: user,
                      deviceState: deviceState,
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

  Widget _buildCampSelectorAndExportBar({
    required ReportingState reportState,
    required CampState campState,
    required UserModel? user,
    required String deviceId,
  }) {
    final isSuperAdmin = user?.role == UserRole.superAdmin;
    final visibleCamps = !isSuperAdmin && user != null
        ? campState.camps.where((c) => user.assignedCampIds.contains(c.id)).toList()
        : campState.camps;
    final allCampsLabel = isSuperAdmin
        ? 'All Camp Records (समग्र क्याम्प)'
        : 'All My Assigned Camps (${visibleCamps.length})';

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
                        hint: Text(allCampsLabel),
                        items: [
                          DropdownMenuItem<String>(
                            value: null,
                            child: Text(allCampsLabel, overflow: TextOverflow.ellipsis),
                          ),
                          ...visibleCamps.map(
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
                              hint: Text(allCampsLabel),
                              items: [
                                DropdownMenuItem<String>(
                                  value: null,
                                  child: Text(allCampsLabel, overflow: TextOverflow.ellipsis),
                                ),
                                ...visibleCamps.map(
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'District-wise Breakdown (जिल्लागत विवरण)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (summary.districtCounts.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${summary.districtCounts.length} Districts',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryTeal,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (summary.districtCounts.isEmpty)
          const Text(
            'No district distribution data available.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
          )
        else ...[
          ...(() {
            final sortedEntries = summary.districtCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            return sortedEntries.map((e) {
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
                          child: Row(
                            children: [
                              const Icon(Icons.location_on, size: 14, color: AppTheme.accentCyan),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  e.key,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '(${e.value} patients)',
                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(pct * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: AppTheme.borderLight,
                        color: AppTheme.accentCyan,
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              );
            });
          })(),
        ],
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

  Widget _buildPatientRecordsTab(
    String? campId, {
    CampReportSummaryModel? summary,
    required CampState campState,
    required UserModel? user,
    required DeviceSecurityState deviceState,
  }) {
    final patientState = ref.watch(patientListProvider);

    final effectiveCampId = campId;
    if (effectiveCampId != null &&
        (!patientState.hasLoaded || patientState.loadedCampId != effectiveCampId) &&
        !patientState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(patientListProvider.notifier).loadPatients(effectiveCampId);
      });
    } else if (effectiveCampId == null &&
        (!patientState.hasLoaded || patientState.loadedCampId != null) &&
        !patientState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(patientListProvider.notifier).loadPatients(null);
      });
    }

    // Source of truth is summary.patients (which reflects all active filters and camp selection)
    final sourcePatients = summary?.patients ?? patientState.patients;

    final query = _patientSearchController.text.trim().toLowerCase();
    final patients = sourcePatients.where((p) {
      if (query.isEmpty) return true;
      return p.fullName.toLowerCase().contains(query) ||
          p.patientId.toLowerCase().contains(query) ||
          p.mobile.contains(query) ||
          p.ward.toLowerCase().contains(query) ||
          p.municipality.toLowerCase().contains(query);
    }).toList();

    final visitByPatientId = <String, ClinicalVisitModel>{};
    if (summary != null) {
      for (final v in summary.visits) {
        visitByPatientId[v.patientId] = v;
      }
    }
    final unfilt = ref.watch(reportingViewModelProvider).unfilteredSummary;
    if (unfilt != null) {
      for (final v in unfilt.visits) {
        visitByPatientId.putIfAbsent(v.patientId, () => v);
      }
    }
    final campById = {for (final c in campState.camps) c.id: c};

    final hasActiveFilter = (_startDate != null) ||
        (_endDate != null) ||
        (_selectedDoctor != null) ||
        (_selectedDiagnosis != null) ||
        (_selectedPopStage != null) ||
        (_selectedTreatment != null) ||
        (_selectedComplaint != null);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMasterDetail = constraints.maxWidth >= 650;

        if (isMasterDetail) {
          final currentSelected = (_selectedPatient != null &&
                  patients.any((p) => p.patientId == _selectedPatient!.patientId))
              ? _selectedPatient
              : (patients.isNotEmpty ? patients.first : null);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Master Pane: Patient List (Left) ──
              SizedBox(
                width: constraints.maxWidth > 900 ? 350 : 300,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _patientSearchController,
                            decoration: InputDecoration(
                              hintText: 'Search by name, ID, ward, phone...',
                              prefixIcon: const Icon(Icons.search, size: 18),
                              suffixIcon: _patientSearchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 16),
                                      onPressed: () => setState(() => _patientSearchController.clear()),
                                    )
                                  : null,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Showing ${patients.length} patient${patients.length == 1 ? '' : 's'}',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                              ),
                              if (hasActiveFilter)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: AppTheme.dangerRose.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Filtered',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.dangerRose),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (patientState.isLoading && patientState.patients.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: LinearProgressIndicator(
                          color: AppTheme.primaryTeal,
                          backgroundColor: AppTheme.primaryLight,
                          minHeight: 2,
                        ),
                      ),
                    Expanded(
                      child: (patientState.isLoading && sourcePatients.isEmpty)
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
                                  child: Padding(
                                    padding: const EdgeInsets.all(20.0),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.person_search_outlined, size: 40, color: Colors.grey),
                                        const SizedBox(height: 8),
                                        Text(
                                          _patientSearchController.text.isNotEmpty
                                              ? 'No matching patients found for "${_patientSearchController.text.trim()}".'
                                              : (hasActiveFilter ? 'No patients match the active filters.' : 'No patient records found in this camp.'),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: AppTheme.textSecondaryLight, fontSize: 12.5),
                                        ),
                                        if (hasActiveFilter) ...[
                                          const SizedBox(height: 8),
                                          TextButton.icon(
                                            onPressed: _clearAllFilters,
                                            icon: const Icon(Icons.clear_all, size: 14),
                                            label: const Text('Reset All Filters', style: TextStyle(fontSize: 11.5)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  itemCount: patients.length,
                                  itemBuilder: (context, index) {
                                    final patient = patients[index];
                                    final isSelected = currentSelected?.patientId == patient.patientId;
                                    final isExporting = _exportingPatientId == patient.patientId;

                                    return _buildPatientCardItem(
                                      patient: patient,
                                      visit: visitByPatientId[patient.patientId],
                                      camp: campById[patient.campId],
                                      isSelected: isSelected,
                                      isExporting: isExporting,
                                      onTap: () => setState(() => _selectedPatient = patient),
                                      onExportPdf: () => _exportIndividualPatientPdf(
                                        patient,
                                        campState,
                                        user,
                                        deviceState,
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              // ── Detail Pane: Patient Clinical Dossier (Right) ──
              Expanded(
                child: currentSelected != null
                    ? _buildPatientDetailPane(
                        patient: currentSelected,
                        summary: summary,
                        campState: campState,
                        user: user,
                        deviceState: deviceState,
                      )
                    : const Center(
                        child: Text(
                          'Select a patient on the left to view clinical details.',
                          style: TextStyle(color: AppTheme.textSecondaryLight),
                        ),
                      ),
              ),
            ],
          );
        }

        // ── Mobile / Narrow Layout (< 650) ──
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _patientSearchController,
                    decoration: InputDecoration(
                      hintText: 'Search patients by name, ID, ward, phone...',
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
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Showing ${patients.length} patient${patients.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                      ),
                      if (hasActiveFilter)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.dangerRose.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Filtered',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.dangerRose),
                          ),
                        ),
                    ],
                  ),
                ],
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
              child: (patientState.isLoading && sourcePatients.isEmpty)
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
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.person_search_outlined, size: 40, color: Colors.grey),
                                const SizedBox(height: 8),
                                Text(
                                  _patientSearchController.text.isNotEmpty
                                      ? 'No matching patients found for "${_patientSearchController.text.trim()}".'
                                      : (hasActiveFilter ? 'No patients match the active filters.' : 'No patient records found in this camp.'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: AppTheme.textSecondaryLight, fontSize: 13),
                                ),
                                if (hasActiveFilter) ...[
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    onPressed: _clearAllFilters,
                                    icon: const Icon(Icons.clear_all, size: 14),
                                    label: const Text('Reset All Filters', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: patients.length,
                          itemBuilder: (context, index) {
                            final patient = patients[index];
                            final isExporting = _exportingPatientId == patient.patientId;

                            return _buildPatientCardItem(
                              patient: patient,
                              visit: visitByPatientId[patient.patientId],
                              camp: campById[patient.campId],
                              isSelected: false,
                              isExporting: isExporting,
                              onTap: () {
                                _showPatientDetailModal(
                                  context: context,
                                  patient: patient,
                                  summary: summary,
                                  campState: campState,
                                  user: user,
                                  deviceState: deviceState,
                                );
                              },
                              onExportPdf: () => _exportIndividualPatientPdf(
                                patient,
                                campState,
                                user,
                                deviceState,
                              ),
                              onViewClinical: () {
                                _showPatientDetailModal(
                                  context: context,
                                  patient: patient,
                                  summary: summary,
                                  campState: campState,
                                  user: user,
                                  deviceState: deviceState,
                                );
                              },
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPatientCardItem({
    required PatientModel patient,
    required ClinicalVisitModel? visit,
    required CampModel? camp,
    required bool isSelected,
    required bool isExporting,
    required VoidCallback onTap,
    required VoidCallback onExportPdf,
    VoidCallback? onViewClinical,
  }) {
    final campCode = camp?.campCode ??
        (patient.campCode.isNotEmpty
            ? patient.campCode
            : (patient.patientId.split('-').length >= 2 ? patient.patientId.split('-')[1] : ''));

    final docName = visit?.primaryDoctorName != null && visit!.primaryDoctorName!.trim().isNotEmpty
        ? visit.primaryDoctorName!.trim()
        : (visit?.attendingDoctorNames.any((d) => d.trim().isNotEmpty) == true
            ? visit!.attendingDoctorNames.firstWhere((d) => d.trim().isNotEmpty)
            : (patient.primaryDoctorName != null && patient.primaryDoctorName!.trim().isNotEmpty
                ? patient.primaryDoctorName!.trim()
                : null));

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryTeal.withValues(alpha: 0.08) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? AppTheme.primaryTeal : AppTheme.borderLight,
          width: isSelected ? 1.8 : 1.0,
        ),
        boxShadow: isSelected
            ? [BoxShadow(color: AppTheme.primaryTeal.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 2))]
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Avatar, Name, ID badge
              Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: isSelected ? AppTheme.primaryTeal : AppTheme.primaryTeal.withValues(alpha: 0.15),
                    child: Text(
                      patient.firstName.isNotEmpty ? patient.firstName[0].toUpperCase() : 'P',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : AppTheme.primaryTeal,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      patient.fullName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isSelected ? AppTheme.primaryTeal : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      patient.patientId,
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Row 2: Camp Pill & Doctor Pill
              Row(
                children: [
                  if (campCode.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFBAE6FD)),
                      ),
                      child: Text(
                        'Camp $campCode',
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF0369A1)),
                      ),
                    ),
                  if (docName != null)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.brandPurpleLight,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppTheme.brandPurpleBorder),
                        ),
                        child: Text(
                          '🩺 Dr. $docName',
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppTheme.brandPurple),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),

              // Row 3: Demographics
              Text(
                'Age: ${patient.age}y • Ward: ${patient.ward.isNotEmpty ? patient.ward : "-"} • 📞 ${patient.mobile.isNotEmpty ? patient.mobile : "N/A"}',
                style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondaryLight),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),

              // Row 4: Clinical Status Pills (if visit available)
              if (visit != null) ...[
                Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children: [
                    _buildPopStageChip(visit.highestPopStage),
                    if (visit.pessaryType != null && visit.pessaryType!.isNotEmpty)
                      _buildSmallStatusChip('💍 Pessary', AppTheme.brandPurple, AppTheme.brandPurpleLight),
                    if (visit.surgicalReferral != null && visit.surgicalReferral!.isNotEmpty)
                      _buildSmallStatusChip('🏥 Surgery Ref', const Color(0xFF7C3AED), const Color(0xFFEDE9FE)),
                    if (visit.diagnoses.isNotEmpty)
                      _buildSmallStatusChip(visit.diagnoses.first, const Color(0xFF2563EB), const Color(0xFFDBEAFE)),
                  ],
                ),
                const SizedBox(height: 6),
              ],

              // Row 5: Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryTeal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: isExporting
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.picture_as_pdf, size: 12),
                      label: Text(
                        isExporting ? 'Exporting...' : 'PDF Dossier',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: isExporting ? null : onExportPdf,
                    ),
                  ),
                  if (onViewClinical != null) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.medical_information_outlined, size: 12, color: AppTheme.primaryTeal),
                        label: const Text(
                          'Clinical View',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: onViewClinical,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPopStageChip(int stage) {
    final Color textColor;
    final Color bgColor;
    final String label;

    if (stage == 0) {
      label = 'POP Stage 0 (Normal)';
      textColor = const Color(0xFF047857);
      bgColor = const Color(0xFFD1FAE5);
    } else if (stage == 1) {
      label = 'POP Stage 1';
      textColor = const Color(0xFF0369A1);
      bgColor = const Color(0xFFE0F2FE);
    } else if (stage == 2) {
      label = 'POP Stage 2';
      textColor = const Color(0xFFB45309);
      bgColor = const Color(0xFFFEF3C7);
    } else {
      label = 'POP Stage $stage';
      textColor = const Color(0xFFB91C1C);
      bgColor = const Color(0xFFFEE2E2);
    }

    return _buildSmallStatusChip(label, textColor, bgColor);
  }

  Widget _buildSmallStatusChip(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: textColor),
      ),
    );
  }

  Widget _buildPatientDetailPane({
    required PatientModel patient,
    required CampReportSummaryModel? summary,
    required CampState campState,
    required UserModel? user,
    required DeviceSecurityState deviceState,
  }) {
    ClinicalVisitModel? visit;
    if (summary != null) {
      for (final v in summary.visits) {
        if (v.patientId == patient.patientId) {
          visit = v;
          break;
        }
      }
    }

    final isExporting = _exportingPatientId == patient.patientId;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Patient Dossier Header ──
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryTeal.withValues(alpha: 0.12), AppTheme.accentCyan.withValues(alpha: 0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                ),
                child: isCompact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: AppTheme.primaryTeal,
                                child: Text(
                                  patient.firstName.isNotEmpty ? patient.firstName[0].toUpperCase() : 'P',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            patient.fullName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryDark),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryTeal,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            patient.patientId,
                                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Builder(builder: (context) {
                                      final campObj = campState.camps.where((c) => c.id == patient.campId).firstOrNull;
                                      final campText = campObj != null ? '${campObj.name} (${campObj.campCode})' : 'Camp ID: ${patient.campId}';
                                      return Text(
                                        '🎪 $campText',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryTeal),
                                      );
                                    }),
                                    Text(
                                      'Age: ${patient.age}y • Marital: ${patient.maritalStatus.isNotEmpty ? patient.maritalStatus : "N/A"} • Parity: ${visit?.deliveries ?? "N/A"} • Ward: ${patient.ward}',
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
                                    ),
                                    Text(
                                      'Mobile: ${patient.mobile.isNotEmpty ? patient.mobile : "N/A"} • District: ${patient.district.isNotEmpty ? patient.district : "N/A"}',
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryTeal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: isExporting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.picture_as_pdf, size: 16),
                            label: Text(
                              isExporting ? 'Exporting...' : 'Export PDF Dossier (पिडिएफ)',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: AppTheme.primaryTeal,
                            child: Text(
                              patient.firstName.isNotEmpty ? patient.firstName[0].toUpperCase() : 'P',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        patient.fullName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryDark),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryTeal,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        patient.patientId,
                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Builder(builder: (context) {
                                  final campObj = campState.camps.where((c) => c.id == patient.campId).firstOrNull;
                                  final campText = campObj != null ? '${campObj.name} (${campObj.campCode})' : 'Camp ID: ${patient.campId}';
                                  return Text(
                                    '🎪 $campText',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryTeal),
                                  );
                                }),
                                Text(
                                  'Age: ${patient.age}y • Marital: ${patient.maritalStatus.isNotEmpty ? patient.maritalStatus : "N/A"} • Parity: ${visit?.deliveries ?? "N/A"} • Ward: ${patient.ward}',
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
                                ),
                                Text(
                                  'Mobile: ${patient.mobile.isNotEmpty ? patient.mobile : "N/A"} • District: ${patient.district.isNotEmpty ? patient.district : "N/A"}',
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryTeal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: isExporting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.picture_as_pdf, size: 16),
                            label: Text(
                              isExporting ? 'Exporting...' : 'PDF Dossier',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
                        ],
                      ),
              ),
              const SizedBox(height: 14),

              if (visit != null) ...[
                // ── Vitals & Triage Metrics ──
                const Text(
                  'Clinical Vitals & Measurements',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.primaryDark),
                ),
                const SizedBox(height: 8),
                if (isCompact) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _buildVitalTile(
                          'Blood Pressure',
                          (visit.systolicBp != null && visit.diastolicBp != null)
                              ? '${visit.systolicBp}/${visit.diastolicBp}'
                              : 'N/A',
                          'mmHg',
                          isAlert: (visit.systolicBp != null && visit.systolicBp! >= 140) ||
                              (visit.diastolicBp != null && visit.diastolicBp! >= 90),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildVitalTile(
                          'Pulse Rate',
                          visit.pulse != null ? '${visit.pulse}' : 'N/A',
                          'bpm',
                          isAlert: visit.pulse != null && (visit.pulse! > 100 || visit.pulse! < 50),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildVitalTile(
                          'Oxygen (SpO2)',
                          visit.spo2 != null ? '${visit.spo2}' : 'N/A',
                          '%',
                          isAlert: visit.spo2 != null && visit.spo2! < 94,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildVitalTile(
                          'Blood Glucose',
                          visit.glucose != null ? '${visit.glucose}' : 'N/A',
                          'mg/dL',
                          isAlert: visit.glucose != null && visit.glucose! > 180,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: _buildVitalTile(
                          'Blood Pressure',
                          (visit.systolicBp != null && visit.diastolicBp != null)
                              ? '${visit.systolicBp}/${visit.diastolicBp}'
                              : 'N/A',
                          'mmHg',
                          isAlert: (visit.systolicBp != null && visit.systolicBp! >= 140) ||
                              (visit.diastolicBp != null && visit.diastolicBp! >= 90),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildVitalTile(
                          'Pulse Rate',
                          visit.pulse != null ? '${visit.pulse}' : 'N/A',
                          'bpm',
                          isAlert: visit.pulse != null && (visit.pulse! > 100 || visit.pulse! < 50),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildVitalTile(
                          'Oxygen (SpO2)',
                          visit.spo2 != null ? '${visit.spo2}' : 'N/A',
                          '%',
                          isAlert: visit.spo2 != null && visit.spo2! < 94,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildVitalTile(
                          'Blood Glucose',
                          visit.glucose != null ? '${visit.glucose}' : 'N/A',
                          'mg/dL',
                          isAlert: visit.glucose != null && visit.glucose! > 180,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),

                // ── POP Staging Dossier ──
                Card(
                  elevation: 0,
                  color: const Color(0xFFF8FAFC),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.healing, color: AppTheme.primaryTeal, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Pelvic Organ Prolapse (POP) Staging',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                            _buildPopStageBadge(visit.highestPopStage),
                          ],
                        ),
                        const Divider(height: 16),
                        if (isCompact) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Expanded(child: _buildCompartmentStage('Anterior Wall', visit.popAnteriorStage)),
                              Expanded(child: _buildCompartmentStage('Apical / Cervix', visit.popMiddleStage)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Expanded(child: _buildCompartmentStage('Posterior Wall', visit.popPosteriorStage)),
                              Expanded(child: _buildCompartmentStage('Pelvic Floor Tone', visit.pelvicFloorTone)),
                            ],
                          ),
                        ] else ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildCompartmentStage('Anterior Wall', visit.popAnteriorStage),
                              _buildCompartmentStage('Apical / Cervix', visit.popMiddleStage),
                              _buildCompartmentStage('Posterior Wall', visit.popPosteriorStage),
                              _buildCompartmentStage('Pelvic Floor Tone', visit.pelvicFloorTone),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ── Diagnoses & Interventions ──
                if (isCompact) ...[
                  _buildDiagnosesCard(visit),
                  const SizedBox(height: 12),
                  _buildTreatmentPlanCard(visit),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildDiagnosesCard(visit)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildTreatmentPlanCard(visit)),
                    ],
                  ),
                ],
                const SizedBox(height: 12),

                // Attending Doctor Footer
                if ((visit.primaryDoctorName != null && visit.primaryDoctorName!.trim().isNotEmpty) ||
                    visit.attendingDoctorNames.any((d) => d.trim().isNotEmpty))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user_outlined, size: 15, color: AppTheme.primaryTeal),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Attending Clinician: ${(visit.primaryDoctorName != null && visit.primaryDoctorName!.trim().isNotEmpty) ? visit.primaryDoctorName! : visit.attendingDoctorNames.where((d) => d.trim().isNotEmpty).join(", ")}',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.pending_actions_outlined, size: 36, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'Camp Registration Completed • Examination Pending',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'No clinical examination visit recorded yet for this patient in the selected camp session.',
                        style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondaryLight),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiagnosesCard(ClinicalVisitModel visit) {
    return Card(
      elevation: 0,
      color: const Color(0xFFF0FDF4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFBBF7D0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.medication_outlined, size: 16, color: AppTheme.successGreen),
                SizedBox(width: 6),
                Text('Diagnoses (रोग निदान)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            if (visit.diagnoses.isEmpty)
              const Text('No diagnoses specified', style: TextStyle(fontSize: 12, color: Colors.grey))
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: visit.diagnoses.map((d) {
                  return Chip(
                    label: Text(d, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF86EFAC)),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTreatmentPlanCard(ClinicalVisitModel visit) {
    return Card(
      elevation: 0,
      color: const Color(0xFFEFF6FF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFBFDBFE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.local_hospital_outlined, size: 16, color: Color(0xFF2563EB)),
                SizedBox(width: 6),
                Text('Treatment Plan (उपचार)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            if (visit.pessaryType != null && visit.pessaryType!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• Ring Pessary: ${visit.pessaryType} (Size: ${visit.pessarySize ?? "Standard"})',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            if (visit.surgicalReferral != null && visit.surgicalReferral!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• Surgical Referral: ${visit.surgicalReferral}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.dangerRose),
                ),
              ),
            if (visit.medications.isNotEmpty || (visit.customMedication != null && visit.customMedication!.trim().isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• Medications: ${[
                    ...visit.medications,
                    if (visit.customMedication != null && visit.customMedication!.trim().isNotEmpty)
                      visit.customMedication!.trim(),
                  ].join(", ")}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            if (visit.counseling.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• Counseling: ${visit.counseling.join(", ")}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            if (visit.pessaryType == null &&
                visit.surgicalReferral == null &&
                visit.medications.isEmpty &&
                (visit.customMedication == null || visit.customMedication!.trim().isEmpty) &&
                visit.counseling.isEmpty)
              const Text('No specific intervention recorded', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildVitalTile(String label, String value, String unit, {bool isAlert = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isAlert ? AppTheme.dangerRose.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isAlert ? AppTheme.dangerRose : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondaryLight), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: isAlert ? AppTheme.dangerRose : AppTheme.primaryDark,
                ),
              ),
              const SizedBox(width: 3),
              Text(unit, style: const TextStyle(fontSize: 9.5, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPopStageBadge(int stage) {
    Color bg = const Color(0xFFDCFCE7);
    Color fg = const Color(0xFF166534);
    if (stage == 1) {
      bg = const Color(0xFFE0F2FE);
      fg = const Color(0xFF0369A1);
    } else if (stage == 2) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFB45309);
    } else if (stage >= 3) {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFFB91C1C);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(
        'Stage $stage',
        style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  Widget _buildCompartmentStage(String label, dynamic stage) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondaryLight)),
        const SizedBox(height: 2),
        Text(
          stage is int ? 'Stage $stage' : '$stage',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  void _showPatientDetailModal({
    required BuildContext context,
    required PatientModel patient,
    required CampReportSummaryModel? summary,
    required CampState campState,
    required UserModel? user,
    required DeviceSecurityState deviceState,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: _buildPatientDetailPane(
                    patient: patient,
                    summary: summary,
                    campState: campState,
                    user: user,
                    deviceState: deviceState,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
