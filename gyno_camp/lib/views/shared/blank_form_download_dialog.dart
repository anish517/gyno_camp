// ignore_for_file: deprecated_member_use
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/organization_provider.dart';
import '../../core/services/file_download_helper.dart';
import '../../core/services/pdf_report_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/camp_model.dart';
import '../../models/patient_model.dart';
import '../../models/user_model.dart';
import '../../repositories/patient_repository.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/master_lookup_viewmodel.dart';
import '../../viewmodels/patient_registration_viewmodel.dart';

enum PrintableFormType {
  yellowRegistrationForm,
  followUpEncounterSlip,
}

enum DoctorSelectionMode {
  allDoctorsChecklist, // every camp doctor as a tick-box (multi-select on paper)
  specificDoctor, // one pre-printed doctor
  allDoctorsBatch, // separate copies for each doctor
  blankDoctorField, // blank doctor name / signature lines
}

/// How the attending nurse(s) appear on a printed blank form.
enum NurseSelectionMode {
  allNursesChecklist, // every camp nurse as a tick-box (multi-select on paper)
  specificNurse, // one pre-printed nurse
  allNursesBatch, // separate copies for each nurse
  blankNurseField, // blank nurse name / signature lines
}

class BlankFormDownloadDialog extends ConsumerStatefulWidget {
  final CampModel? camp;

  const BlankFormDownloadDialog({
    super.key,
    this.camp,
  });

  static Future<void> show(BuildContext context, {CampModel? camp}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => BlankFormDownloadDialog(camp: camp),
    );
  }

  @override
  ConsumerState<BlankFormDownloadDialog> createState() => _BlankFormDownloadDialogState();
}

class _BlankFormDownloadDialogState extends ConsumerState<BlankFormDownloadDialog> {
  CampModel? _selectedCamp;
  PrintableFormType _selectedFormType = PrintableFormType.yellowRegistrationForm;
  DoctorSelectionMode _doctorMode = DoctorSelectionMode.allDoctorsChecklist;
  DoctorProfile? _selectedDoctor;
  NurseSelectionMode _nurseMode = NurseSelectionMode.allNursesChecklist;
  NurseProfile? _selectedNurse;
  bool _includeBlankNurseLine = false; // used only when the camp has no nurses
  bool _isGenerating = false;
  String? _progressMessage;
  double? _progressValue;

  // Pre-numbered Patient Token Range State
  static const int maxPreNumberedBatchSize = 5000;
  static const int defaultVolumeChunkSize = 250;

  bool _enablePreNumberedTokens = false;
  int _nextAvailableToken = 1;
  bool? _userSplitVolumesOverride;
  final TextEditingController _startTokenController = TextEditingController(text: '1');
  final TextEditingController _tokenCountController = TextEditingController(text: '50');

  int? get _rawParsedCount => int.tryParse(_tokenCountController.text.trim());

  bool get isTokenCountClamped {
    final val = _rawParsedCount;
    return val != null && val > maxPreNumberedBatchSize;
  }

  int get safeStartToken {
    final val = int.tryParse(_startTokenController.text.trim());
    return (val != null && val > 0) ? val : 1;
  }

  int get safeTokenCount {
    final val = _rawParsedCount;
    if (val == null || val <= 0) return 50;
    if (val > maxPreNumberedBatchSize) return maxPreNumberedBatchSize;
    return val;
  }

  bool get effectiveSplitIntoVolumes {
    if (safeTokenCount <= defaultVolumeChunkSize) return false;
    return _userSplitVolumesOverride ?? (safeTokenCount >= 500);
  }

  int get plannedVolumeCount {
    if (!effectiveSplitIntoVolumes) return 1;
    return (safeTokenCount / defaultVolumeChunkSize).ceil();
  }

  void _applyBulkRange({required int start, required int count}) {
    final cleanStart = start < 1 ? 1 : start;
    final cleanCount = count.clamp(1, maxPreNumberedBatchSize);
    _startTokenController.text = '$cleanStart';
    _tokenCountController.text = '$cleanCount';
    setState(() {});
  }

  void _setStartToken(int start) {
    final cleanStart = start < 1 ? 1 : start;
    _startTokenController.text = '$cleanStart';
    setState(() {});
  }

  void _setTokenCount(int count) {
    final cleanCount = count.clamp(1, maxPreNumberedBatchSize);
    _tokenCountController.text = '$cleanCount';
    setState(() {});
  }

  void _stepTokenBlock(int direction) {
    final nextStart = safeStartToken + (direction * safeTokenCount);
    _setStartToken(nextStart < 1 ? 1 : nextStart);
  }

  @override
  void initState() {
    super.initState();
    final user = ref.read(authStateProvider).currentUser;
    final isSuperAdmin = user?.role == UserRole.superAdmin || (user?.isSuperAdmin ?? false);
    final isPrivileged = isSuperAdmin || user?.role == UserRole.staff || user?.role == UserRole.dataAnalyst;

    CampModel? initialCamp = widget.camp;
    if (!isPrivileged && user != null) {
      final campState = ref.read(campStateProvider);
      final assignedCamps = campState.camps
          .where((c) =>
              c.isStaffAssigned(user.id) ||
              user.assignedCampIds.contains(c.id))
          .toList();

      if (initialCamp != null && !assignedCamps.any((c) => c.id == initialCamp!.id)) {
        initialCamp = null;
      }
      initialCamp ??= ref.read(userActiveCampProvider) ?? (assignedCamps.isNotEmpty ? assignedCamps.first : null);
    }

    _selectedCamp = initialCamp;
    _resetCliniciansForCamp(initialCamp, shouldInitToken: true);
  }

  void _resetCliniciansForCamp(CampModel? camp, {bool shouldInitToken = true}) {
    _selectedCamp = camp;
    if (camp == null) {
      _doctorMode = DoctorSelectionMode.blankDoctorField;
      _selectedDoctor = null;
      _nurseMode = NurseSelectionMode.blankNurseField;
      _selectedNurse = null;
      _includeBlankNurseLine = true;
      _enablePreNumberedTokens = false;
    } else {
      final doctors = camp.doctorProfiles;
      if (doctors.length > 1) {
        _doctorMode = DoctorSelectionMode.allDoctorsChecklist;
        _selectedDoctor = doctors.first;
      } else if (doctors.length == 1) {
        _doctorMode = DoctorSelectionMode.specificDoctor;
        _selectedDoctor = doctors.first;
      } else {
        _doctorMode = DoctorSelectionMode.blankDoctorField;
        _selectedDoctor = null;
      }

      final nurses = camp.nurseProfiles;
      if (nurses.length > 1) {
        _nurseMode = NurseSelectionMode.allNursesChecklist;
        _selectedNurse = nurses.first;
      } else if (nurses.length == 1) {
        _nurseMode = NurseSelectionMode.specificNurse;
        _selectedNurse = nurses.first;
      } else {
        _nurseMode = NurseSelectionMode.blankNurseField;
        _selectedNurse = null;
      }
      if (shouldInitToken) {
        _initStartingToken(camp);
      }
    }
  }

