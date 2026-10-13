// ignore_for_file: deprecated_member_use
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/organization_provider.dart';
import '../../core/services/file_download_helper.dart';
import '../../core/services/pdf_report_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/camp_model.dart';
import '../../models/patient_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
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
  PrintableFormType _selectedFormType = PrintableFormType.yellowRegistrationForm;
  BlankFormPage1Layout _page1Layout = BlankFormPage1Layout.grid;
  DoctorSelectionMode _doctorMode = DoctorSelectionMode.allDoctorsChecklist;
  DoctorProfile? _selectedDoctor;
  NurseSelectionMode _nurseMode = NurseSelectionMode.allNursesChecklist;
  NurseProfile? _selectedNurse;
  bool _includeBlankNurseLine = false; // used only when the camp has no nurses
  bool _isGenerating = false;

  // Pre-numbered Patient Token Range State
  bool _enablePreNumberedTokens = false;
  final TextEditingController _startTokenController = TextEditingController(text: '1');
  final TextEditingController _tokenCountController = TextEditingController(text: '50');

  int get safeStartToken {
    final val = int.tryParse(_startTokenController.text.trim());
    return (val != null && val > 0) ? val : 1;
  }

  int get safeTokenCount {
    final val = int.tryParse(_tokenCountController.text.trim());
    return (val != null && val > 0 && val <= 500) ? val : 50;
  }

  @override
  void initState() {
    super.initState();
    final doctors = widget.camp?.doctorProfiles ?? [];
    if (doctors.length > 1) {
      _doctorMode = DoctorSelectionMode.allDoctorsChecklist;
      _selectedDoctor = doctors.first;
    } else if (doctors.length == 1) {
      _doctorMode = DoctorSelectionMode.specificDoctor;
      _selectedDoctor = doctors.first;
    } else {
      _doctorMode = DoctorSelectionMode.blankDoctorField;
    }

    final nurses = widget.camp?.nurseProfiles ?? [];
    if (nurses.length > 1) {
      _nurseMode = NurseSelectionMode.allNursesChecklist;
      _selectedNurse = nurses.first;
    } else if (nurses.length == 1) {
      _nurseMode = NurseSelectionMode.specificNurse;
      _selectedNurse = nurses.first;
    } else {
      _nurseMode = NurseSelectionMode.blankNurseField;
    }
    _initStartingToken();
  }

  @override
  void dispose() {
    _startTokenController.dispose();
    _tokenCountController.dispose();
    super.dispose();
  }

  Future<void> _initStartingToken() async {
    if (widget.camp == null) return;
    try {
      final patients = await ref.read(patientRepositoryProvider).getPatientsByCamp(widget.camp!.id);
      int highestSeq = 0;
      for (final p in patients) {
        final pid = p.patientId.toUpperCase();
        final lastHyphen = pid.lastIndexOf('-');
        if (lastHyphen != -1 && lastHyphen < pid.length - 1) {
          final seqPart = pid.substring(lastHyphen + 1);
          final num = int.tryParse(seqPart);
          if (num != null && num > highestSeq) {
            highestSeq = num;
          }
        }
      }
      if (mounted) {
        setState(() {
          _startTokenController.text = '${highestSeq + 1}';
        });
      }
    } catch (_) {}
  }

  Future<void> _generateAndDownload() async {
    setState(() => _isGenerating = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final effectiveOrg = ref.read(effectiveOrganizationProvider);
      final orgName = (widget.camp?.organizationName.isNotEmpty == true &&
              !AppConstants.isLegacyDefaultOrganization(widget.camp!.organizationName))
          ? widget.camp!.organizationName
          : effectiveOrg;

      final repo = ref.read(lookupRepositoryProvider);
      final user = ref.read(authStateProvider).currentUser;
      final tenantId = user?.tenantId;
      final campId = widget.camp?.id;

      final diagnoses = await repo.getItemsByCategory('diagnosis', tenantId: tenantId, campId: campId, activeOnly: true);
      final medications = await repo.getItemsByCategory('medicine', tenantId: tenantId, campId: campId, activeOnly: true);
      final referralHospitals = await repo.getItemsByCategory('referral_hospital', tenantId: tenantId, campId: campId, activeOnly: true);
      final visitReasons = await repo.getItemsByCategory('visit_reason', tenantId: tenantId, campId: campId, activeOnly: true);
      final chiefComplaints = await repo.getItemsByCategory('chief_complaint', tenantId: tenantId, campId: campId, activeOnly: true);

      final pdfService = PdfReportService();
      final doctors = widget.camp?.doctorProfiles ?? [];
      final nurses = widget.camp?.nurseProfiles ?? [];
      final NurseProfile? nurseToUse =
          (nurses.isNotEmpty && _nurseMode == NurseSelectionMode.specificNurse)
              ? _selectedNurse
              : null;
      final bool blankNurse = nurses.isNotEmpty
          ? _nurseMode == NurseSelectionMode.blankNurseField
          : _includeBlankNurseLine;

      final DoctorProfile? docToUse =
          (doctors.isNotEmpty && _doctorMode == DoctorSelectionMode.specificDoctor)
              ? _selectedDoctor
              : null;
      final bool blankDoctor = doctors.isNotEmpty
          ? _doctorMode == DoctorSelectionMode.blankDoctorField
          : true;

      Uint8List pdfBytes;
      String filename;
      final campCode = widget.camp?.campCode ?? 'CAMP';

      if (_enablePreNumberedTokens && widget.camp != null) {
        final startSeq = safeStartToken;
        final count = safeTokenCount;
        final endSeq = startSeq + count - 1;
        final startPad = startSeq.toString().padLeft(5, '0');
        final endPad = endSeq.toString().padLeft(5, '0');

        if (_selectedFormType == PrintableFormType.yellowRegistrationForm) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Generating $count pre-numbered blank forms ($startPad to $endPad, ${count * 2} pages)...'),
              duration: const Duration(seconds: 3),
            ),
          );
          pdfBytes = await pdfService.generatePreNumberedBlankFormsPdf(
            camp: widget.camp!,
            startSequence: startSeq,
            count: count,
            doctor: docToUse,
            nurse: nurseToUse,
            blankNurseLines: blankNurse,
            blankDoctorLines: blankDoctor,
            page1Layout: _page1Layout,
            organizationName: orgName,
            diagnoses: diagnoses,
            medications: medications,
            referralHospitals: referralHospitals,
            visitReasons: visitReasons,
            chiefComplaints: chiefComplaints,
          );
          filename = 'Blank_YellowForms_${campCode}_${startPad}_to_$endPad.pdf';
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Generating $count pre-numbered follow-up sheets ($startPad to $endPad, $count pages)...'),
              duration: const Duration(seconds: 3),
            ),
          );
          pdfBytes = await pdfService.generatePreNumberedBlankFollowUpSlipsPdf(
            camp: widget.camp!,
            startSequence: startSeq,
            count: count,
            doctor: docToUse,
            blankDoctorLines: blankDoctor,
            nurse: nurseToUse,
            blankNurseLines: blankNurse,
            organizationName: orgName,
          );
          filename = 'Blank_FollowUpSlips_${campCode}_${startPad}_to_$endPad.pdf';
        }
      } else if (_selectedFormType == PrintableFormType.yellowRegistrationForm) {
        if (_doctorMode == DoctorSelectionMode.allDoctorsBatch && doctors.isNotEmpty) {
          // Batch download: generate combined multi-page PDF with 2 pages for each doctor
          messenger.showSnackBar(
            SnackBar(
              content: Text('Generating batch forms for ${doctors.length} doctors (${doctors.length * 2} pages)...'),
              duration: const Duration(seconds: 2),
            ),
          );
          pdfBytes = await pdfService.generateBatchBlankYellowFormsPdf(
            doctors: doctors,
            camp: widget.camp,
            nurse: nurseToUse,
            blankNurseLines: blankNurse,
            page1Layout: _page1Layout,
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
            camp: widget.camp,
            doctor: docToUse,
            blankDoctorLines: blankDoctor,
            page1Layout: _page1Layout,
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
            camp: widget.camp,
            doctor: docToUse,
            nurse: nurseToUse,
            blankNurseLines: blankNurse,
            blankDoctorLines: blankDoctor,
            page1Layout: _page1Layout,
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
        if (_doctorMode == DoctorSelectionMode.allDoctorsBatch && doctors.isNotEmpty) {
          // Batch download: generate combined multi-page PDF with 1 page for each doctor
          messenger.showSnackBar(
            SnackBar(
              content: Text('Generating batch follow-up sheets for ${doctors.length} doctors (${doctors.length} pages)...'),
              duration: const Duration(seconds: 2),
            ),
          );
          pdfBytes = await pdfService.generateBatchBlankFollowUpSlipsPdf(
            doctors: doctors,
            camp: widget.camp,
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
            camp: widget.camp,
            doctor: docToUse,
            blankDoctorLines: blankDoctor,
            organizationName: orgName,
          );
          filename = 'Blank_FollowUpSlips_${campCode}_AllNursesBatch.pdf';
        } else {
          pdfBytes = await pdfService.generateBlankFollowUpSlipPdf(
            camp: widget.camp,
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
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doctors = widget.camp?.doctorProfiles ?? [];
    final hasDoctors = doctors.isNotEmpty;
    final showDoctorSetting = widget.camp?.showDoctorOnForms ?? true;
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
                              widget.camp != null
                                  ? '${widget.camp!.name} (${widget.camp!.campCode})'
                                  : 'Outreach Camp Master Forms',
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

                        if (_selectedFormType == PrintableFormType.yellowRegistrationForm) ...[
                          const SizedBox(height: 14),
                          const Text(
                            'PAGE 1 DEMOGRAPHICS LAYOUT (पृष्ठ १ ढाँचा)',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: AppTheme.brandPurple,
                            ),
                          ),
                          const SizedBox(height: 8),
                          isNarrow
                              ? Column(
                                  children: [
                                    _buildLayoutOption(
                                      title: 'Two-Column Field Grid (विस्तृत ग्रिड)',
                                      subtitle: 'Side-by-side First/Surname, Age & Marital status, full-width Sections B & C',
                                      badge: 'Recommended',
                                      isSelected: _page1Layout == BlankFormPage1Layout.grid,
                                      onTap: () => setState(() => _page1Layout = BlankFormPage1Layout.grid),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildLayoutOption(
                                      title: 'Classic Single Column (एकल स्तम्भ)',
                                      subtitle: 'Vertical demographics column with separate right panel for visit reasons',
                                      badge: 'Classic',
                                      isSelected: _page1Layout == BlankFormPage1Layout.classic,
                                      onTap: () => setState(() => _page1Layout = BlankFormPage1Layout.classic),
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(
                                      child: _buildLayoutOption(
                                        title: 'Two-Column Field Grid (विस्तृत ग्रिड)',
                                        subtitle: 'Side-by-side First/Surname, Age & Marital status, full-width B & C',
                                        badge: 'Recommended',
                                        isSelected: _page1Layout == BlankFormPage1Layout.grid,
                                        onTap: () => setState(() => _page1Layout = BlankFormPage1Layout.grid),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _buildLayoutOption(
                                        title: 'Classic Single Column (एकल स्तम्भ)',
                                        subtitle: 'Vertical demographics column with separate right panel',
                                        badge: 'Classic',
                                        isSelected: _page1Layout == BlankFormPage1Layout.classic,
                                        onTap: () => setState(() => _page1Layout = BlankFormPage1Layout.classic),
                                      ),
                                    ),
                                  ],
                                ),
                        ],

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

                        if (!showDoctorSetting) ...[
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

                        const SizedBox(height: 22),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        const SizedBox(height: 18),
                        _buildNurseSection(isNarrow),
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
                  child: isNarrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isGenerating ? null : _generateAndDownload,
                              icon: _isGenerating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.download_rounded, size: 18),
                              label: Text(
                                _isGenerating
                                    ? 'Generating PDF...'
                                    : (_enablePreNumberedTokens
                                        ? 'Download $safeTokenCount Pre-Numbered Forms'
                                        : 'Download Printable PDF'),
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
                      : Row(
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
                            ElevatedButton.icon(
                              onPressed: _isGenerating ? null : _generateAndDownload,
                              icon: _isGenerating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.download_rounded, size: 18),
                              label: Text(
                                _isGenerating
                                    ? 'Generating PDF...'
                                    : (_enablePreNumberedTokens
                                        ? 'Download $safeTokenCount Pre-Numbered Forms'
                                        : 'Download Printable PDF'),
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
    final nurses = widget.camp?.nurseProfiles ?? [];
    final hasNurses = nurses.isNotEmpty;
    final showNurseSetting = widget.camp?.showNurseOnForms ?? true;

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
        if (!hasNurses) ...[
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

  Widget _buildLayoutOption({
    required String title,
    required String subtitle,
    required String badge,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF5F3FF) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.brandPurple : const Color(0xFFE2E8F0),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppTheme.brandPurple : const Color(0xFF1E293B),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.brandPurple.withValues(alpha: 0.12)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppTheme.brandPurple : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.25),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTokenRangeSection(bool isNarrow) {
    final campCode = widget.camp?.campCode ?? 'CAMP';
    final year = widget.camp?.startDate.year ?? DateTime.now().year;
    final startSeq = safeStartToken;
    final count = safeTokenCount;
    final endSeq = startSeq + count - 1;
    final startId = PatientModel.generatePatientId(campCode: campCode, sequenceNumber: startSeq, year: year);
    final endId = PatientModel.generatePatientId(campCode: campCode, sequenceNumber: endSeq, year: year);
    final totalPages = _selectedFormType == PrintableFormType.yellowRegistrationForm ? count * 2 : count;

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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Starting Number (सुरु नम्बर)',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                          ),
                          const SizedBox(height: 6),
                          TextField(
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
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Quantity (फाराम संख्या)',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                          ),
                          const SizedBox(height: 6),
                          TextField(
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
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Quick quantity chips
                Row(
                  children: [
                    const Text('Quick:', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    for (final q in [10, 25, 50, 100]) ...[
                      InkWell(
                        onTap: () {
                          _tokenCountController.text = '$q';
                          setState(() {});
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: safeTokenCount == q ? AppTheme.brandPurple : Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: safeTokenCount == q ? AppTheme.brandPurple : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Text(
                            '$q',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: safeTokenCount == q ? Colors.white : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // Range Summary Preview Banner
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE9D5FF)),
                  ),
                  child: Row(
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
                              '$count forms ($totalPages pages) • Header boxes pre-printed with token & QR code',
                              style: const TextStyle(fontSize: 10.5, color: Color(0xFF6B21A8)),
                            ),
                          ],
                        ),
                      ),
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
}

