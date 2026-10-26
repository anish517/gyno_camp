import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/clinical_constants.dart';
import '../../core/services/file_download_helper.dart';
import '../../core/services/clinical_validation_service.dart';
import '../../core/services/nepali_localization_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/clinical_visit_model.dart';
import '../../models/patient_model.dart';
import '../../models/user_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../models/camp_model.dart';
import '../../models/lookup_item_model.dart';
import '../../viewmodels/clinical_assessment_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../../viewmodels/master_lookup_viewmodel.dart';
import '../../viewmodels/reporting_viewmodel.dart';

class ClinicalAssessmentView extends ConsumerStatefulWidget {
  final PatientModel patient;

  const ClinicalAssessmentView({super.key, required this.patient});

  @override
  ConsumerState<ClinicalAssessmentView> createState() => _ClinicalAssessmentViewState();
}

class _ClinicalAssessmentViewState extends ConsumerState<ClinicalAssessmentView> {
  // Controllers
  final _deliveriesController = TextEditingController();
  final _livingChildrenController = TextEditingController();
  final _abortionsController = TextEditingController();

  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _pulseController = TextEditingController();
  final _spo2Controller = TextEditingController();
  final _glucoseController = TextEditingController();
  final _ecgController = TextEditingController();

  final _vulvaRemarksController = TextEditingController();
  final _vaginaRemarksController = TextEditingController();
  final _cervixRemarksController = TextEditingController();
  final _uterusRemarksController = TextEditingController();
  final _pessarySizeController = TextEditingController();
  final _customMedController = TextEditingController();
  final _outtakeNotesController = TextEditingController();
  final _customFollowUpHospitalController = TextEditingController();
  final Map<String, TextEditingController> _complaintRemarksControllers = {};
  final Set<String> _expandedComplaints = {};
  final Set<String> _collapsedComplaints = {};

  TextEditingController _getRemarksController(String key, String initialText) {
    if (!_complaintRemarksControllers.containsKey(key)) {
      _complaintRemarksControllers[key] = TextEditingController(text: initialText);
    } else if (initialText.isNotEmpty && _complaintRemarksControllers[key]!.text.isEmpty) {
      _complaintRemarksControllers[key]!.text = initialText;
    }
    return _complaintRemarksControllers[key]!;
  }

  bool _isDurationMatch(String d, String? sel) {
    if (sel == null || sel.trim().isEmpty) return false;
    final dNorm = d.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final sNorm = sel.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (dNorm == sNorm) return true;
    if (dNorm.contains('1month') && (sNorm.contains('1m') || sNorm.contains('1month'))) return true;
    if (dNorm.contains('<1year') && (sNorm.contains('<1y') || sNorm.contains('<1year'))) return true;
    if (dNorm.contains('>1year') && (sNorm.contains('>1y') || sNorm.contains('>1year'))) return true;
    if (dNorm.contains('>5year') && (sNorm.contains('>5y') || sNorm.contains('>5year'))) return true;
    if (dNorm.contains('>10year') && (sNorm.contains('>10y') || sNorm.contains('>10year'))) return true;
    return false;
  }