  @override
  void dispose() {
    _startTokenController.dispose();
    _tokenCountController.dispose();
    super.dispose();
  }

  Future<void> _initStartingToken([CampModel? targetCamp]) async {
    final camp = targetCamp ?? _selectedCamp;
    if (camp == null) return;
    try {
      // Global continuous 5-digit sequence across all camps (ignoring historical GC-... records)
      final patientRepo = ref.read(patientRepositoryProvider);
      int nextSeq;
      if (patientRepo is PatientRepository) {
        nextSeq = await patientRepo.getNextAvailableSequenceNumber();
      } else {
        final patients = await patientRepo.getPatientsByCamp();
        int highestSeq = 0;
        for (final p in patients) {
          final pid = p.patientId.trim();
          if (RegExp(r'^\d+$').hasMatch(pid)) {
            final num = int.tryParse(pid);
            if (num != null && num > highestSeq) {
              highestSeq = num;
            }
          }
        }
        nextSeq = highestSeq + 1;
      }
      if (mounted) {
        setState(() {
          _nextAvailableToken = nextSeq < 1 ? 1 : nextSeq;
          _startTokenController.text = '$_nextAvailableToken';
        });
      }
    } catch (_) {}
  }

  Future<void> _generateAndDownload() async {
    setState(() {
      _isGenerating = true;
      _progressMessage = 'Preparing PDF document...';
      _progressValue = 0.0;
    });
    final messenger = ScaffoldMessenger.of(context);

    try {
      final effectiveOrg = ref.read(effectiveOrganizationProvider);
      final orgName = (_selectedCamp?.organizationName.isNotEmpty == true &&
              !AppConstants.isLegacyDefaultOrganization(_selectedCamp!.organizationName))
          ? _selectedCamp!.organizationName
          : effectiveOrg;

      final repo = ref.read(lookupRepositoryProvider);
      final user = ref.read(authStateProvider).currentUser;
      final isSuperAdmin = user?.role == UserRole.superAdmin || (user?.isSuperAdmin ?? false);
      final isPrivileged = isSuperAdmin || user?.role == UserRole.staff || user?.role == UserRole.dataAnalyst;

      if (!isPrivileged && user != null) {
        if (_selectedCamp == null) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Cannot download: You are not assigned to any health camp.'),
              backgroundColor: AppTheme.dangerRose,
            ),
          );
          return;
        }
        final isAssigned = _selectedCamp!.isStaffAssigned(user.id) || user.assignedCampIds.contains(_selectedCamp!.id);
        if (!isAssigned) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Access restricted: You are not assigned to camp "${_selectedCamp!.name}".'),
              backgroundColor: AppTheme.dangerRose,
            ),
          );
          return;
        }
      }

      final tenantId = user?.tenantId;
      final campId = _selectedCamp?.id;

      final diagnoses = await repo.getItemsByCategory('diagnosis', tenantId: tenantId, campId: campId, activeOnly: true);
      final medications = await repo.getItemsByCategory('medicine', tenantId: tenantId, campId: campId, activeOnly: true);
      final referralHospitals = await repo.getItemsByCategory('referral_hospital', tenantId: tenantId, campId: campId, activeOnly: true);
      final visitReasons = await repo.getItemsByCategory('visit_reason', tenantId: tenantId, campId: campId, activeOnly: true);
      final chiefComplaints = await repo.getItemsByCategory('chief_complaint', tenantId: tenantId, campId: campId, activeOnly: true);

      final pdfService = PdfReportService();
      final doctors = _selectedCamp?.doctorProfiles ?? [];
      final nurses = _selectedCamp?.nurseProfiles ?? [];
      final NurseProfile? nurseToUse =
          (nurses.isNotEmpty && _nurseMode == NurseSelectionMode.specificNurse)
              ? _selectedNurse
              : null;
      final bool blankNurse = _selectedCamp == null
          ? true
          : (nurses.isNotEmpty
              ? _nurseMode == NurseSelectionMode.blankNurseField
              : _includeBlankNurseLine);

      final DoctorProfile? docToUse =
          (doctors.isNotEmpty && _doctorMode == DoctorSelectionMode.specificDoctor)
              ? _selectedDoctor
              : null;
      final bool blankDoctor = _selectedCamp == null
          ? true
          : (doctors.isNotEmpty
              ? _doctorMode == DoctorSelectionMode.blankDoctorField
              : true);

      Uint8List pdfBytes;
      String filename;
      final campCode = _selectedCamp?.campCode ?? 'CAMP';

      if (_enablePreNumberedTokens && _selectedCamp != null) {
        final startSeq = safeStartToken;
        final count = safeTokenCount;
        final endSeq = startSeq + count - 1;
        final startPad = startSeq.toString().padLeft(5, '0');
        final endPad = endSeq.toString().padLeft(5, '0');

        if (effectiveSplitIntoVolumes) {
          final totalVolumes = plannedVolumeCount;
          DownloadResult? lastResult;

          for (int volIdx = 0; volIdx < totalVolumes; volIdx++) {
            final volOffset = volIdx * defaultVolumeChunkSize;
            final volStartSeq = startSeq + volOffset;
            final remaining = count - volOffset;
            final volCount = remaining > defaultVolumeChunkSize ? defaultVolumeChunkSize : remaining;
            final volEndSeq = volStartSeq + volCount - 1;
            final volStartPad = volStartSeq.toString().padLeft(5, '0');
            final volEndPad = volEndSeq.toString().padLeft(5, '0');

            final Uint8List volBytes;
            final String volFilename;
            if (_selectedFormType == PrintableFormType.yellowRegistrationForm) {
              volBytes = await pdfService.generatePreNumberedBlankFormsPdf(
                camp: _selectedCamp!,
                startSequence: volStartSeq,
                count: volCount,
                doctor: docToUse,
                nurse: nurseToUse,
                blankNurseLines: blankNurse,
                blankDoctorLines: blankDoctor,
                allDoctorsChecklist: _doctorMode == DoctorSelectionMode.allDoctorsChecklist,
                allNursesChecklist: _nurseMode == NurseSelectionMode.allNursesChecklist,
                organizationName: orgName,
                diagnoses: diagnoses,
                medications: medications,
                referralHospitals: referralHospitals,
                visitReasons: visitReasons,
                chiefComplaints: chiefComplaints,
                onProgress: (current, total, _) {
                  if (mounted) {
                    final overallDone = volOffset + current;
                    setState(() {
                      _progressMessage =
                          'Volume ${volIdx + 1}/$totalVolumes • Form $overallDone of $count (${(overallDone / count * 100).toInt()}%)...';
                      _progressValue = overallDone / count;
                    });
                  }
                },
              );
              volFilename =
                  'Blank_YellowForms_${campCode}_${volStartPad}_to_${volEndPad}_Part${volIdx + 1}of$totalVolumes.pdf';
            } else {
              volBytes = await pdfService.generatePreNumberedBlankFollowUpSlipsPdf(
                camp: _selectedCamp!,
                startSequence: volStartSeq,
                count: volCount,
                doctor: docToUse,
                blankDoctorLines: blankDoctor,
                nurse: nurseToUse,
                blankNurseLines: blankNurse,
                organizationName: orgName,
                onProgress: (current, total, _) {
                  if (mounted) {
                    final overallDone = volOffset + current;
                    setState(() {
                      _progressMessage =
                          'Volume ${volIdx + 1}/$totalVolumes • Sheet $overallDone of $count (${(overallDone / count * 100).toInt()}%)...';
                      _progressValue = overallDone / count;
                    });
                  }
                },
              );
              volFilename =
                  'Blank_FollowUpSlips_${campCode}_${volStartPad}_to_${volEndPad}_Part${volIdx + 1}of$totalVolumes.pdf';
            }

            lastResult = await FileDownloadHelper.saveAndDownloadFile(
              bytes: volBytes,
              filename: volFilename,
              mimeType: 'application/pdf',
            );

            if (!lastResult.isSuccess) {
              break;
            }
            if (volIdx < totalVolumes - 1) {
              await Future.delayed(const Duration(milliseconds: 120));
            }
          }

          if (mounted && lastResult != null) {
            Navigator.pop(context);
            if (lastResult.isSuccess) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    'Downloaded $totalVolumes PDF volumes ($startPad to $endPad • $count forms) to ${lastResult.displayLocation}.',
                  ),
                  backgroundColor: AppTheme.successGreen,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 5),
                ),
              );
            } else {
              FileDownloadHelper.showDownloadFeedback(context, lastResult);
            }
          }
          return;
        }

        if (_selectedFormType == PrintableFormType.yellowRegistrationForm) {
          pdfBytes = await pdfService.generatePreNumberedBlankFormsPdf(
            camp: _selectedCamp!,
            startSequence: startSeq,
            count: count,
            doctor: docToUse,
            nurse: nurseToUse,
            blankNurseLines: blankNurse,
            blankDoctorLines: blankDoctor,
            allDoctorsChecklist: _doctorMode == DoctorSelectionMode.allDoctorsChecklist,
            allNursesChecklist: _nurseMode == NurseSelectionMode.allNursesChecklist,
            organizationName: orgName,
            diagnoses: diagnoses,
            medications: medications,
            referralHospitals: referralHospitals,
            visitReasons: visitReasons,
            chiefComplaints: chiefComplaints,
            onProgress: (current, total, status) {
              if (mounted) {
                setState(() {
                  _progressMessage = status;
                  _progressValue = current / total;
                });
              }
            },
          );
          filename = 'Blank_YellowForms_${campCode}_${startPad}_to_$endPad.pdf';
        } else {
          pdfBytes = await pdfService.generatePreNumberedBlankFollowUpSlipsPdf(
            camp: _selectedCamp!,
            startSequence: startSeq,
            count: count,
            doctor: docToUse,
            blankDoctorLines: blankDoctor,
            nurse: nurseToUse,
            blankNurseLines: blankNurse,
            organizationName: orgName,
            onProgress: (current, total, status) {
              if (mounted) {
                setState(() {
                  _progressMessage = status;
                  _progressValue = current / total;
                });
              }
            },
          );
          filename = 'Blank_FollowUpSlips_${campCode}_${startPad}_to_$endPad.pdf';
        }
      } else if (_selectedFormType == PrintableFormType.yellowRegistrationForm) {
        if (_selectedCamp == null) {
          // Universal Mode: Clean open boxes and blank signatures
          pdfBytes = await pdfService.generatePatientRegistrationFormPdf(
            camp: null,
            doctor: null,
            nurse: null,
            blankNurseLines: true,
            blankDoctorLines: true,
            allDoctorsChecklist: false,
            allNursesChecklist: false,
            organizationName: orgName,
            diagnoses: diagnoses,
            medications: medications,
            referralHospitals: referralHospitals,
            visitReasons: visitReasons,
            chiefComplaints: chiefComplaints,
          );
          filename = 'Blank_Universal_YellowForm.pdf';
        } else if (_doctorMode == DoctorSelectionMode.allDoctorsBatch && doctors.isNotEmpty) {
          // Batch download: generate combined multi-page PDF with 2 pages for each doctor
          messenger.showSnackBar(
            SnackBar(
              content: Text('Generating batch forms for ${doctors.length} doctors (${doctors.length * 2} pages)...'),
              duration: const Duration(seconds: 2),
            ),
          );
          pdfBytes = await pdfService.generateBatchBlankYellowFormsPdf(
            doctors: doctors,
            camp: _selectedCamp,
            nurse: nurseToUse,
            blankNurseLines: blankNurse,
            organizationName: orgName,
            diagnoses: diagnoses,
            medications: medications,
            referralHospitals: referralHospitals,
            visitReasons: visitReasons,
            chiefComplaints: chiefComplaints,
          );
          filename = 'Blank_YellowForms_${campCode}_AllDoctorsBatch.pdf';
        } else if (_nurseMode == NurseSelectionMode.allNursesBatch && nurses.isNotEmpty) {
          // Batch download: generate combined multi-page PDF with 2 pages for each nurse
          messenger.showSnackBar(
            SnackBar(
              content: Text('Generating batch forms for ${nurses.length} nurses (${nurses.length * 2} pages)...'),
              duration: const Duration(seconds: 2),
            ),
          );
          pdfBytes = await pdfService.generateBatchBlankYellowFormsByNursesPdf(
            nurses: nurses,
            camp: _selectedCamp,
            doctor: docToUse,
            blankDoctorLines: blankDoctor,
            organizationName: orgName,
            diagnoses: diagnoses,
            medications: medications,
            referralHospitals: referralHospitals,
            visitReasons: visitReasons,
            chiefComplaints: chiefComplaints,
          );
          filename = 'Blank_YellowForms_${campCode}_AllNursesBatch.pdf';
        } else {
          pdfBytes = await pdfService.generatePatientRegistrationFormPdf(
            camp: _selectedCamp,
            doctor: docToUse,
            nurse: nurseToUse,
            blankNurseLines: blankNurse,
            blankDoctorLines: blankDoctor,
            allDoctorsChecklist: _doctorMode == DoctorSelectionMode.allDoctorsChecklist,
            allNursesChecklist: _nurseMode == NurseSelectionMode.allNursesChecklist,
            organizationName: orgName,
            diagnoses: diagnoses,
            medications: medications,
            referralHospitals: referralHospitals,
            visitReasons: visitReasons,
            chiefComplaints: chiefComplaints,
          );
          final String docSlug;
          if (_doctorMode == DoctorSelectionMode.allDoctorsChecklist) {
            docSlug = '_DoctorsChecklist';
          } else if (_doctorMode == DoctorSelectionMode.blankDoctorField) {
            docSlug = '_BlankDoctor';
          } else if (docToUse != null) {
            docSlug = '_${docToUse.name.replaceAll(' ', '_')}';
          } else {
            docSlug = '';
          }

          final String nurseSlug;
          if (_nurseMode == NurseSelectionMode.allNursesChecklist) {
            nurseSlug = '_NursesChecklist';
          } else if (_nurseMode == NurseSelectionMode.blankNurseField) {
            nurseSlug = '_BlankNurse';
          } else if (nurseToUse != null) {
            nurseSlug = '_${nurseToUse.name.replaceAll(' ', '_')}';
          } else {
            nurseSlug = '';
          }

          filename = 'Blank_YellowForm_$campCode$docSlug$nurseSlug.pdf';
        }
      } else {
        // Follow-Up Form
        if (_selectedCamp == null) {
          // Universal Mode: Clean open boxes and blank signatures
          pdfBytes = await pdfService.generateBlankFollowUpSlipPdf(
            camp: null,
            doctor: null,
            blankDoctorLines: true,
            nurse: null,
            blankNurseLines: true,
            organizationName: orgName,
          );
          filename = 'Blank_Universal_FollowUpSlip.pdf';
        } else if (_doctorMode == DoctorSelectionMode.allDoctorsBatch && doctors.isNotEmpty) {
          // Batch download: generate combined multi-page PDF with 1 page for each doctor
          messenger.showSnackBar(
            SnackBar(
              content: Text('Generating batch follow-up sheets for ${doctors.length} doctors (${doctors.length} pages)...'),
              duration: const Duration(seconds: 2),
            ),
          );
          pdfBytes = await pdfService.generateBatchBlankFollowUpSlipsPdf(
            doctors: doctors,
            camp: _selectedCamp,
            nurse: nurseToUse,
            blankNurseLines: blankNurse,
            organizationName: orgName,
          );
          filename = 'Blank_FollowUpSlips_${campCode}_AllDoctorsBatch.pdf';
        } else if (_nurseMode == NurseSelectionMode.allNursesBatch && nurses.isNotEmpty) {
          // Batch download: generate combined multi-page PDF with 1 page for each nurse
          messenger.showSnackBar(
            SnackBar(
              content: Text('Generating batch follow-up sheets for ${nurses.length} nurses (${nurses.length} pages)...'),
              duration: const Duration(seconds: 2),
            ),
          );
          pdfBytes = await pdfService.generateBatchBlankFollowUpSlipsByNursesPdf(
            nurses: nurses,
            camp: _selectedCamp,
            doctor: docToUse,
            blankDoctorLines: blankDoctor,
            organizationName: orgName,
          );
          filename = 'Blank_FollowUpSlips_${campCode}_AllNursesBatch.pdf';
        } else {
          pdfBytes = await pdfService.generateBlankFollowUpSlipPdf(
            camp: _selectedCamp,
            doctor: docToUse,
            blankDoctorLines: blankDoctor,
            nurse: nurseToUse,
            blankNurseLines: blankNurse,
            organizationName: orgName,
          );
          final String docSlug;
          if (_doctorMode == DoctorSelectionMode.allDoctorsChecklist) {
            docSlug = '_DoctorsChecklist';
          } else if (_doctorMode == DoctorSelectionMode.blankDoctorField) {
            docSlug = '_BlankDoctor';
          } else if (docToUse != null) {
            docSlug = '_${docToUse.name.replaceAll(' ', '_')}';
          } else {
            docSlug = '';
          }

          final String nurseSlug;
          if (_nurseMode == NurseSelectionMode.allNursesChecklist) {
            nurseSlug = '_NursesChecklist';
          } else if (_nurseMode == NurseSelectionMode.blankNurseField) {
            nurseSlug = '_BlankNurse';
          } else if (nurseToUse != null) {
            nurseSlug = '_${nurseToUse.name.replaceAll(' ', '_')}';
          } else {
            nurseSlug = '';
          }

          filename = 'Blank_FollowUpSlip_$campCode$docSlug$nurseSlug.pdf';
        }
      }

      final result = await FileDownloadHelper.saveAndDownloadFile(
        bytes: pdfBytes,
        filename: filename,
        mimeType: 'application/pdf',
      );

      if (mounted) {
        Navigator.pop(context);
        FileDownloadHelper.showDownloadFeedback(context, result);
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to generate form: $e'),
            backgroundColor: AppTheme.dangerRose,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _progressMessage = null;
          _progressValue = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final campState = ref.watch(campStateProvider);
    final user = ref.watch(authStateProvider).currentUser;
    final isSuperAdmin = user?.role == UserRole.superAdmin || (user?.isSuperAdmin ?? false);
    final isPrivileged = isSuperAdmin || user?.role == UserRole.staff || user?.role == UserRole.dataAnalyst;

    final visibleCamps = isPrivileged || user == null
        ? campState.camps
        : campState.camps
            .where((c) =>
                c.isStaffAssigned(user.id) ||
                user.assignedCampIds.contains(c.id))
            .toList();

    // Auto-heal / guard selection for non-privileged users
    if (!isPrivileged && user != null && visibleCamps.isNotEmpty) {
      if (_selectedCamp == null || !visibleCamps.any((c) => c.id == _selectedCamp!.id)) {
        final fallback = ref.read(userActiveCampProvider);
        final nextCamp = (fallback != null && visibleCamps.any((c) => c.id == fallback.id))
            ? fallback
            : visibleCamps.first;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _resetCliniciansForCamp(nextCamp);
            });
          }
        });
      }
    }

    final canDownload = !_isGenerating &&
        (isPrivileged || user == null || (visibleCamps.isNotEmpty && _selectedCamp != null));
    final downloadLabel = _isGenerating
        ? 'Generating PDF...'
        : (!isPrivileged && user != null && visibleCamps.isEmpty)
            ? 'No Assigned Camp'
            : (_selectedCamp == null
                ? 'Download Universal Blank Form (PDF)'
                : (_enablePreNumberedTokens
                    ? (effectiveSplitIntoVolumes
                        ? 'Download $safeTokenCount Pre-Numbered Forms ($plannedVolumeCount PDFs)'
                        : 'Download $safeTokenCount Pre-Numbered Forms')
                    : 'Download Printable PDF'));

    final doctors = _selectedCamp?.doctorProfiles ?? [];
    final hasDoctors = doctors.isNotEmpty;
    final showDoctorSetting = _selectedCamp?.showDoctorOnForms ?? true;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompactScreen = screenWidth < 500;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompactScreen ? 14 : 20,
        vertical: isCompactScreen ? 16 : 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 460;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 16 : 20,
                    vertical: isNarrow ? 14 : 16,
                  ),
                  decoration: const BoxDecoration(
                    color: AppTheme.brandPurple,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(isNarrow ? 7 : 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.print_rounded, color: Colors.white, size: isNarrow ? 20 : 22),
                      ),
                      SizedBox(width: isNarrow ? 10 : 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Blank Forms & Clinical Sheets',
                              style: TextStyle(
                                fontSize: isNarrow ? 15 : 16.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _selectedCamp != null
                                  ? '${_selectedCamp!.name} (${_selectedCamp!.campCode})'
                                  : 'Universal Master Blank Form (सार्वभौमिक फाराम)',
                              style: const TextStyle(fontSize: 12, color: Colors.white70),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        onPressed: _isGenerating ? null : () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Body
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(isNarrow ? 14 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Camp Scope Selector (Universal vs Specific Camp)
                        _buildCampScopeSelector(
                          visibleCamps,
                          ref.watch(userActiveCampProvider) ?? campState.activeCamp,
                          isNarrow,
                          isPrivileged: isPrivileged,
                        ),

                        // Form Type Selection
                        const Text(
                          '1. SELECT CLINICAL FORM TYPE (फारामको प्रकार)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: AppTheme.brandPurple,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildFormTypeCard(
                          type: PrintableFormType.yellowRegistrationForm,
                          title: 'Yellow Form — Intake & Clinical Exam (2 Pages A4)',
                          subtitle: 'Standard Nepal MoHP Yellow registration grid + 6-station clinical exam.',
                          badge: 'Primary Assessment',
                          icon: Icons.description_rounded,
                          color: const Color(0xFFD97706),
                          bgColor: const Color(0xFFFFFBEB),
                          isNarrow: isNarrow,
                        ),
                        const SizedBox(height: 10),
                        _buildFormTypeCard(
                          type: PrintableFormType.followUpEncounterSlip,
                          title: 'Follow-Up Clinical Encounter Sheet (1 Page A4)',
                          subtitle: 'Specialized re-check sheet for returning patients, pessary reviews & medication refills.',
                          badge: 'Follow-Up / Re-check',
                          icon: Icons.replay_rounded,
                          color: const Color(0xFF0891B2),
                          bgColor: const Color(0xFFECFEFF),
                          isNarrow: isNarrow,
                        ),


                        const SizedBox(height: 22),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        const SizedBox(height: 18),

                        // Doctor & NMC Selection
                        const Text(
                          '2. EXAMINING DOCTOR & NMC STAMP (चिकित्सक र NMC नं.)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: AppTheme.brandPurple,
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (_selectedCamp == null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.assignment_ind_outlined, color: Color(0xFF2563EB), size: 20),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Universal Mode: Leaves Doctor Name, NMC Number, and Signature box blank with clean write-in lines for manual signing on-site.',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (!showDoctorSetting) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline_rounded, color: Color(0xFFB45309), size: 20),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Camp setting has "Show Doctor Name on Forms" switched OFF. Doctor headers and signatures will be generated with blank lines for manual on-site signing.',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (!hasDoctors) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.person_off_outlined, color: Color(0xFF64748B), size: 20),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'No doctors currently assigned to this camp. Forms will be generated with blank lines for doctor name, NMC number, and physical signature.',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // Doctor Selection Options
                          if (doctors.length > 1) ...[
                            RadioListTile<DoctorSelectionMode>(
                              dense: true,
                              activeColor: AppTheme.brandPurple,
                              contentPadding: EdgeInsets.zero,
                              value: DoctorSelectionMode.allDoctorsChecklist,
                              groupValue: _doctorMode,
                              title: Text('All Camp Doctors Checklist (${doctors.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: const Text('Prints every assigned doctor as a tick-box; tick one or more on paper', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                              onChanged: (val) => setState(() => _doctorMode = val!),
                            ),
                          ],
                          RadioListTile<DoctorSelectionMode>(
                            dense: true,
                            activeColor: AppTheme.brandPurple,
                            contentPadding: EdgeInsets.zero,
                            value: DoctorSelectionMode.specificDoctor,
                            groupValue: _doctorMode,
                            title: const Text('Specific Doctor (तोकिएको चिकित्सक)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: const Text('Pre-prints the selected doctor\'s name and NMC number on the form', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                            onChanged: (val) => setState(() => _doctorMode = val!),
                          ),
                          if (_doctorMode == DoctorSelectionMode.specificDoctor) ...[
                            Padding(
                              padding: EdgeInsets.only(left: isNarrow ? 16 : 32, bottom: 8),
                              child: DropdownButtonFormField<DoctorProfile>(
                                value: _selectedDoctor,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'Choose Doctor (चिकित्सक छान्नुहोस्)',
                                  isDense: true,
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                items: doctors.map((doc) {
                                  return DropdownMenuItem(
                                    value: doc,
                                    child: Text(
                                      doc.formattedLabel,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) => setState(() => _selectedDoctor = val),
                              ),
                            ),
                          ],
                          if (doctors.length > 1) ...[
                            RadioListTile<DoctorSelectionMode>(
                              dense: true,
                              activeColor: AppTheme.brandPurple,
                              contentPadding: EdgeInsets.zero,
                              value: DoctorSelectionMode.allDoctorsBatch,
                              groupValue: _doctorMode,
                              title: Text('All Assigned Doctors (${doctors.length} Doctors Batch)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: const Text('Generates separate doctor-wise copies for each doctor in the roster', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                              onChanged: (val) => setState(() => _doctorMode = val!),
                            ),
                          ],
                          RadioListTile<DoctorSelectionMode>(
                            dense: true,
                            activeColor: AppTheme.brandPurple,
                            contentPadding: EdgeInsets.zero,
                            value: DoctorSelectionMode.blankDoctorField,
                            groupValue: _doctorMode,
                            title: const Text('Blank Doctor Lines (हस्तलिखित / स्थानीय छाप)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: const Text('Leaves doctor and NMC boxes blank with a signature line for manual signing on-site', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                            onChanged: (val) => setState(() => _doctorMode = val!),
                          ),
                        ],

                        if (_selectedCamp?.showNurseOnForms == true) ...[
                          const SizedBox(height: 22),
                          const Divider(height: 1, color: Color(0xFFE2E8F0)),
                          const SizedBox(height: 18),
                          _buildNurseSection(isNarrow),
                        ],
                        const SizedBox(height: 22),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        const SizedBox(height: 18),
                        _buildTokenRangeSection(isNarrow),
                      ],
                    ),
                  ),
                ),

                // Footer / Actions
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 16 : 20,
                    vertical: isNarrow ? 12 : 14,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isGenerating && _progressMessage != null) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.brandPurple.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.brandPurple.withOpacity(0.25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.brandPurple,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _progressMessage!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.brandPurple,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (_progressValue != null) ...[
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: _progressValue,
                                    backgroundColor: AppTheme.brandPurple.withOpacity(0.15),
                                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.brandPurple),
                                    minHeight: 4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (isNarrow)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: canDownload ? _generateAndDownload : null,
                              icon: _isGenerating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.download_rounded, size: 18),
                              label: Text(
                                _isGenerating
                                    ? (_progressMessage ?? 'Generating...')
                                    : downloadLabel,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.brandPurple,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: _isGenerating ? null : () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF64748B),
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Cancel', style: TextStyle(fontSize: 13)),
                            ),
                          ],
                        )
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: _isGenerating ? null : () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF64748B),
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: ElevatedButton.icon(
                                onPressed: canDownload ? _generateAndDownload : null,
                                icon: _isGenerating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.download_rounded, size: 18),
                                label: Text(
                                  _isGenerating
                                      ? (_progressMessage ?? 'Generating...')
                                      : downloadLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.brandPurple,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Attending nurse selection (camp-level roster; not login based).
  Widget _buildNurseSection(bool isNarrow) {
    final nurses = _selectedCamp?.nurseProfiles ?? [];
    final hasNurses = nurses.isNotEmpty;
    final showNurseSetting = _selectedCamp?.showNurseOnForms ?? false;

    Widget infoBox(IconData icon, Color iconColor, Color bg, Color border, Color textColor, String text) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: textColor))),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '3. ATTENDING NURSE & NNC (सेवा दिने नर्स)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: AppTheme.brandPurple,
          ),
        ),
        const SizedBox(height: 10),
        if (_selectedCamp == null) ...[
          infoBox(
            Icons.badge_outlined,
            const Color(0xFF2563EB),
            const Color(0xFFEFF6FF),
            const Color(0xFFBFDBFE),
            const Color(0xFF1E40AF),
            'Universal Mode: Renders standard blank signature lines for Attending Nurse Name, NNC Number, and Signature box.',
          ),
        ] else if (!hasNurses) ...[
          infoBox(
            Icons.info_outline_rounded,
            const Color(0xFF64748B),
            const Color(0xFFF1F5F9),
            const Color(0xFFE2E8F0),
            const Color(0xFF475569),
            'No nurses assigned to this camp. Forms keep the standard layout without a nurse section.',
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeColor: AppTheme.brandPurple,
            title: const Text('Add blank nurse signature line', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('Leaves nurse name, signature and NNC blank for manual entry', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            value: _includeBlankNurseLine,
            onChanged: (val) => setState(() => _includeBlankNurseLine = val),
          ),
        ] else if (!showNurseSetting) ...[
          infoBox(
            Icons.info_outline_rounded,
            const Color(0xFFB45309),
            const Color(0xFFFEF3C7),
            const Color(0xFFFDE68A),
            const Color(0xFF92400E),
            'Camp setting has "Show on forms" switched OFF for nurses. Nurse name and signature will be generated with blank lines for manual signing.',
          ),
        ] else ...[
          RadioListTile<NurseSelectionMode>(
            dense: true,
            activeColor: AppTheme.brandPurple,
            contentPadding: EdgeInsets.zero,
            value: NurseSelectionMode.allNursesChecklist,
            groupValue: _nurseMode,
            title: Text('All Camp Nurses Checklist (${nurses.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('Prints every assigned nurse as a tick-box; tick one or more on paper', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            onChanged: (val) => setState(() => _nurseMode = val!),
          ),
          RadioListTile<NurseSelectionMode>(
            dense: true,
            activeColor: AppTheme.brandPurple,
            contentPadding: EdgeInsets.zero,
            value: NurseSelectionMode.specificNurse,
            groupValue: _nurseMode,
            title: const Text('Specific Nurse (तोकिएको नर्स)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('Pre-prints the selected nurse\'s name and NNC number', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            onChanged: (val) => setState(() => _nurseMode = val!),
          ),
          if (_nurseMode == NurseSelectionMode.specificNurse)
            Padding(
              padding: EdgeInsets.only(left: isNarrow ? 16 : 32, bottom: 8),
              child: DropdownButtonFormField<NurseProfile>(
                value: _selectedNurse,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Choose Nurse (नर्स छान्नुहोस्)',
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: nurses.map((n) {
                  return DropdownMenuItem(
                    value: n,
                    child: Text(
                      n.formattedLabel,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedNurse = val),
              ),
            ),
          if (nurses.length > 1) ...[
            RadioListTile<NurseSelectionMode>(
              dense: true,
              activeColor: AppTheme.brandPurple,
              contentPadding: EdgeInsets.zero,
              value: NurseSelectionMode.allNursesBatch,
              groupValue: _nurseMode,
              title: Text('All Assigned Nurses (${nurses.length} Nurses Batch)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('Generates separate nurse-wise copies for each nurse in the roster', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              onChanged: (val) => setState(() => _nurseMode = val!),
            ),
          ],
          RadioListTile<NurseSelectionMode>(
            dense: true,
            activeColor: AppTheme.brandPurple,
            contentPadding: EdgeInsets.zero,
            value: NurseSelectionMode.blankNurseField,
            groupValue: _nurseMode,
            title: const Text('Blank Nurse Lines (हस्तलिखित)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('Leaves nurse name, signature and NNC blank for manual entry on-site', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            onChanged: (val) => setState(() => _nurseMode = val!),
          ),
        ],
      ],
    );
  }

  Widget _buildFormTypeCard({
    required PrintableFormType type,
    required String title,
    required String subtitle,
    required String badge,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required bool isNarrow,
  }) {
    final isSelected = _selectedFormType == type;

    return InkWell(
      onTap: () => setState(() => _selectedFormType = type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(isNarrow ? 10 : 12),
        decoration: BoxDecoration(
          color: isSelected ? bgColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFE2E8F0),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(isNarrow ? 8 : 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: isNarrow ? 20 : 22),
            ),
            SizedBox(width: isNarrow ? 10 : 12),
            Expanded(
              child: isNarrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            height: 1.25,
                            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.25),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                badge,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildTokenRangeSection(bool isNarrow) {
    if (_selectedCamp == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.pin_outlined, size: 20, color: Color(0xFF64748B)),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '4. PATIENT TOKEN IDs (टोकन नं.)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Universal forms feature 5 clean character boxes: [ ][ ][ ][ ][ ] (e.g. 00001) for on-site token assignment. To generate pre-numbered sequential token barcodes, switch to a specific camp above.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final campCode = _selectedCamp!.campCode;
    final year = _selectedCamp!.startDate.year;
    final startSeq = safeStartToken;
    final count = safeTokenCount;
    final endSeq = startSeq + count - 1;
    final startId = PatientModel.generatePatientId(campCode: campCode, sequenceNumber: startSeq, year: year);
    final endId = PatientModel.generatePatientId(campCode: campCode, sequenceNumber: endSeq, year: year);
    final nextFreePad = _nextAvailableToken.toString().padLeft(5, '0');
    final totalPages = _selectedFormType == PrintableFormType.yellowRegistrationForm ? count * 2 : count;
    final canStepPrev = startSeq > 1;
    final showSplitOption = count > defaultVolumeChunkSize;

    final List<({String keyId, String label, int start, int count})> bulkPacks = [
      if (_nextAvailableToken > 1) ...[
        (keyId: 'bulk_pack_next_100', label: 'Next+100', start: _nextAvailableToken, count: 100),
        (keyId: 'bulk_pack_next_250', label: 'Next+250', start: _nextAvailableToken, count: 250),
        (keyId: 'bulk_pack_next_500', label: 'Next+500', start: _nextAvailableToken, count: 500),
      ],
      (keyId: 'bulk_pack_1_100', label: '1–100', start: 1, count: 100),
      (keyId: 'bulk_pack_101_200', label: '101–200', start: 101, count: 100),
      (keyId: 'bulk_pack_201_300', label: '201–300', start: 201, count: 100),
      (keyId: 'bulk_pack_301_500', label: '301–500', start: 301, count: 200),
      (keyId: 'bulk_pack_1_250', label: '1–250', start: 1, count: 250),
      (keyId: 'bulk_pack_251_500', label: '251–500', start: 251, count: 250),
      (keyId: 'bulk_pack_1_500', label: '1–500', start: 1, count: 500),
      (keyId: 'bulk_pack_501_1000', label: '501–1000', start: 501, count: 500),
      (keyId: 'bulk_pack_1_1000', label: '1–1000', start: 1, count: 1000),
      (keyId: 'bulk_pack_1001_2000', label: '1001–2000', start: 1001, count: 1000),
    ];

    Widget buildChip({
      required Key key,
      required String label,
      required bool selected,
      required VoidCallback onTap,
      IconData? icon,
    }) {
      return InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? AppTheme.brandPurple : Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: selected ? AppTheme.brandPurple : const Color(0xFFCBD5E1),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 12,
                  color: selected ? Colors.white : AppTheme.brandPurple,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.white : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildStartField() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Starting Number (सुरु नम्बर)',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('pre_numbered_start_input'),
            controller: _startTokenController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              hintText: '1',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              suffixIconConstraints: const BoxConstraints(minHeight: 30),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    key: const Key('start_token_dec_btn'),
                    onTap: startSeq > 1 ? () => _setStartToken(startSeq - 1) : null,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Icon(
                        Icons.remove_rounded,
                        size: 16,
                        color: startSeq > 1 ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      ),
                    ),
                  ),
                  InkWell(
                    key: const Key('start_token_inc_btn'),
                    onTap: () => _setStartToken(startSeq + 1),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4, right: 8, top: 4, bottom: 4),
                      child: Icon(Icons.add_rounded, size: 16, color: Color(0xFF334155)),
                    ),
                  ),
                ],
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Start:',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
              ),
              buildChip(
                key: const Key('start_chip_next_free'),
                label: 'Next (#$nextFreePad)',
                selected: startSeq == _nextAvailableToken,
                icon: Icons.auto_awesome_rounded,
                onTap: () => _setStartToken(_nextAvailableToken),
              ),
              for (final s in [1, 101, 201, 301, 501, 1001, 1501, 2001])
                buildChip(
                  key: Key('start_chip_$s'),
                  label: '$s',
                  selected: startSeq == s,
                  onTap: () => _setStartToken(s),
                ),
            ],
          ),
        ],
      );
    }

    Widget buildQuantityField() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quantity (फाराम संख्या)',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('pre_numbered_count_input'),
            controller: _tokenCountController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              hintText: '50',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              suffixIconConstraints: const BoxConstraints(minHeight: 30),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    key: const Key('token_count_dec_btn'),
                    onTap: count > 1 ? () => _setTokenCount((count - 25).clamp(1, maxPreNumberedBatchSize)) : null,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Icon(
                        Icons.remove_rounded,
                        size: 16,
                        color: count > 1 ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      ),
                    ),
                  ),
                  InkWell(
                    key: const Key('token_count_inc_btn'),
                    onTap: count < maxPreNumberedBatchSize
                        ? () => _setTokenCount((count + 25).clamp(1, maxPreNumberedBatchSize))
                        : null,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, right: 8, top: 4, bottom: 4),
                      child: Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: count < maxPreNumberedBatchSize ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (isTokenCountClamped) ...[
            const SizedBox(height: 4),
            const Text(
              'Max 5,000 forms per batch (clamped to 5,000 — use Next ▶ for 5,001+)',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFFB45309)),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Quick:',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
              ),
              for (final q in [10, 25, 50, 100, 200, 250, 500, 1000, 2000])
                buildChip(
                  key: Key('qty_chip_$q'),
                  label: '$q',
                  selected: count == q,
                  onTap: () => _setTokenCount(q),
                ),
            ],
          ),
        ],
      );
    }

    Widget buildBlockStepButtons() {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            key: const Key('token_range_prev_block_btn'),
            onPressed: canStepPrev ? () => _stepTokenBlock(-1) : null,
            icon: const Icon(Icons.chevron_left_rounded, size: 16),
            label: const Text('Prev', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.brandPurple,
              side: BorderSide(color: canStepPrev ? const Color(0xFFD8B4FE) : const Color(0xFFE2E8F0)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            key: const Key('token_range_next_block_btn'),
            onPressed: () => _stepTokenBlock(1),
            icon: const Icon(Icons.chevron_right_rounded, size: 16),
            label: const Text('Next', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.brandPurple,
              side: const BorderSide(color: Color(0xFFD8B4FE)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.pin_outlined, size: 16, color: AppTheme.brandPurple),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                '4. PRE-NUMBER PATIENT TOKEN IDs (टोकन नं. छापिएको फाराम)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: AppTheme.brandPurple,
                ),
              ),
            ),
            Switch.adaptive(
              key: const Key('enable_pre_numbered_tokens_switch'),
              value: _enablePreNumberedTokens,
              activeColor: AppTheme.brandPurple,
              onChanged: (val) => setState(() => _enablePreNumberedTokens = val),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _enablePreNumberedTokens
              ? 'Print sequentially numbered forms with pre-filled character boxes and QR codes in the header.'
              : 'Switch ON to print a batch of blank forms sequentially numbered (e.g. 00001 to 00050).',
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
        ),
        if (_enablePreNumberedTokens) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDDD6FE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1-Tap Bulk Range Packs (sets BOTH Starting Number & Quantity)
                const Text(
                  'Bulk Packs (सुरु र संख्या एकैपटक छान्नुहोस्):',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4C1D95)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final pack in bulkPacks)
                      buildChip(
                        key: Key(pack.keyId),
                        label: pack.label,
                        selected: startSeq == pack.start && count == pack.count,
                        icon: Icons.layers_outlined,
                        onTap: () => _applyBulkRange(start: pack.start, count: pack.count),
                      ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: Color(0xFFDDD6FE)),
                ),
                if (isNarrow) ...[
                  buildStartField(),
                  const SizedBox(height: 12),
                  buildQuantityField(),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: buildStartField()),
                      const SizedBox(width: 12),
                      Expanded(child: buildQuantityField()),
                    ],
                  ),
                const SizedBox(height: 12),
                // Range Summary Preview Banner + Prev/Next Block Stepper + Multi-Volume Split Option
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE9D5FF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.qr_code_2_rounded, size: 28, color: AppTheme.brandPurple),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$startId → $endId',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2E1065),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  effectiveSplitIntoVolumes
                                      ? '$count forms ($totalPages pages) • Split into $plannedVolumeCount PDFs (up to $defaultVolumeChunkSize forms/file)'
                                      : '$count forms ($totalPages pages) • Header boxes pre-printed with token & QR code',
                                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF6B21A8)),
                                ),
                              ],
                            ),
                          ),
                          if (!isNarrow) ...[
                            const SizedBox(width: 8),
                            buildBlockStepButtons(),
                          ],
                        ],
                      ),
                      if (isNarrow) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: buildBlockStepButtons(),
                        ),
                      ],
                      if (showSplitOption) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(height: 1, color: Color(0xFFF3E8FF)),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.library_books_outlined, size: 16, color: AppTheme.brandPurple),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Split into print-ready PDF volumes ($plannedVolumeCount files • $defaultVolumeChunkSize forms/PDF)',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF3B0764),
                                    ),
                                  ),
                                  const Text(
                                    'Prevents browser & printer spooler memory overload on large runs',
                                    style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              key: const Key('split_large_batch_volumes_switch'),
                              value: effectiveSplitIntoVolumes,
                              activeColor: AppTheme.brandPurple,
                              onChanged: (val) => setState(() => _userSplitVolumesOverride = val),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCampScopeSelector(
    List<CampModel> camps,
    CampModel? activeCamp,
    bool isNarrow, {
    required bool isPrivileged,
  }) {
    // 1. NON-PRIVILEGED (e.g. Data Taker) with NO assigned camps
    if (!isPrivileged && camps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFECACA), width: 1.2),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_person_rounded, color: Color(0xFFDC2626), size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No Health Camps Assigned',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF991B1B),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Your data taker account is not currently assigned to any active health camp. Please contact your health camp coordinator or administrator to assign you to a camp before downloading printable blank forms.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFFB91C1C),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 2. NON-PRIVILEGED (e.g. Data Taker) with EXACTLY ONE assigned camp
    if (!isPrivileged && camps.length == 1) {
      final assignedCamp = camps.first;
      final isActive = activeCamp?.id == assignedCamp.id;

      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Material(
          color: const Color(0xFFF0FDF4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF86EFAC), width: 1.3),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_rounded, size: 18, color: Color(0xFF16A34A)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'CAMP SCOPE / शिविर छनोट',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: Color(0xFF166534),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Assigned Camp Only',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF166534),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.location_on_rounded, color: Color(0xFF16A34A), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${assignedCamp.name} (${assignedCamp.campCode})',
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF14532D),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isActive)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'ACTIVE',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF166534),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (assignedCamp.venue.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Venue: ${assignedCamp.venue}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Forms are pre-configured with the doctors, nurses, and venue for your assigned camp.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF15803D)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 3. NON-PRIVILEGED (e.g. Data Taker) with MULTIPLE assigned camps
    if (!isPrivileged) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Material(
          color: const Color(0xFFF8FAFC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded, size: 18, color: AppTheme.brandPurple),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'CAMP SCOPE / शिविर छनोट',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: AppTheme.brandPurple,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDE9FE),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Assigned Camps Only',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.brandPurple,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<CampModel>(
                  value: camps.any((c) => c.id == _selectedCamp?.id)
                      ? camps.firstWhere((c) => c.id == _selectedCamp!.id)
                      : camps.first,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Select Assigned Camp (तोकिएको शिविर छान्नुहोस्)',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: camps.map((c) {
                    final isActive = activeCamp?.id == c.id;
                    return DropdownMenuItem(
                      value: c,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${c.name} (${c.campCode})',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isActive)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('ACTIVE', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF166534))),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (camp) {
                    if (camp != null) {
                      setState(() {
                        _resetCliniciansForCamp(camp);
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 4. PRIVILEGED USERS (SuperAdmin, Staff Coordinator, Data Analyst)
    final isUniversal = _selectedCamp == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Material(
        color: isUniversal ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isUniversal ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0),
            width: isUniversal ? 1.5 : 1.0,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isUniversal ? Icons.public_rounded : Icons.location_on_rounded,
                    size: 18,
                    color: isUniversal ? const Color(0xFF1D4ED8) : AppTheme.brandPurple,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'CAMP SCOPE / शिविर छनोट',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: isUniversal ? const Color(0xFF1D4ED8) : AppTheme.brandPurple,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: isUniversal ? const Color(0xFFDBEAFE) : const Color(0xFFEDE9FE),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isUniversal ? 'Universal Mode (सार्वभौमिक)' : 'Camp-Specific',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: isUniversal ? const Color(0xFF1E40AF) : AppTheme.brandPurple,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Option 1: Universal Form
              RadioListTile<String?>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFF2563EB),
                value: null,
                groupValue: _selectedCamp?.id,
                title: const Text(
                  'Universal Blank Form (सार्वभौमिक फाराम — No Camp Required)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                subtitle: const Text(
                  'Printable blank forms with fillable Camp, Venue, and Token boxes. Perfect for advance printing & any health camp station.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
                onChanged: (_) {
                  setState(() {
                    _resetCliniciansForCamp(null);
                  });
                },
              ),
              // Option 2: Camp-Specific Form (if camps exist)
              if (camps.isNotEmpty) ...[
                RadioListTile<String?>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppTheme.brandPurple,
                  value: _selectedCamp?.id ?? 'SPECIFIC_CAMP_PLACEHOLDER',
                  groupValue: _selectedCamp?.id,
                  title: const Text(
                    'Camp-Specific Form (तोकिएको स्वास्थ्य शिविर)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  subtitle: const Text(
                    'Pre-prints camp name, venue, clinician rosters, and allows sequential token numbering.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                  onChanged: (_) {
                    final targetCamp = widget.camp ?? activeCamp ?? camps.first;
                    setState(() {
                      _resetCliniciansForCamp(targetCamp);
                    });
                  },
                ),
                if (_selectedCamp != null)
                  Padding(
                    padding: EdgeInsets.only(left: isNarrow ? 12 : 32, top: 4, bottom: 4),
                    child: DropdownButtonFormField<CampModel>(
                      value: camps.any((c) => c.id == _selectedCamp!.id)
                          ? camps.firstWhere((c) => c.id == _selectedCamp!.id)
                          : camps.first,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Select Registered Camp (शिविर छान्नुहोस्)',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: camps.map((c) {
                        final isActive = activeCamp?.id == c.id;
                        return DropdownMenuItem(
                          value: c,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${c.name} (${c.campCode})',
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isActive)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('ACTIVE', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF166534))),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (camp) {
                        if (camp != null) {
                          setState(() {
                            _resetCliniciansForCamp(camp);
                          });
                        }
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
}
}
