import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/organization_provider.dart';
import '../../core/services/file_download_helper.dart';
import '../../core/services/pdf_report_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/camp_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/master_lookup_viewmodel.dart';

enum PrintableFormType {
  yellowRegistrationForm,
  followUpEncounterSlip,
}

enum DoctorSelectionMode {
  specificDoctor,
  allDoctorsBatch,
  blankDoctorField,
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
  DoctorSelectionMode _doctorMode = DoctorSelectionMode.specificDoctor;
  DoctorProfile? _selectedDoctor;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    final doctors = widget.camp?.doctorProfiles ?? [];
    if (doctors.isNotEmpty) {
      _selectedDoctor = doctors.first;
    } else {
      _doctorMode = DoctorSelectionMode.blankDoctorField;
    }
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

      Uint8List pdfBytes;
      String filename;
      final campCode = widget.camp?.campCode ?? 'CAMP';

      if (_selectedFormType == PrintableFormType.yellowRegistrationForm) {
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
            organizationName: orgName,
            diagnoses: diagnoses,
            medications: medications,
            referralHospitals: referralHospitals,
            visitReasons: visitReasons,
            chiefComplaints: chiefComplaints,
          );
          filename = 'Blank_YellowForms_${campCode}_AllDoctors.pdf';
        } else {
          final isBlank = _doctorMode == DoctorSelectionMode.blankDoctorField;
          final docToUse = _doctorMode == DoctorSelectionMode.specificDoctor ? _selectedDoctor : null;
          pdfBytes = await pdfService.generatePatientRegistrationFormPdf(
            camp: widget.camp,
            doctor: docToUse,
            blankDoctorLines: isBlank,
            organizationName: orgName,
            diagnoses: diagnoses,
            medications: medications,
            referralHospitals: referralHospitals,
            visitReasons: visitReasons,
            chiefComplaints: chiefComplaints,
          );
          final docSlug = docToUse != null ? '_${docToUse.name.replaceAll(' ', '_')}' : '_Blank';
          filename = 'Blank_YellowForm_${campCode}_$docSlug.pdf';
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
            organizationName: orgName,
          );
          filename = 'Blank_FollowUpSlips_${campCode}_AllDoctors.pdf';
        } else {
          final docToUse = _doctorMode == DoctorSelectionMode.specificDoctor ? _selectedDoctor : null;
          pdfBytes = await pdfService.generateBlankFollowUpSlipPdf(
            camp: widget.camp,
            doctor: docToUse,
            organizationName: orgName,
          );
          final docSlug = docToUse != null ? '_${docToUse.name.replaceAll(' ', '_')}' : '_Blank';
          filename = 'Blank_FollowUpSlip_${campCode}_$docSlug.pdf';
        }
      }

      await FileDownloadHelper.saveAndDownloadFile(
        bytes: pdfBytes,
        filename: filename,
        mimeType: 'application/pdf',
      );

      if (mounted) {
        Navigator.pop(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Downloaded successfully: $filename')),
              ],
            ),
            backgroundColor: AppTheme.successGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
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

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF0F766E),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.print_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Blank Forms & Clinical Sheets',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          widget.camp != null
                              ? '${widget.camp!.name} (${widget.camp!.campCode})'
                              : 'Outreach Camp Master Forms',
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
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
                padding: const EdgeInsets.all(20),
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
                        color: Color(0xFF0F766E),
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
                        color: Color(0xFF0F766E),
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
                      // ignore: deprecated_member_use
                      RadioListTile<DoctorSelectionMode>(
                        dense: true,
                        activeColor: const Color(0xFF0F766E),
                        contentPadding: EdgeInsets.zero,
                        value: DoctorSelectionMode.specificDoctor,
                        groupValue: _doctorMode,
                        title: const Text('Specific Doctor (तोकिएको चिकित्सक)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Pre-prints the selected doctor\'s name and NMC number on the form', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        onChanged: (val) => setState(() => _doctorMode = val!),
                      ),
                      if (_doctorMode == DoctorSelectionMode.specificDoctor) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 32, bottom: 8),
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
                                ),
                              );
                            }).toList(),
                            onChanged: (val) => setState(() => _selectedDoctor = val),
                          ),
                        ),
                      ],
                      if (doctors.length > 1) ...[
                        // ignore: deprecated_member_use
                        RadioListTile<DoctorSelectionMode>(
                          dense: true,
                          activeColor: const Color(0xFF0F766E),
                          contentPadding: EdgeInsets.zero,
                          value: DoctorSelectionMode.allDoctorsBatch,
                          groupValue: _doctorMode,
                          title: Text('All Assigned Doctors (${doctors.length} Doctors Batch)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: const Text('Generates separate doctor-wise copies for each doctor in the roster', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          onChanged: (val) => setState(() => _doctorMode = val!),
                        ),
                      ],
                      // ignore: deprecated_member_use
                      RadioListTile<DoctorSelectionMode>(
                        dense: true,
                        activeColor: const Color(0xFF0F766E),
                        contentPadding: EdgeInsets.zero,
                        value: DoctorSelectionMode.blankDoctorField,
                        groupValue: _doctorMode,
                        title: const Text('Blank Doctor Lines (हस्तलिखित / स्थानीय छाप)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Leaves doctor and NMC boxes blank with a signature line for manual signing on-site', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        onChanged: (val) => setState(() => _doctorMode = val!),
                      ),
                    ],


                  ],
                ),
              ),
            ),

            // Footer / Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
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
                      _isGenerating ? 'Generating PDF...' : 'Download Printable PDF',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
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
        ),
      ),
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
  }) {
    final isSelected = _selectedFormType == type;

    return InkWell(
      onTap: () => setState(() => _selectedFormType = type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
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
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 22),
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
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155),
                          ),
                        ),
                      ),
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
}