  Map<String, dynamic> _resolveComplaintData(Map<String, dynamic> complaints, String complaintKey) {
    if (complaints.isEmpty) return const {};
    if (complaints[complaintKey] is Map && (complaints[complaintKey] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(complaints[complaintKey] as Map);
    }
    final lowerKey = complaintKey.toLowerCase().trim();
    if (complaints[lowerKey] is Map && (complaints[lowerKey] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(complaints[lowerKey] as Map);
    }
    final withSpaces = lowerKey.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    final withUnderscores = lowerKey.replaceAll(RegExp(r'[\s\-]+'), '_').trim();
    if (complaints[withSpaces] is Map && (complaints[withSpaces] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(complaints[withSpaces] as Map);
    }
    if (complaints[withUnderscores] is Map && (complaints[withUnderscores] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(complaints[withUnderscores] as Map);
    }

    final List<String> aliases = [];
    if (lowerKey.contains('prolapse') || lowerKey.contains('hanging') || lowerKey.contains('पाठेघर') || lowerKey.contains('mass')) {
      aliases.addAll(['prolapse', 'something hanging out', 'something_hanging_out']);
    } else if (lowerKey.contains('discharge') || lowerKey.contains('itching') || lowerKey.contains('स्राव') || lowerKey.contains('चिलाउने')) {
      aliases.addAll(['discharge', 'discharge and or itching', 'discharge_and_or_itching', 'discharge / itching', 'discharge___itching', 'discharge_itching']);
    } else if (lowerKey.contains('urine') || lowerKey.contains('पिसाब') || lowerKey.contains('micturition')) {
      aliases.addAll(['urine', 'problems passing urine', 'problems_passing_urine']);
    } else if (lowerKey.contains('stool') || lowerKey.contains('दिसा') || lowerKey.contains('bowel')) {
      aliases.addAll(['stool', 'problems passing stool', 'problems_passing_stool']);
    } else if (lowerKey.contains('menstrual') || lowerKey.contains('महिनावारी')) {
      aliases.addAll(['menstrual', 'menstrual problem', 'menstrual_problem']);
    } else if (lowerKey.contains('infertility') || lowerKey.contains('बाँझोपन') || lowerKey.contains('निःसन्तान')) {
      aliases.addAll(['infertility']);
    } else if (lowerKey.contains('abdomen') || lowerKey.contains('तल्लो पेट')) {
      aliases.addAll(['lower_abdomen_pain', 'lower abdomen pain', 'pain']);
    } else if (lowerKey.contains('back') || lowerKey.contains('ढाड') || lowerKey.contains('कम्मर')) {
      aliases.addAll(['lower_back_pain', 'lower back pain', 'pain']);
    } else if (lowerKey == 'pain' || lowerKey.contains('दुख्ने')) {
      aliases.addAll(['pain', 'lower_abdomen_pain', 'lower_back_pain']);
    } else if (lowerKey.contains('checkup') || lowerKey.contains('जाँच')) {
      aliases.addAll(['checkup']);
    }

    for (final a in aliases) {
      if (complaints[a] is Map && (complaints[a] as Map).isNotEmpty) {
        return Map<String, dynamic>.from(complaints[a] as Map);
      }
    }

    for (final entry in complaints.entries) {
      if (entry.value is! Map || (entry.value as Map).isEmpty) continue;
      final k = entry.key.toLowerCase().trim();
      final kClean = k.replaceAll(RegExp(r'[^a-z0-9]'), '');
      final keyClean = lowerKey.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (kClean.isNotEmpty && keyClean.isNotEmpty && (kClean.contains(keyClean) || keyClean.contains(kClean))) {
        return Map<String, dynamic>.from(entry.value as Map);
      }
    }
    return const {};
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.patient.campId.isNotEmpty) {
        ref.read(masterLookupProvider.notifier).setCampScope(widget.patient.campId);
      }
      final existing = await ref.read(clinicalAssessmentProvider.notifier).loadPatientAssessment(
        widget.patient.patientId,
        patientUuid: widget.patient.id,
      );
      if (existing != null && mounted) {
        _populateControllers(existing);
      }
    });
  }

  void _populateControllers(ClinicalVisitModel visit) {
    if (visit.deliveries != null) _deliveriesController.text = visit.deliveries.toString();
    if (visit.livingChildren != null) _livingChildrenController.text = visit.livingChildren.toString();
    if (visit.abortions != null) _abortionsController.text = visit.abortions.toString();
    if (visit.systolicBp != null) _systolicController.text = visit.systolicBp.toString();
    if (visit.diastolicBp != null) _diastolicController.text = visit.diastolicBp.toString();
    if (visit.pulse != null) _pulseController.text = visit.pulse.toString();
    if (visit.spo2 != null) _spo2Controller.text = visit.spo2.toString();
    if (visit.glucose != null) _glucoseController.text = visit.glucose.toString();
    if (visit.ecgNotes != null && visit.ecgNotes!.isNotEmpty) _ecgController.text = visit.ecgNotes!;
    if (visit.vulvaRemarks != null && visit.vulvaRemarks!.isNotEmpty) _vulvaRemarksController.text = visit.vulvaRemarks!;
    if (visit.vaginaRemarks != null && visit.vaginaRemarks!.isNotEmpty) _vaginaRemarksController.text = visit.vaginaRemarks!;
    if (visit.cervixRemarks != null && visit.cervixRemarks!.isNotEmpty) _cervixRemarksController.text = visit.cervixRemarks!;
    if (visit.uterusRemarks != null && visit.uterusRemarks!.isNotEmpty) _uterusRemarksController.text = visit.uterusRemarks!;
    if (visit.pessarySize != null && visit.pessarySize!.isNotEmpty) _pessarySizeController.text = visit.pessarySize!;
    if (visit.customMedication != null && visit.customMedication!.isNotEmpty) _customMedController.text = visit.customMedication!;
    if (visit.outtakeNotes != null && visit.outtakeNotes!.isNotEmpty) _outtakeNotesController.text = visit.outtakeNotes!;
    final partnerHospitals = ref.read(masterLookupProvider).activeReferralHospitals
        .map((h) => h.labelEn)
        .where((h) => h != 'Health Post' && h != 'GynaeSupport Nurse' && h != 'Other')
        .toList();
    if (visit.followUpDestination != null &&
        visit.followUpDestination!.isNotEmpty &&
        visit.followUpDestination != 'Health Post' &&
        visit.followUpDestination != 'GynaeSupport Nurse' &&
        !partnerHospitals.contains(visit.followUpDestination)) {
      _customFollowUpHospitalController.text = visit.followUpDestination!;
    }
    final existingComplaints = visit.anamnesisComplaints;
    for (final entry in existingComplaints.entries) {
      if (entry.value is Map) {
        final rem = entry.value['remarks'] as String?;
        if (rem != null && rem.isNotEmpty) {
          _getRemarksController(entry.key, rem).text = rem;
          final lk = entry.key.toLowerCase().trim();
          final withSpaces = lk.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
          final withUnderscores = lk.replaceAll(RegExp(r'[\s\-]+'), '_').trim();
          _getRemarksController(lk, rem).text = rem;
          _getRemarksController(withSpaces, rem).text = rem;
          _getRemarksController(withUnderscores, rem).text = rem;
        }
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _deliveriesController.dispose();
    _livingChildrenController.dispose();
    _abortionsController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _pulseController.dispose();
    _spo2Controller.dispose();
    _glucoseController.dispose();
    _ecgController.dispose();
    _vulvaRemarksController.dispose();
    _vaginaRemarksController.dispose();
    _cervixRemarksController.dispose();
    _uterusRemarksController.dispose();
    _pessarySizeController.dispose();
    _customMedController.dispose();
    _outtakeNotesController.dispose();
    _customFollowUpHospitalController.dispose();
    for (final c in _complaintRemarksControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clinicalAssessmentProvider);
    final vm = ref.read(clinicalAssessmentProvider.notifier);
    final user = ref.watch(authStateProvider).currentUser;
    final device = ref.watch(deviceSecurityProvider).device;
    final campState = ref.watch(campStateProvider);

    // CAMP LOCK CHECK
    CampModel? patientCamp;
    try {
      patientCamp = campState.camps.firstWhere((c) => c.id == widget.patient.campId);
    } catch (_) {}
    final isLockedCamp = patientCamp != null && patientCamp.status.isLocked;
    final isSuperAdmin = user?.role == UserRole.superAdmin;
    final isEffectivelyLocked = isLockedCamp && !isSuperAdmin;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: AppTheme.brandAppBarFlexibleSpace,
        bottom: AppTheme.brandAppBarBottomLine,
        iconTheme: const IconThemeData(color: Color(0xFF1E0A38)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Clinical Intake • ${widget.patient.fullName}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF1E0A38),
                fontWeight: FontWeight.w800,
                fontSize: 17.5,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'ID: ${widget.patient.patientId} • Age: ${widget.patient.age} • Ward: ${widget.patient.ward}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: 'Download Patient Clinical Summary (PDF)',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Generating clinical summary PDF for ${widget.patient.fullName}...'),
                  duration: const Duration(seconds: 1),
                ),
              );

              final activeCamp = ref.read(campStateProvider).activeCamp;
              final complaintsMap = Map<String, dynamic>.from(state.complaints);
              if (complaintsMap.isEmpty && state.savedVisit?.anamnesisComplaints != null) {
                complaintsMap.addAll(state.savedVisit!.anamnesisComplaints);
              }
              final activeKeys = <String>{};
              for (final entry in complaintsMap.entries) {
                if (entry.key == 'clinicalComplaints' || entry.key == 'complaintsDuration') continue;
                if (entry.value is Map) {
                  final m = entry.value as Map;
                  if (m['active'] == true ||
                      m['present'] == true ||
                      ((m['duration'] as String?)?.isNotEmpty == true) ||
                      ((m['subOption'] as String?)?.isNotEmpty == true) ||
                      (m['options'] is List && (m['options'] as List).isNotEmpty) ||
                      ((m['remarks'] as String?)?.isNotEmpty == true)) {
                    final k = entry.key.toLowerCase().replaceAll(RegExp(r'[_\-\s]+'), ' ').trim();
                    if (k.contains('prolapse') || k.contains('hanging')) {
                      activeKeys.add('prolapse');
                    } else if (k.contains('discharge') || k.contains('itching')) {
                      activeKeys.add('discharge');
                    } else if (k.contains('urine')) {
                      activeKeys.add('urine');
                    } else if (k.contains('stool')) {
                      activeKeys.add('stool');
                    } else if (k.contains('menstrual')) {
                      activeKeys.add('menstrual');
                    } else if (k.contains('infertility')) {
                      activeKeys.add('infertility');
                    } else if (k.contains('abdomen')) {
                      activeKeys.add('lower_abdomen_pain');
                    } else if (k.contains('back')) {
                      activeKeys.add('lower_back_pain');
                    } else if (k.contains('checkup')) {
                      activeKeys.add('checkup');
                    } else {
                      activeKeys.add(entry.key);
                    }
                  }
                }
              }
              if (activeKeys.isNotEmpty) {
                complaintsMap['clinicalComplaints'] = activeKeys.toList();
              }

              final currentVisit = ClinicalVisitModel(
                id: state.existingVisitId ?? state.savedVisit?.id ?? 'visit-draft',
                patientId: widget.patient.patientId,
                campId: widget.patient.campId,
                visitDate: state.visitDate ?? state.savedVisit?.visitDate ?? DateTime.now(),
                deliveries: state.deliveries ?? state.savedVisit?.deliveries,
                livingChildren: state.livingChildren ?? state.savedVisit?.livingChildren,
                abortions: state.abortions ?? state.savedVisit?.abortions,
                anamnesisComplaints: complaintsMap,
                uterusInside: state.uterusInside,
                vulvaRemarks: state.vulvaRemarks ?? state.savedVisit?.vulvaRemarks,
                vaginaRemarks: state.vaginaRemarks ?? state.savedVisit?.vaginaRemarks,
                cervixRemarks: state.cervixRemarks ?? state.savedVisit?.cervixRemarks,
                uterusRemarks: state.uterusRemarks ?? state.savedVisit?.uterusRemarks,
                pelvicFloorTone: state.pelvicFloorTone,
                popAnteriorStage: state.popAnteriorStage,
                popMiddleStage: state.popMiddleStage,
                popPosteriorStage: state.popPosteriorStage,
                highestPopStage: state.highestPopStage,
                urineTest: state.urineTest ?? state.savedVisit?.urineTest ?? 'normal',
                pregnancyTest: state.pregnancyTest ?? state.savedVisit?.pregnancyTest ?? 'neg',
                systolicBp: state.systolicBp ?? state.savedVisit?.systolicBp,
                diastolicBp: state.diastolicBp ?? state.savedVisit?.diastolicBp,
                pulse: state.pulse ?? state.savedVisit?.pulse,
                spo2: state.spo2 ?? state.savedVisit?.spo2,
                glucose: state.glucose ?? state.savedVisit?.glucose,
                ecgNotes: state.ecgNotes ?? state.savedVisit?.ecgNotes,
                diagnoses: state.selectedDiagnoses.isNotEmpty
                    ? state.selectedDiagnoses
                    : (state.savedVisit?.diagnoses ?? const []),
                medications: state.selectedMedications.isNotEmpty
                    ? state.selectedMedications
                    : (state.savedVisit?.medications ?? const []),
                customMedication: state.customMedication ?? state.savedVisit?.customMedication,
                pessaryType: state.pessaryType ?? state.savedVisit?.pessaryType,
                pessarySize: state.pessarySize ?? state.savedVisit?.pessarySize,
                surgicalReferral: state.surgicalReferral ?? state.savedVisit?.surgicalReferral,
                treatmentLevel: state.treatmentLevel ?? state.savedVisit?.treatmentLevel,
                counseling: state.selectedCounseling.isNotEmpty
                    ? state.selectedCounseling
                    : (state.savedVisit?.counseling ?? const []),
                followUpNeeded: state.followUpNeeded,
                followUpDestination: state.followUpDestination ?? state.savedVisit?.followUpDestination,
                outtakeNotes: state.outtakeNotes ?? state.savedVisit?.outtakeNotes,
                attendingDoctorNames: state.attendingDoctorNames.isNotEmpty
                    ? state.attendingDoctorNames
                    : (state.savedVisit?.attendingDoctorNames ?? const []),
                primaryDoctorName: state.primaryDoctorName ?? state.savedVisit?.primaryDoctorName,
                attendingNurseNames: state.attendingNurseNames.isNotEmpty
                    ? state.attendingNurseNames
                    : (state.savedVisit?.attendingNurseNames ?? const []),
                primaryNurseName: state.primaryNurseName ?? state.savedVisit?.primaryNurseName,
                createdByUserId: user?.id ?? state.savedVisit?.createdByUserId ?? 'usr-doc',
                tenantId: user?.tenantId ?? state.savedVisit?.tenantId ?? 'tenant_default',
                isSynced: state.savedVisit?.isSynced ?? false,
                createdAt: state.savedVisit?.createdAt ?? DateTime.now(),
              );

              final saved = await ref.read(reportingViewModelProvider.notifier).exportIndividualPatientPdf(
                patient: widget.patient,
                visit: currentVisit,
                camp: activeCamp,
                organizationName: activeCamp?.organizationName,
                userId: user?.id ?? 'usr-doc',
                userName: user?.name ?? 'Medical Officer',
                userRole: user?.role.toDbString() ?? 'SUPER_ADMIN',
                deviceId: device?.deviceId ?? 'dev-field',
              );

              if (context.mounted && saved != null) {
                final result = DownloadResult.fromSavedPath(
                  savedPath: saved,
                  filename: ReportFilenameHelper.patientDossier(widget.patient.patientId),
                  mimeType: 'application/pdf',
                );
                FileDownloadHelper.showDownloadFeedback(context, result);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Station Indicator Stepper Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStepTab(0, '1. Anamnesis', Icons.history_edu, state.currentStationIndex),
                  _buildStepTab(1, '2. Exam & POP', Icons.accessibility_new, state.currentStationIndex),
                  _buildStepTab(2, '3. Vitals & Lab', Icons.monitor_heart, state.currentStationIndex),
                  _buildStepTab(3, '4. Diagnoses', Icons.checklist, state.currentStationIndex),
                  _buildStepTab(4, '5. Treatment', Icons.medication, state.currentStationIndex),
                  _buildStepTab(5, '6. Outtake', Icons.assignment_turned_in, state.currentStationIndex),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          // CAMP LOCKED BANNER
          if (isLockedCamp)
            Builder(builder: (context) {
              final lockedCamp = patientCamp!;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                color: isSuperAdmin ? const Color(0xFFFFFBEB) : const Color(0xFFFEF2F2),
                child: Row(
                  children: [
                    Icon(
                      isSuperAdmin ? Icons.lock_open_rounded : Icons.lock_rounded,
                      color: isSuperAdmin ? const Color(0xFFD97706) : const Color(0xFFDC2626),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isSuperAdmin
                            ? 'Super Admin Override — Camp "${lockedCamp.name}" is ${lockedCamp.status.displayNameEn}. You may save clinical changes.'
                            : 'Camp Closed — Read-Only View. Camp "${lockedCamp.name}" (${lockedCamp.campCode}) is ${lockedCamp.status.displayNameEn}. Clinical data cannot be edited.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSuperAdmin ? const Color(0xFF92400E) : const Color(0xFF991B1B),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

          // Main Station Form Area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: _buildStationContent(state, vm),
                ),
              ),
            ),
          ),

          // Bottom Station Navigation Toolbar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppTheme.borderLight)),
            ),
            child: LayoutBuilder(
              builder: (context, toolbarConstraints) {
                final isCompact = toolbarConstraints.maxWidth < 420;
                return Row(
                  children: [
                    if (state.currentStationIndex > 0) ...[
                      OutlinedButton.icon(
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: Text(isCompact ? 'Back' : 'Previous'),
                        onPressed: () => vm.previousStation(),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Spacer(),
                    if (state.currentStationIndex < 5)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: Text(isCompact ? 'Next' : 'Next Station'),
                        onPressed: () => vm.nextStation(),
                      )
                    else
                      Flexible(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.successGreen,
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 10 : 16,
                              vertical: 12,
                            ),
                          ),
                          icon: state.isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.check_circle_outline, size: 18),
                          label: Text(
                            isCompact ? 'Save Record' : 'Complete & Save Record',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: state.isSaving || isEffectivelyLocked
                            ? null
                            : () async {
                                final scaffoldMessenger = ScaffoldMessenger.of(context);
                                final navigator = Navigator.of(context);

                                final saved = await vm.submitAssessment(
                                  patientId: widget.patient.patientId,
                                  campId: widget.patient.campId,
                                  staffUserId: user?.id ?? 'usr-doc',
                                  deviceId: device?.deviceId ?? 'dev-field',
                                );

                                if (!mounted) return;

                                if (saved != null) {
                                  scaffoldMessenger.clearSnackBars();
                                  scaffoldMessenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Clinical Assessment successfully saved in local SQLite!'),
                                      backgroundColor: AppTheme.successGreen,
                                    ),
                                  );
                                  navigator.pop(true);
                                } else {
                                  scaffoldMessenger.clearSnackBars();
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(Icons.error_outline, color: Colors.white, size: 20),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              ref.read(clinicalAssessmentProvider).errorMessage ?? 'Failed to save clinical assessment. Please check required fields.',
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: Colors.red[700],
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 5),
                                    ),
                                  );
                                }
                              },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStationDate({required String title}) async {
    final current = ref.read(clinicalAssessmentProvider).visitDate ??
        ref.read(clinicalAssessmentProvider).savedVisit?.visitDate ??
        DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: title,
    );
    if (picked != null && mounted) {
      ref.read(clinicalAssessmentProvider.notifier).setVisitDate(picked);
      setState(() {});
    }
  }

  Widget _buildStationDateChip({
    required String label,
    required DateTime date,
  }) {
    final formattedAd = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    final dual = NepaliLocalizationService.formatDualCalendarDate(date);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _pickStationDate(title: 'Select $label (मिति परिवर्तन)'),
      child: Tooltip(
        message: 'Tap to change date: $dual',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_month_rounded, size: 13, color: AppTheme.primaryTeal),
              const SizedBox(width: 5),
              Text(
                '$label: $formattedAd',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.edit_outlined, size: 12, color: AppTheme.primaryTeal),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepTab(int index, String label, IconData icon, int currentIndex) {
    final isSelected = index == currentIndex;
    return InkWell(
      onTap: () => ref.read(clinicalAssessmentProvider.notifier).setStation(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryTeal : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryTeal : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey.shade700),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : AppTheme.textPrimaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationContent(ClinicalAssessmentState state, ClinicalAssessmentViewModel vm) {
    switch (state.currentStationIndex) {
      case 0:
        return _buildStation1Anamnesis(state, vm);
      case 1:
        return _buildStation2ExamAndPOP(state, vm);
      case 2:
        return _buildStation3VitalsAndLab(state, vm);
      case 3:
        return _buildStation4Diagnoses(state, vm);
      case 4:
        return _buildStation5Treatment(state, vm);
      case 5:
      default:
        return _buildStation6Outtake(state, vm);
    }
  }

  // --- 1. Anamnesis / Obstetric History ---
  Widget _buildStation1Anamnesis(ClinicalAssessmentState state, ClinicalAssessmentViewModel vm) {
    final patientReasons = widget.patient.reasonsForVisit.map((r) => r.toLowerCase()).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.child_care_rounded, color: AppTheme.primaryTeal, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Obstetric History (सुत्केरी तथा गर्भ विवरण)',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildStationDateChip(
                      label: 'Intake Date',
                      date: widget.patient.intakeDate,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 580;
                    if (isMobile) {
                      return Column(
                        children: [
                          TextField(
                            controller: _deliveriesController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Deliveries (सुत्केरी संख्या)',
                              hintText: '0–20',
                              prefixIcon: Icon(Icons.pregnant_woman_rounded),
                            ),
                            onChanged: (val) => vm.setObstetricHistory(deliveries: int.tryParse(val)),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _livingChildrenController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Living Children (जीवित बच्चा)',
                              hintText: 'Count',
                              prefixIcon: Icon(Icons.family_restroom_rounded),
                            ),
                            onChanged: (val) => vm.setObstetricHistory(livingChildren: int.tryParse(val)),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _abortionsController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Abortions (गर्भपतन)',
                              hintText: 'Count',
                              prefixIcon: Icon(Icons.remove_circle_outline_rounded),
                            ),
                            onChanged: (val) => vm.setObstetricHistory(abortions: int.tryParse(val)),
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _deliveriesController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Deliveries (सुत्केरी संख्या)',
                              hintText: '0–20',
                              prefixIcon: Icon(Icons.pregnant_woman_rounded),
                            ),
                            onChanged: (val) => vm.setObstetricHistory(deliveries: int.tryParse(val)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _livingChildrenController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Living Children (जीवित बच्चा)',
                              hintText: 'Count',
                              prefixIcon: Icon(Icons.family_restroom_rounded),
                            ),
                            onChanged: (val) => vm.setObstetricHistory(livingChildren: int.tryParse(val)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _abortionsController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Abortions (गर्भपतन)',
                              hintText: 'Count',
                              prefixIcon: Icon(Icons.remove_circle_outline_rounded),
                            ),
                            onChanged: (val) => vm.setObstetricHistory(abortions: int.tryParse(val)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (state.obstetricValidation.isError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      state.obstetricValidation.messageEn!,
                      style: const TextStyle(color: AppTheme.dangerRose, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        const Row(
          children: [
            Icon(Icons.medical_services_outlined, color: AppTheme.primaryTeal, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Chief Complaints Details (Dynamic Master Data & Standard Symptoms)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Dynamic complaints from Clinical Master Data. Tap any duration or symptom option to record findings:',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 12),

        ...() {
          final lookupState = ref.watch(masterLookupProvider);
          final activeMasterComplaints = lookupState.activeChiefComplaints;

          // Standard baseline Yellow Form complaints (9 Canonical Complaints)
          final standardComplaints = [
            {
              'key': 'prolapse',
              'title': 'Something hanging out (पाठेघर खस्ने समस्या)',
              'subCategory': 'Pelvic Floor & Prolapse',
              'hasDuration': true,
              'options': ['pessary', 'surgery'],
              'matches': (List<String> r) => r.any((x) => x.contains('hanging') || x.contains('prolapse') || x.contains('पाठेघर')),
            },
            {
              'key': 'discharge',
              'title': 'Discharge / Itching (पानी बग्ने / चिलाउने)',
              'subCategory': 'Infections & Discharge',
              'hasDuration': true,
              'options': ['white', 'yellow', 'green', 'grey', 'smelly'],
              'matches': (List<String> r) => r.any((x) => x.contains('discharge') || x.contains('itching') || x.contains('स्राव') || x.contains('चिलाउने')),
            },
            {
              'key': 'urine',
              'title': 'Problems passing urine (पिसाब सम्बन्धी समस्या)',
              'subCategory': 'Urinary Symptoms',
              'hasDuration': true,
              'options': ['stress', 'urge', 'continuous flow'],
              'matches': (List<String> r) => r.any((x) => x.contains('urine') || x.contains('पिसाब')),
            },
            {
              'key': 'stool',
              'title': 'Problems passing stool (दिसा सम्बन्धी समस्या)',
              'subCategory': 'Pelvic Floor & Prolapse',
              'hasDuration': true,
              'options': <String>[],
              'matches': (List<String> r) => r.any((x) => x.contains('stool') || x.contains('दिसा')),
            },
            {
              'key': 'menstrual',
              'title': 'Menstrual problem (महिनावारी समस्या)',
              'subCategory': 'Reproductive & Sexual',
              'hasDuration': false,
              'options': ['dysmenorrhoea', 'metrorrhagia', 'menorrhagia', 'postmenopausal bleeding'],
              'matches': (List<String> r) => r.any((x) => x.contains('menstrual') || x.contains('महिनावारी')),
            },
            {
              'key': 'infertility',
              'title': 'Infertility / Conception Difficulty (निःसन्तान समस्या)',
              'subCategory': 'Reproductive & Sexual',
              'hasDuration': true,
              'options': <String>[],
              'matches': (List<String> r) => r.any((x) => x.contains('infertility') || x.contains('बाँझोपन')),
            },
            {
              'key': 'lower_abdomen_pain',
              'title': 'Lower abdomen pain (तल्लो पेट दुख्ने)',
              'subCategory': 'Pelvic & Abdominal',
              'hasDuration': true,
              'options': <String>[],
              'matches': (List<String> r) => r.any((x) => x == 'pain' || x.contains('दुख्ने') || ((x.contains('abdomen') || x.contains('तल्लो पेट')) && x.contains('pain'))),
            },
            {
              'key': 'lower_back_pain',
              'title': 'Lower back pain (कम्मर / ढाड दुख्ने)',
              'subCategory': 'Musculoskeletal & General',
              'hasDuration': true,
              'options': <String>[],
              'matches': (List<String> r) => r.any((x) => x == 'pain' || x.contains('दुख्ने') || ((x.contains('back') || x.contains('ढाड') || x.contains('कम्मर')) && x.contains('pain'))),
            },
            {
              'key': 'checkup',
              'title': 'Checkup (सामान्य जाँच)',
              'subCategory': 'General / Other',
              'hasDuration': false,
              'options': ['routine wellness screening', 'follow-up checkup', 'general counseling'],
              'matches': (List<String> r) => r.any((x) => x.contains('checkup') || x.contains('जाँच')),
            },
          ];

          final List<Map<String, dynamic>> resolvedComplaints = [];

          if (activeMasterComplaints.isNotEmpty) {
            for (final masterItem in activeMasterComplaints) {
              final code = masterItem.code.toLowerCase().trim();

              final stdMatch = standardComplaints.cast<Map<String, dynamic>?>().firstWhere(
                (s) => s != null && (s['key'] == code ||
                       masterItem.labelEn.toLowerCase().contains(s['key'] as String) ||
                       (s['title'] as String).toLowerCase().contains(masterItem.labelEn.toLowerCase())),
                orElse: () => null,
              );

              final title = masterItem.labelNe.isNotEmpty
                  ? '${masterItem.labelEn} (${masterItem.labelNe})'
                  : masterItem.labelEn;

              final matchesFn = stdMatch?['matches'] as bool Function(List<String>)?;
              final bool isIntakeReason = (matchesFn != null && matchesFn(patientReasons)) ||
                  patientReasons.any((r) {
                    final rClean = r.replaceAll(RegExp(r'[^a-z0-9]'), '');
                    final codeClean = code.replaceAll(RegExp(r'[^a-z0-9]'), '');
                    final labelClean = masterItem.labelEn.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
                    return (codeClean.isNotEmpty && rClean.contains(codeClean)) ||
                           (labelClean.isNotEmpty && (rClean.contains(labelClean) || labelClean.contains(rClean))) ||
                           (masterItem.labelNe.isNotEmpty && r.contains(masterItem.labelNe.toLowerCase()));
                  });

              resolvedComplaints.add({
                'key': code,
                'title': title,
                'subCategory': masterItem.subCategory ?? stdMatch?['subCategory'],
                'hasDuration': stdMatch?['hasDuration'] ?? true,
                'options': stdMatch?['options'] ?? <String>[],
                'isIntakeReason': isIntakeReason,
              });
            }
          } else {
            for (final std in standardComplaints) {
              final matchesFn = std['matches'] as bool Function(List<String>);
              resolvedComplaints.add({
                'key': std['key'] as String,
                'title': std['title'] as String,
                'subCategory': std['subCategory'] as String?,
                'hasDuration': std['hasDuration'] as bool,
                'options': std['options'] as List<String>,
                'isIntakeReason': matchesFn(patientReasons),
              });
            }
          }

          return resolvedComplaints.map((comp) {
            return _buildComplaintCard(
              state: state,
              vm: vm,
              complaintKey: comp['key'] as String,
              title: comp['title'] as String,
              hasDuration: comp['hasDuration'] as bool,
              options: comp['options'] as List<String>,
              isIntakeReason: comp['isIntakeReason'] as bool,
            );
          }).toList();
        }(),
      ],
    );
  }

  Widget _buildComplaintCard({
    required ClinicalAssessmentState state,
    required ClinicalAssessmentViewModel vm,
    required String complaintKey,
    required String title,
    required bool hasDuration,
    required List<String> options,
    bool isIntakeReason = false,
  }) {
    final complaintData = _resolveComplaintData(state.complaints, complaintKey);
    final selectedDuration = (complaintData['duration'] as String?)?.trim() ??
        (state.complaints['complaintsDuration'] as String?)?.trim();
    final rawOptions = complaintData['options'] ??
        complaintData['subOptions'] ??
        complaintData['subOption'];
    final List<String> selectedOptions = [];
    if (rawOptions is List) {
      for (final o in rawOptions) {
        final s = o?.toString().trim().toLowerCase();
        if (s != null && s.isNotEmpty && !selectedOptions.contains(s)) selectedOptions.add(s);
      }
    } else if (rawOptions is String && rawOptions.trim().isNotEmpty) {
      for (final p in rawOptions.split(',')) {
        final s = p.trim().toLowerCase();
        if (s.isNotEmpty && !selectedOptions.contains(s)) selectedOptions.add(s);
      }
    }
    final currentRemarks = (complaintData['remarks'] as String?)?.trim() ?? '';
    final remarksController = _getRemarksController(complaintKey, currentRemarks);

    final hasActiveSelections = (complaintData['active'] == true) ||
        (complaintData['present'] == true) ||
        (selectedDuration != null && selectedDuration.isNotEmpty) ||
        selectedOptions.isNotEmpty ||
        currentRemarks.isNotEmpty;

    final isSelected = _collapsedComplaints.contains(complaintKey)
        ? false
        : (hasActiveSelections || isIntakeReason || _expandedComplaints.contains(complaintKey));

    // Yellow Form canonical duration options
    final durationOptions = complaintKey.toLowerCase().contains('infertility')
        ? ClinicalConstants.infertilityDurations
        : ClinicalConstants.anamnesisDurations;
    final allDurations = [
      ...durationOptions,
      if (selectedDuration != null &&
          selectedDuration.isNotEmpty &&
          !durationOptions.any((d) => _isDurationMatch(d, selectedDuration)))
        selectedDuration,
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryLight.withValues(alpha: 0.15) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? AppTheme.primaryTeal.withValues(alpha: 0.5) : Colors.grey.shade300,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? AppTheme.primaryDark : const Color(0xFF334155),
                    ),
                  ),
                ),
                if (isIntakeReason) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                    ),
                    child: const Text(
                      'Reported in Intake',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
                    ),
                  ),
                ],
              ],
            ),
            value: isSelected,
            activeColor: AppTheme.primaryTeal,
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  _collapsedComplaints.remove(complaintKey);
                  _expandedComplaints.add(complaintKey);
                  final defDuration = (selectedDuration != null && selectedDuration.isNotEmpty)
                      ? selectedDuration
                      : '< 1 year';
                  if (hasDuration && (selectedDuration == null || selectedDuration.isEmpty)) {
                    vm.setComplaintDuration(complaintKey, defDuration);
                  }
                  vm.updateComplaint(complaintKey, {
                    ...complaintData,
                    'active': true,
                    'present': true,
                    if (hasDuration) 'duration': defDuration,
                  });
                } else {
                  _expandedComplaints.remove(complaintKey);
                  _collapsedComplaints.add(complaintKey);
                  vm.updateComplaint(complaintKey, {});
                  remarksController.clear();
                }
              });
            },
          ),
          if (isSelected) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 10),
                  if (hasDuration) ...[
                    const Text(
                      'Duration since onset (सुरु भएको अवधि):',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: allDurations.map((d) {
                        final isDurSelected = _isDurationMatch(d, selectedDuration);
                        return ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            d,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: isDurSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          selected: isDurSelected,
                          selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                          labelStyle: TextStyle(
                            color: isDurSelected ? AppTheme.primaryTeal : const Color(0xFF334155),
                          ),
                          onSelected: (val) {
                            vm.setComplaintDuration(complaintKey, isDurSelected ? '' : d);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (options.isNotEmpty) ...[
                    const Text(
                      'Clinical Presentation / Subtypes:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: options.map((opt) {
                        final isChecked = selectedOptions.any((s) =>
                            s == opt.toLowerCase().trim() ||
                            opt.toLowerCase().trim().contains(s) ||
                            s.contains(opt.toLowerCase().trim()));
                        return FilterChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            '${NepaliLocalizationService.translate(opt)} ($opt)',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          selected: isChecked,
                          selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                          checkmarkColor: AppTheme.primaryTeal,
                          labelStyle: TextStyle(
                            color: isChecked ? AppTheme.primaryTeal : const Color(0xFF334155),
                          ),
                          onSelected: (val) {
                            vm.toggleComplaintOption(complaintKey, opt);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 4),
                  TextField(
                    controller: remarksController,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      labelText: 'Clinical Remarks / टिप्पणी ($title)',
                      hintText: 'Enter clinical remarks, details or severity...',
                      prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                    ),
                    onChanged: (val) {
                      vm.setComplaintRemarks(complaintKey, val);
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- 2. Physical Examination & POP Staging ---
  Widget _buildStation2ExamAndPOP(ClinicalAssessmentState state, ClinicalAssessmentViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top status card: Uterus Inside & Pelvic Floor Muscle Tone
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.health_and_safety_outlined, color: AppTheme.primaryTeal, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Uterus Position & Pelvic Muscle Tone (पाठेघरको स्थिति तथा मांसपेशी तनाव)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildStationDateChip(
                      label: 'Exam Date',
                      date: state.visitDate ?? state.savedVisit?.visitDate ?? DateTime.now(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Uterus Inside (पाठेघर भित्रै छ?):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  children: [
                    ChoiceChip(
                      label: const Text('Yes'),
                      selected: state.uterusInside == true,
                      selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.18),
                      labelStyle: TextStyle(
                        color: state.uterusInside == true ? AppTheme.primaryTeal : const Color(0xFF334155),
                        fontWeight: state.uterusInside == true ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (_) => vm.updateExam(uterusInside: true),
                    ),
                    ChoiceChip(
                      label: const Text('No'),
                      selected: state.uterusInside == false,
                      selectedColor: Colors.red.shade100,
                      labelStyle: TextStyle(
                        color: state.uterusInside == false ? Colors.red.shade900 : const Color(0xFF334155),
                        fontWeight: state.uterusInside == false ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (_) => vm.updateExam(uterusInside: false),
                    ),
                  ],
                ),
                const Divider(height: 24),
                const Text('Pelvic Floor Muscle (पेल्भिक मांसपेशी तनाव):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['normal', 'weak', 'hypertonic'].map((tone) {
                    final isSelected = state.pelvicFloorTone == tone;
                    return ChoiceChip(
                      label: Text('${NepaliLocalizationService.translate(tone)} ($tone)', style: const TextStyle(fontSize: 12)),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.18),
                      labelStyle: TextStyle(
                        color: isSelected ? AppTheme.primaryTeal : const Color(0xFF334155),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (_) => vm.updateExam(pelvicFloorTone: tone),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Anatomical Physical Examination: Vulva, Vagina, Cervix, Uterus
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.visibility_outlined, color: AppTheme.primaryTeal, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Physical Examination (अङ्गगत शारीरिक जाँच — Yellow Form Page 2)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Color(0xFF1E293B)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 1. Vulva Examination
                const Text('1. Vulva Examination (बाह्य अङ्ग / भल्भा):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF334155))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    'Normal', 'Atrophic', 'Discharge', 'Condylomata', 'Ulcer', 'Lichen Sclerosus'
                  ].map((chip) {
                    final isSelected = _vulvaRemarksController.text.contains(chip);
                    return ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(chip, style: const TextStyle(fontSize: 11)),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                      onSelected: (sel) {
                        setState(() {
                          _vulvaRemarksController.text = sel ? chip : '';
                          vm.updateExam(vulvaRemarks: _vulvaRemarksController.text);
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _vulvaRemarksController,
                  decoration: const InputDecoration(
                    labelText: 'Vulva Remarks (भल्भा सम्बन्धी कैफियत)',
                    hintText: 'e.g. Normal, healthy, or ulcer/lesion noted',
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                  onChanged: (val) => vm.updateExam(vulvaRemarks: val),
                ),
                const Divider(height: 24),

                // 2. Vagina Examination
                const Text('2. Vagina Examination (योनीको अवस्था):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF334155))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    'Normal', 'Atrophic Mucosa', 'Discharge Present', 'Cystocele', 'Rectocele', 'Vault Prolapse'
                  ].map((chip) {
                    final isSelected = _vaginaRemarksController.text.contains(chip);
                    return ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(chip, style: const TextStyle(fontSize: 11)),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                      onSelected: (sel) {
                        setState(() {
                          _vaginaRemarksController.text = sel ? chip : '';
                          vm.updateExam(vaginaRemarks: _vaginaRemarksController.text);
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _vaginaRemarksController,
                  decoration: const InputDecoration(
                    labelText: 'Vagina Remarks (योनी सम्बन्धी कैफियत)',
                    hintText: 'e.g. Healthy mucosa, mild discharge, or laxity',
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                  onChanged: (val) => vm.updateExam(vaginaRemarks: val),
                ),
                const Divider(height: 24),

                // 3. Cervix Examination
                const Text('3. Cervix Appearance (पाठेघरको मुखको अवस्था):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF334155))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    'Normal / Smooth', 'Erosion', 'Hypertrophied', 'Polyp', 'Bleeding on Touch', 'Leukoplakia'
                  ].map((chip) {
                    final isSelected = _cervixRemarksController.text.contains(chip);
                    return ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(chip, style: const TextStyle(fontSize: 11)),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                      onSelected: (sel) {
                        setState(() {
                          _cervixRemarksController.text = sel ? chip : '';
                          vm.updateExam(cervixRemarks: _cervixRemarksController.text);
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _cervixRemarksController,
                  decoration: const InputDecoration(
                    labelText: 'Cervix Remarks (पाठेघरको मुख सम्बन्धी कैफियत)',
                    hintText: 'e.g. Smooth, healthy, or erosion present',
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                  onChanged: (val) => vm.updateExam(cervixRemarks: val),
                ),
                const Divider(height: 24),

                // 4. Uterus Examination
                const Text('4. Uterus Examination (पाठेघरको अवस्था):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF334155))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    'Normal Size & Mobile', 'Enlarged / Bulky', 'Tender on Motion', 'Fibroid / Myoma', 'Retroverted'
                  ].map((chip) {
                    final isSelected = _uterusRemarksController.text.contains(chip);
                    return ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(chip, style: const TextStyle(fontSize: 11)),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                      onSelected: (sel) {
                        setState(() {
                          _uterusRemarksController.text = sel ? chip : '';
                          vm.updateExam(uterusRemarks: _uterusRemarksController.text);
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _uterusRemarksController,
                  decoration: const InputDecoration(
                    labelText: 'Uterus Remarks (पाठेघर सम्बन्धी कैफियत)',
                    hintText: 'e.g. Normal size, non-tender, freely mobile, or bulky',
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                  onChanged: (val) => vm.updateExam(uterusRemarks: val),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // POP STAGING BOX
        Card(
          color: AppTheme.primaryLight.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.primaryTeal),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const Text(
                      'POP STAGING (Pelvic Organ Prolapse)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryDark),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryTeal,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Highest POP: Stage ${state.highestPopStage}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Anterior Wall (Stage 0 - 3)
                _buildPopStageSelector(
                  title: 'POP Anterior Wall (अगाडिको भित्ता):',
                  maxStage: 3,
                  currentStage: state.popAnteriorStage,
                  onSelect: (stg) => vm.setPopStages(anterior: stg),
                ),
                const SizedBox(height: 10),

                // Middle Part (Stage 0 - 4)
                _buildPopStageSelector(
                  title: 'POP Middle Part (बीचको भाग - Uterine):',
                  maxStage: 4,
                  currentStage: state.popMiddleStage,
                  onSelect: (stg) => vm.setPopStages(middle: stg),
                ),
                const SizedBox(height: 10),

                // Posterior Wall (Stage 0 - 3)
                _buildPopStageSelector(
                  title: 'POP Posterior Wall (पछाडिको भित्ता):',
                  maxStage: 3,
                  currentStage: state.popPosteriorStage,
                  onSelect: (stg) => vm.setPopStages(posterior: stg),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPopStageSelector({
    required String title,
    required int maxStage,
    required int currentStage,
    required Function(int) onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(maxStage + 1, (index) {
            final isSelected = currentStage == index;
            return ChoiceChip(
              visualDensity: VisualDensity.compact,
              label: Text('Stage $index', style: const TextStyle(fontSize: 11)),
              selected: isSelected,
              selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                color: isSelected ? AppTheme.primaryTeal : const Color(0xFF334155),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (_) => onSelect(index),
            );
          }),
        ),
      ],
    );
  }

  // --- 3. Lab Tests & Numeric Vitals (Live Validation) ---
  Widget _buildStation3VitalsAndLab(ClinicalAssessmentState state, ClinicalAssessmentViewModel vm) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 560;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Rapid Point-of-Care Tests (प्रयोगशाला जाँच)',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                        ),
                        _buildStationDateChip(
                          label: 'Lab Test Date',
                          date: state.visitDate ?? state.savedVisit?.visitDate ?? DateTime.now(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Urine Test (पिसाब जाँच):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Builder(
                      builder: (context) {
                        final currentUrine = (state.urineTest ?? 'normal').toLowerCase();
                        final isNormal = currentUrine == 'normal' || currentUrine.isEmpty;
                        final isPos = !isNormal && (currentUrine.contains('pos') || currentUrine.contains('+') || currentUrine.contains('protein') || currentUrine.contains('glucose') || currentUrine.contains('blood'));

                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Normal (सामान्य)'),
                              selected: isNormal,
                              selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                              labelStyle: TextStyle(
                                color: isNormal ? AppTheme.primaryTeal : const Color(0xFF334155),
                                fontWeight: isNormal ? FontWeight.bold : FontWeight.normal,
                                fontSize: 11.5,
                              ),
                              onSelected: (_) => vm.setVitals(urineTest: 'normal'),
                            ),
                            ChoiceChip(
                              label: const Text('Positive (पोजिटिभ)'),
                              selected: isPos,
                              selectedColor: Colors.purple.shade100,
                              labelStyle: TextStyle(
                                color: isPos ? Colors.purple.shade900 : const Color(0xFF334155),
                                fontWeight: isPos ? FontWeight.bold : FontWeight.normal,
                                fontSize: 11.5,
                              ),
                              onSelected: (_) => vm.setVitals(urineTest: 'pos'),
                            ),
                          ],
                        );
                      },
                    ),
                    const Divider(height: 24),
                    const Text('Pregnancy Test (UPT) (गर्भावस्था जाँच):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        {'val': 'neg', 'label': 'Negative (नेगेटिभ)'},
                        {'val': 'pos', 'label': 'Positive (पोजिटिभ)'},
                      ].map((item) {
                        final rawPreg = (state.pregnancyTest ?? 'neg').toLowerCase().trim();
                        final isSelected = rawPreg == item['val'] ||
                            (item['val'] == 'neg' && (rawPreg == 'negative' || rawPreg.startsWith('neg'))) ||
                            (item['val'] == 'pos' && (rawPreg == 'positive' || rawPreg.startsWith('pos')));
                        return ChoiceChip(
                          label: Text(item['label']!),
                          selected: isSelected,
                          selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                          labelStyle: TextStyle(
                            color: isSelected ? AppTheme.primaryTeal : const Color(0xFF334155),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 11.5,
                          ),
                          onSelected: (_) => vm.setVitals(pregnancyTest: item['val']),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            const Text('Numeric Vital Signs (महत्वपूर्ण शारीरिक सूचकहरू)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Real-time validation checks for typos and abnormal health thresholds:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),

            // Blood Pressure (Systolic / Diastolic)
            if (isMobile) ...[
              TextField(
                controller: _systolicController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Systolic BP (सिस्टोलिक)',
                  suffixText: 'mmHg',
                  prefixIcon: _getValidationIcon(state.systolicValidation),
                ),
                onChanged: (val) => vm.setVitals(systolic: int.tryParse(val)),
              ),
              _buildValidationMessage(state.systolicValidation),
              const SizedBox(height: 12),
              TextField(
                controller: _diastolicController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Diastolic BP (डायस्टोलिक)',
                  suffixText: 'mmHg',
                  prefixIcon: _getValidationIcon(state.diastolicValidation),
                ),
                onChanged: (val) => vm.setVitals(diastolic: int.tryParse(val)),
              ),
              _buildValidationMessage(state.diastolicValidation),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _systolicController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Systolic BP (सिस्टोलिक)',
                        suffixText: 'mmHg',
                        prefixIcon: _getValidationIcon(state.systolicValidation),
                      ),
                      onChanged: (val) => vm.setVitals(systolic: int.tryParse(val)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _diastolicController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Diastolic BP (डायस्टोलिक)',
                        suffixText: 'mmHg',
                        prefixIcon: _getValidationIcon(state.diastolicValidation),
                      ),
                      onChanged: (val) => vm.setVitals(diastolic: int.tryParse(val)),
                    ),
                  ),
                ],
              ),
              _buildValidationMessage(state.systolicValidation),
              _buildValidationMessage(state.diastolicValidation),
            ],
            const SizedBox(height: 12),

            // Pulse and Oxygen Saturation
            if (isMobile) ...[
              TextField(
                controller: _pulseController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Pulse (नाडी गति)',
                  suffixText: 'bpm',
                  prefixIcon: _getValidationIcon(state.pulseValidation),
                ),
                onChanged: (val) => vm.setVitals(pulse: int.tryParse(val)),
              ),
              _buildValidationMessage(state.pulseValidation),
              const SizedBox(height: 12),
              TextField(
                controller: _spo2Controller,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'SpO2 (अक्सिजन)',
                  suffixText: '%',
                  prefixIcon: _getValidationIcon(state.spo2Validation),
                ),
                onChanged: (val) => vm.setVitals(spo2: int.tryParse(val)),
              ),
              _buildValidationMessage(state.spo2Validation),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pulseController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Pulse (नाडी गति)',
                        suffixText: 'bpm',
                        prefixIcon: _getValidationIcon(state.pulseValidation),
                      ),
                      onChanged: (val) => vm.setVitals(pulse: int.tryParse(val)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _spo2Controller,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'SpO2 (अक्सिजन)',
                        suffixText: '%',
                        prefixIcon: _getValidationIcon(state.spo2Validation),
                      ),
                      onChanged: (val) => vm.setVitals(spo2: int.tryParse(val)),
                    ),
                  ),
                ],
              ),
              _buildValidationMessage(state.pulseValidation),
              _buildValidationMessage(state.spo2Validation),
            ],
            const SizedBox(height: 12),

            // Blood Glucose
            TextField(
              controller: _glucoseController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Blood Glucose (रक्त ग्लुकोज)',
                suffixText: 'mg/dL',
                prefixIcon: _getValidationIcon(state.glucoseValidation),
              ),
              onChanged: (val) => vm.setVitals(glucose: int.tryParse(val)),
            ),
            _buildValidationMessage(state.glucoseValidation),
            const SizedBox(height: 16),

            // ECG Examination (Yellow Form Station 3)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.monitor_heart_outlined, color: AppTheme.primaryTeal, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'ECG Examination (ईसीजी जाँच)',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Record resting 12-lead ECG findings if indicated:',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        'Normal Sinus Rhythm',
                        'Sinus Tachycardia',
                        'Sinus Bradycardia',
                        'Arrhythmia',
                        'Ischemia / ST-T Change',
                        'Not Done',
                      ].map((tag) {
                        final isSelected = _ecgController.text.contains(tag);
                        return ChoiceChip(
                          label: Text(tag, style: const TextStyle(fontSize: 11.5)),
                          selected: isSelected,
                          selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                          labelStyle: TextStyle(
                            color: isSelected ? AppTheme.primaryTeal : const Color(0xFF334155),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (sel) {
                            setState(() {
                              if (sel) {
                                _ecgController.text = tag;
                              } else {
                                _ecgController.clear();
                              }
                              vm.setVitals(ecgNotes: _ecgController.text.trim().isNotEmpty ? _ecgController.text.trim() : null);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _ecgController,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'ECG Findings / Notes (ईसीजी विवरण / टिप्पणी)',
                        hintText: 'e.g. Normal sinus rhythm, rate 76 bpm, or abnormal findings',
                        prefixIcon: Icon(Icons.edit_note_rounded),
                      ),
                      onChanged: (val) => vm.setVitals(ecgNotes: val.trim().isNotEmpty ? val.trim() : null),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _getValidationIcon(ValidationResult result) {
    if (result.isError) return const Icon(Icons.cancel, color: AppTheme.dangerRose);
    if (result.isWarning) return const Icon(Icons.warning, color: AppTheme.warningAmber);
    return const Icon(Icons.check_circle, color: AppTheme.successGreen);
  }

  Widget _buildValidationMessage(ValidationResult result) {
    if (result.isNormal || result.messageEn == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4.0, left: 4.0),
      child: Text(
        '${result.messageEn!} (${result.messageNe ?? ""})',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: result.isError ? AppTheme.dangerRose : AppTheme.warningAmber,
        ),
      ),
    );
  }

  // --- 4. Diagnoses (Dynamic Camp Master Data & Standard Options) ---
  Widget _buildStation4Diagnoses(ClinicalAssessmentState state, ClinicalAssessmentViewModel vm) {
    final lookupState = ref.watch(masterLookupProvider);
    final diagnosesList = lookupState.activeDiagnoses.isNotEmpty
        ? lookupState.activeDiagnoses.map((d) => d.labelEn).toList()
        : ClinicalConstants.defaultDiagnoses;


    String getDiagnosisDisplayLabel(String diag) {
      final masterItem = lookupState.activeDiagnoses.cast<LookupItemModel?>().firstWhere(
        (d) => d != null && d.labelEn.toLowerCase() == diag.toLowerCase(),
        orElse: () => null,
      );
      final labelNe = (masterItem != null && masterItem.labelNe.isNotEmpty && masterItem.labelNe.toLowerCase() != masterItem.labelEn.toLowerCase())
          ? masterItem.labelNe
          : NepaliLocalizationService.translate(diag);
      return (labelNe.isNotEmpty && labelNe.toLowerCase() != diag.toLowerCase())
          ? '$labelNe ($diag)'
          : diag;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    'Clinical Diagnoses (${state.selectedDiagnoses.length} selected)',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  _buildStationDateChip(
                    label: 'Conclusion Date',
                    date: state.visitDate ?? state.savedVisit?.visitDate ?? DateTime.now(),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Highest POP Stage (Station 4 Top Line on Yellow Form)
        Card(
          color: AppTheme.primaryLight.withValues(alpha: 0.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppTheme.primaryTeal),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.stars_rounded, color: AppTheme.primaryTeal, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Highest POP Stage (अधिकतम स्टेज): Stage ${state.highestPopStage}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryDark),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: List.generate(5, (stg) {
                    final isSel = state.highestPopStage == stg;
                    return ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('Stage $stg', style: const TextStyle(fontSize: 11)),
                      selected: isSel,
                      selectedColor: AppTheme.primaryTeal,
                      labelStyle: TextStyle(
                        color: isSel ? Colors.white : const Color(0xFF334155),
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (_) => vm.setPopStages(highest: stg),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Select all confirmed conditions from the Yellow Form standard list:', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),

        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: diagnosesList.map((diag) {
            final isSelected = state.selectedDiagnoses.any((d) => d.toLowerCase().trim() == diag.toLowerCase().trim());
            return FilterChip(
              label: Text(
                getDiagnosisDisplayLabel(diag),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              selectedColor: AppTheme.primaryLight,
              checkmarkColor: AppTheme.primaryTeal,
              onSelected: (_) => vm.toggleDiagnosis(diag),
            );
          }).toList(),
        ),
      ],
    );
  }

  // --- 5. Treatment & Prescriptions ---
  Widget _buildStation5Treatment(ClinicalAssessmentState state, ClinicalAssessmentViewModel vm) {
    final lookupState = ref.watch(masterLookupProvider);
    final medicinesList = lookupState.activeMedicines.isNotEmpty
        ? lookupState.activeMedicines.map((m) => m.labelEn).toList()
        : ClinicalConstants.defaultMedications;
    final Set<String> hospitalsSet = {};
    if (lookupState.activeReferralHospitals.isNotEmpty) {
      for (final h in lookupState.activeReferralHospitals) {
        if (h.labelEn.trim().isNotEmpty) hospitalsSet.add(h.labelEn.trim());
      }
    } else {
      for (final h in ClinicalConstants.referralHospitals) {
        if (h.trim().isNotEmpty) hospitalsSet.add(h.trim());
      }
    }
    if (state.surgicalReferral != null && state.surgicalReferral!.trim().isNotEmpty) {
      hospitalsSet.add(state.surgicalReferral!.trim());
    }
    final hospitalsList = hospitalsSet.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Specialized Counseling (परामर्श)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            _buildStationDateChip(
              label: 'Treatment Date',
              date: state.visitDate ?? state.savedVisit?.visitDate ?? DateTime.now(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: ['weak pelvic floor', 'POP', 'stress incontinence', 'urge incontinence', 'abdominal pain'].map((c) {
            final isSelected = state.selectedCounseling.contains(c);
            return FilterChip(
              visualDensity: VisualDensity.compact,
              label: Text(c, style: const TextStyle(fontSize: 11)),
              selected: isSelected,
              onSelected: (_) => vm.toggleCounseling(c),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),

        const Text('Ring Pessary Fitting (रिङ पेसरी)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 500;
            if (isMobile) {
              return Column(
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: state.pessaryType,
                    decoration: const InputDecoration(labelText: 'Pessary Type'),
                    items: ['ring', 'ring with support', 'ring with knob'].map((t) {
                      return DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)));
                    }).toList(),
                    onChanged: (val) => vm.setPessary(type: val),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pessarySizeController,
                    decoration: const InputDecoration(labelText: 'Size (साइज mm)'),
                    onChanged: (val) => vm.setPessary(size: val),
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: state.pessaryType,
                    decoration: const InputDecoration(labelText: 'Pessary Type'),
                    items: ['ring', 'ring with support', 'ring with knob'].map((t) {
                      return DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)));
                    }).toList(),
                    onChanged: (val) => vm.setPessary(type: val),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _pessarySizeController,
                    decoration: const InputDecoration(labelText: 'Size (साइज mm)'),
                    onChanged: (val) => vm.setPessary(size: val),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),

        const Text('Referral for Surgery (शल्यक्रिया सिफारिस)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('surgical_referral_${state.surgicalReferral}'),
          isExpanded: true,
          initialValue: hospitalsList.contains(state.surgicalReferral) ? state.surgicalReferral : null,
          decoration: InputDecoration(
            labelText: 'Surgical Referral Hospital (शल्यक्रिया सिफारिस अस्पताल)',
            hintText: hospitalsList.isEmpty ? 'No partner hospitals configured' : 'Select referral hospital',
          ),
          items: hospitalsList.map((h) {
            return DropdownMenuItem(value: h, child: Text(h));
          }).toList(),
          onChanged: hospitalsList.isEmpty ? null : (val) => vm.setSurgicalReferral(val),
        ),
        const SizedBox(height: 18),

        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Medications Prescribed (औषधि वितरण)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        () {
          String getMedicationDisplayLabel(String med) {
            final masterItem = lookupState.activeMedicines.cast<LookupItemModel?>().firstWhere(
              (m) => m != null && m.labelEn.toLowerCase() == med.toLowerCase(),
              orElse: () => null,
            );
            final labelNe = (masterItem != null && masterItem.labelNe.isNotEmpty && masterItem.labelNe.toLowerCase() != masterItem.labelEn.toLowerCase())
                ? masterItem.labelNe
                : '';
            return labelNe.isNotEmpty ? '$med ($labelNe)' : med;
          }

          return Wrap(
            spacing: 6,
            runSpacing: 6,
            children: medicinesList.map((m) {
              final isSelected = state.selectedMedications.any((x) => x.toLowerCase().trim() == m.toLowerCase().trim());
              return FilterChip(
                visualDensity: VisualDensity.compact,
                label: Text(getMedicationDisplayLabel(m), style: const TextStyle(fontSize: 11)),
                selected: isSelected,
                onSelected: (_) => vm.toggleMedication(m),
              );
            }).toList(),
          );
        }(),
        const SizedBox(height: 8),
        TextField(
          controller: _customMedController,
          decoration: const InputDecoration(labelText: 'Other Medicines (अन्य औषधिहरू)'),
          onChanged: (val) => vm.setCustomMedication(val),
        ),
      ],
    );
  }

  // --- 6. Outtake & Follow-up ---
  Widget _buildStation6Outtake(ClinicalAssessmentState state, ClinicalAssessmentViewModel vm) {
    final lookupState = ref.watch(masterLookupProvider);
    final partnerHospitals = lookupState.activeReferralHospitals
        .map((h) => h.labelEn)
        .where((h) =>
            h != 'Health Post' &&
            h != 'GynaeSupport Nurse' &&
            h != 'Other' &&
            !h.toLowerCase().contains('scheer') &&
            !h.toLowerCase().contains('model'))
        .toList();

    final standardOptions = [
      ...partnerHospitals,
    ];

    final currentDest = state.followUpDestination;
    final bool isKnownHospital = currentDest != null && standardOptions.contains(currentDest);
    final bool isCustom = currentDest != null &&
        currentDest.trim().isNotEmpty &&
        currentDest != 'Health Post' &&
        currentDest != 'GynaeSupport Nurse' &&
        !currentDest.toLowerCase().contains('scheer') &&
        !currentDest.toLowerCase().contains('model') &&
        !isKnownHospital;

    final dropdownValue = isKnownHospital
        ? currentDest
        : (isCustom
            ? 'Other'
            : (partnerHospitals.isNotEmpty ? partnerHospitals.first : 'Other'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Follow-Up Plan (पुनः जाँच योजना)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            _buildStationDateChip(
              label: 'Outtake Date',
              date: state.visitDate ?? state.savedVisit?.visitDate ?? DateTime.now(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: RadioGroup<bool>(
            groupValue: state.followUpNeeded,
            onChanged: (val) {
              if (val != null) {
                final defaultDest = partnerHospitals.isNotEmpty ? partnerHospitals.first : 'Other';
                final effectiveDest = val
                    ? (standardOptions.contains(state.followUpDestination)
                        ? state.followUpDestination
                        : defaultDest)
                    : null;
                vm.setOuttake(followUpNeeded: val, destination: effectiveDest);
              }
            },
            child: Column(
              children: [
                const RadioListTile<bool>(
                  title: Text('Follow-up Needed (थप जाँच आवश्यक)'),
                  value: true,
                ),
                if (state.followUpNeeded) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Primary Follow-Up Care Destination (प्रमुख अनुगमन गन्तव्य — Yellow Form):',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              avatar: const Icon(Icons.local_hospital_rounded, size: 15),
                              label: const Text('Health Post (स्वास्थ्य चौकी)'),
                              selected: currentDest == 'Health Post',
                              selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                              labelStyle: TextStyle(
                                color: currentDest == 'Health Post' ? AppTheme.primaryTeal : const Color(0xFF334155),
                                fontWeight: currentDest == 'Health Post' ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (sel) {
                                if (sel) vm.setOuttake(destination: 'Health Post');
                              },
                            ),
                            ChoiceChip(
                              avatar: const Icon(Icons.support_agent_rounded, size: 15),
                              label: const Text('GynaeSupport Nurse (गाइने नर्स)'),
                              selected: currentDest == 'GynaeSupport Nurse',
                              selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                              labelStyle: TextStyle(
                                color: currentDest == 'GynaeSupport Nurse' ? AppTheme.primaryTeal : const Color(0xFF334155),
                                fontWeight: currentDest == 'GynaeSupport Nurse' ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (sel) {
                                if (sel) vm.setOuttake(destination: 'GynaeSupport Nurse');
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Or Select Referral Hospital / Center (वा रिफरल अस्पताल):',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          key: ValueKey('followup_dest_$dropdownValue'),
                          isExpanded: true,
                          initialValue: dropdownValue,
                          decoration: const InputDecoration(
                            labelText: 'Follow-up Destination / Hospital (पुनः जाँच गराउने अस्पताल)',
                          ),
                          items: [
                            if (partnerHospitals.isNotEmpty) ...[
                              for (final h in partnerHospitals)
                                DropdownMenuItem(
                                  value: h,
                                  child: Text('Hospital: $h (अस्पताल)'),
                                ),
                            ],
                            const DropdownMenuItem(
                              value: 'Other',
                              child: Text('Other / Custom Hospital (अन्य / म्यानुअल अस्पताल)'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val == null) return;
                            if (val == 'Other') {
                              final manual = _customFollowUpHospitalController.text.trim();
                              vm.setOuttake(destination: manual.isNotEmpty ? manual : 'Other');
                            } else {
                              vm.setOuttake(destination: val);
                            }
                          },
                        ),
                        if (dropdownValue == 'Other' || isCustom) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _customFollowUpHospitalController,
                            decoration: const InputDecoration(
                              labelText: 'Manual Hospital / Center Name (अस्पताल वा संस्थाको नाम)',
                              hintText: 'Enter name of hospital, clinic, or health post...',
                              prefixIcon: Icon(Icons.local_hospital_outlined),
                            ),
                            onChanged: (val) {
                              vm.setOuttake(destination: val.trim().isNotEmpty ? val.trim() : 'Other');
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const Divider(height: 1),
                const RadioListTile<bool>(
                  title: Text('No Follow-up Needed (थप जाँच आवश्यक छैन)'),
                  value: false,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        const Text('Clinical Notes / Referral Summary (अन्तिम टिप्पणी)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _outtakeNotesController,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Enter clinical impressions, patient instructions, or surgical notes...',
          ),
          onChanged: (val) => vm.setOuttake(notes: val),
        ),
        const SizedBox(height: 20),
        const Text('Attending / Examining Doctor(s) (जाँच गर्ने चिकित्सकहरू)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final campState = ref.watch(campStateProvider);
            CampModel? pCamp;
            try {
              pCamp = campState.camps.firstWhere((c) => c.id == widget.patient.campId);
            } catch (_) {}
            final doctors = pCamp?.doctorNames.isNotEmpty == true
                ? pCamp!.doctorNames
                : (pCamp?.doctorName.isNotEmpty == true ? [pCamp!.doctorName] : <String>[]);

            if (doctors.isEmpty) {
              return const Text(
                'No doctors assigned to this camp in camp settings.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.blueGrey),
              );
            }

            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: doctors.map((doc) {
                final isSelected = state.attendingDoctorNames.contains(doc);
                return FilterChip(
                  avatar: CircleAvatar(
                    radius: 12,
                    backgroundColor: isSelected ? Colors.white : AppTheme.primaryTeal.withValues(alpha: 0.2),
                    child: Icon(Icons.person, size: 14, color: isSelected ? AppTheme.primaryTeal : Colors.blueGrey),
                  ),
                  label: Text(doc, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  selected: isSelected,
                  selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                  checkmarkColor: AppTheme.primaryTeal,
                  onSelected: (_) => vm.toggleAttendingDoctor(doc),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 18),
        const Text('Attending / Assisting Nurse(s) (सेवा दिने नर्सहरू)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF81005D))),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final campState = ref.watch(campStateProvider);
            CampModel? pCamp;
            try {
              pCamp = campState.camps.firstWhere((c) => c.id == widget.patient.campId);
            } catch (_) {}
            final nurses = pCamp?.nurseProfiles ?? <NurseProfile>[];

            if (nurses.isEmpty) {
              return const Text(
                'No nurses assigned to this camp in camp settings.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.blueGrey),
              );
            }

            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: nurses.map((nurse) {
                final nurseKey = nurse.displayName;
                final isSelected = state.attendingNurseNames.contains(nurseKey) ||
                    state.attendingNurseNames.any((n) => n.toLowerCase().trim() == nurse.name.toLowerCase().trim());
                return FilterChip(
                  avatar: CircleAvatar(
                    radius: 12,
                    backgroundColor: isSelected ? Colors.white : const Color(0xFF81005D).withValues(alpha: 0.15),
                    child: Icon(Icons.badge_outlined, size: 14, color: isSelected ? const Color(0xFF81005D) : Colors.pink.shade700),
                  ),
                  label: Text(nurse.formattedLabel, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  selected: isSelected,
                  selectedColor: const Color(0xFFFCE7F3),
                  checkmarkColor: const Color(0xFF81005D),
                  onSelected: (_) => vm.toggleAttendingNurse(nurseKey),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
