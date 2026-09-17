import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/clinical_constants.dart';
import '../../core/constants/nepal_geodata.dart';
import '../../core/services/clinical_validation_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ocr_scan_result_model.dart';
import '../../models/patient_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../../viewmodels/ocr_scan_viewmodel.dart';
import '../../viewmodels/patient_list_viewmodel.dart';
import '../patient/patient_list_view.dart';

class FormScanView extends ConsumerStatefulWidget {
  const FormScanView({super.key});

  @override
  ConsumerState<FormScanView> createState() => _FormScanViewState();
}

class _FormScanViewState extends ConsumerState<FormScanView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // Tracks per-field verification: true=correct, false=incorrect, null=not yet reviewed
  final Map<String, bool?> _verifyMap = {};
  final TextEditingController _customDiagnosisController = TextEditingController();
  final TextEditingController _customMedicationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _customDiagnosisController.dispose();
    _customMedicationController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ocrState = ref.watch(ocrScanProvider);
    final ocrVm = ref.read(ocrScanProvider.notifier);
    final campState = ref.watch(campStateProvider);
    final authState = ref.watch(authStateProvider);
    final deviceState = ref.watch(deviceSecurityProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Scan & Auto-Fill (फाराम स्क्यान)', style: TextStyle(fontSize: 16)),
            Text('OCR & OMR Split-Screen Verification', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          // Clinical Reference Form Templates
          PopupMenuButton<String>(
            tooltip: 'Load Reference Form Template',
            icon: const Icon(Icons.document_scanner),
            onSelected: (sample) => ocrVm.loadSample(sample),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'full', child: Text('📄 Complete 2-Page Yellow Form')),
              const PopupMenuItem(value: 'page1', child: Text('📋 Page 1: Demographics & History')),
              const PopupMenuItem(value: 'page2', child: Text('🩺 Page 2: POP Exam & Vitals')),
            ],
          ),
          if (ocrState.hasScanResult)
            IconButton(
              tooltip: 'Clear & Retake',
              icon: const Icon(Icons.refresh),
              onPressed: () => ocrVm.resetScan(),
            ),
        ],
      ),
      body: ocrState.isProcessing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.primaryTeal),
                  SizedBox(height: 16),
                  Text(
                    'Scanning & Digitizing Yellow Form...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Extracting demographics, OMR checkboxes, vitals and diagnoses',
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryLight),
                  ),
                ],
              ),
            )
          : !ocrState.hasScanResult
              ? _buildCapturePrompt(context, ocrVm)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWideScreen = constraints.maxWidth >= 850;
                    if (isWideScreen) {
                      return Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: _buildDocumentPreviewPane(ocrState),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            flex: 6,
                            child: _buildDigitalVerificationPane(context, ref, ocrState, ocrVm, campState, authState, deviceState),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          Expanded(
                            child: _buildDigitalVerificationPane(context, ref, ocrState, ocrVm, campState, authState, deviceState),
                          ),
                        ],
                      );
                    }
                  },
                ),
    );
  }

  // ==========================================
  // INITIAL CAPTURE PROMPT (DUAL-PAGE SLOTS)
  // ==========================================
  Widget _buildCapturePrompt(BuildContext context, OcrScanViewModel ocrVm) {
    final ocrState = ref.watch(ocrScanProvider);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Header Badge: MoHP Nepal Standard
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.primaryTeal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user_outlined, color: AppTheme.primaryTeal, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'OFFLINE CLINICAL OPTICAL CHARACTER RECOGNITION (OCR)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: AppTheme.primaryTeal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Scan & Auto-Fill Yellow Form',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
              const SizedBox(height: 8),
              const Text(
                'Capture both Page 1 (Front: Demographics & Anamnesis) and Page 2 (Back: POP Staging & Treatment).\nThe clinical intake engine will parse and merge both sides into a unified electronic record.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: AppTheme.textSecondaryLight, height: 1.45),
              ),
              const SizedBox(height: 16),

              // Instruction Banner: Block Letters for Scan Accuracy
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF93C5FD), width: 1.2),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.edit_note_rounded, color: Color(0xFF1D4ED8), size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'CRITICAL INSTRUCTION: PLEASE ENSURE THE FORM IS FILLED IN BLOCK LETTERS (सफा ठूला अक्षरमा लेख्नुहोस्) FOR ACCURATE SCANNING.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E3A8A),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Dual-Slot Cards (Side-by-Side or Column)
              LayoutBuilder(
                builder: (context, box) {
                  final isWide = box.maxWidth >= 640;
                  final slot1 = _buildPageSlotCard(
                    pageNumber: 1,
                    title: 'Page 1 (Front Page)',
                    subtitle: 'Demographics, Obstetric History & Visit Reasons',
                    isCaptured: ocrState.hasPage1,
                    summaryText: ocrState.hasPage1
                        ? '${ocrState.page1Scan!.demographics["firstName"] ?? "Patient"} ${ocrState.page1Scan!.demographics["surname"] ?? ""} (${ocrState.page1Scan!.demographics["age"] ?? 35}y) • Ward ${ocrState.page1Scan!.demographics["ward"] ?? "03"}'
                        : null,
                    onCamera: () => ocrVm.capturePage(1),
                    onGallery: () => ocrVm.pickPage(1),
                    onClear: () => ocrVm.clearSlot(1),
                  );

                  final slot2 = _buildPageSlotCard(
                    pageNumber: 2,
                    title: 'Page 2 (Back Page)',
                    subtitle: 'POP Staging, Vitals, Diagnoses & Prescriptions',
                    isCaptured: ocrState.hasPage2,
                    summaryText: ocrState.hasPage2
                        ? 'POP Stage ${ocrState.page2Scan!.popStaging["highestPopStage"] ?? 3} • BP ${ocrState.page2Scan!.vitals["systolicBp"] ?? 120}/${ocrState.page2Scan!.vitals["diastolicBp"] ?? 80} • ${ocrState.page2Scan!.diagnoses.length} Diagnoses'
                        : null,
                    onCamera: () => ocrVm.capturePage(2),
                    onGallery: () => ocrVm.pickPage(2),
                    onClear: () => ocrVm.clearSlot(2),
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: slot1),
                        const SizedBox(width: 18),
                        Expanded(child: slot2),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        slot1,
                        const SizedBox(height: 16),
                        slot2,
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 22),

              // Primary Action: Review Captured Data
              if (ocrState.hasPage1 || ocrState.hasPage2) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.fact_check_outlined, size: 22),
                    label: Text(
                      ocrState.isDualReady
                          ? 'Review & Verify Complete Dual-Page Intake (दुवै पाना रुजु गर्नुहोस्)'
                          : (ocrState.hasPage1
                              ? 'Review Page 1 (Front) Only & Fill Page 2 Manually'
                              : 'Review Page 2 (Back) Only & Fill Page 1 Manually'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => ocrVm.mergeAndProceed(),
                  ),
                ),
                if (!ocrState.isDualReady) ...[
                  const SizedBox(height: 8),
                  Text(
                    ocrState.hasPage1
                        ? 'Tip: You can upload Page 2 into Slot 2 above for complete 2-page extraction.'
                        : 'Tip: You can upload Page 1 into Slot 1 above for complete 2-page extraction.',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight, fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 16),
              ],

              // Multi-Document Batch Import and Clinical Reference
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.document_scanner_outlined, size: 18),
                    label: const Text('Scan Both Pages (Edge Detect & OMR)', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => ocrVm.scanBothPagesWithDocumentScanner(),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.photo_library_outlined, size: 18, color: AppTheme.primaryTeal),
                    label: const Text('Select Both Images at Once (Multi-Select)', style: TextStyle(fontWeight: FontWeight.w600)),
                    onPressed: () => ocrVm.pickBothPages(),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      foregroundColor: Colors.indigo.shade800,
                    ),
                    icon: const Icon(Icons.assignment_outlined, size: 18),
                    label: const Text('Load Complete 2-Page Template', style: TextStyle(fontWeight: FontWeight.w600)),
                    onPressed: () => ocrVm.loadSample('full'),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Enterprise Clinical Guidance Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: AppTheme.primaryTeal),
                        SizedBox(width: 8),
                        Text('Clinical Quality Standards & Digitization Protocols', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryDark)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildGuidelineBullet(
                            icon: Icons.crop_free,
                            title: 'Boundary Alignment',
                            desc: 'Ensure all 4 corner registration marks are clearly inside the camera frame.',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildGuidelineBullet(
                            icon: Icons.wb_sunny_outlined,
                            title: 'Optimal Lighting',
                            desc: 'Avoid harsh shadows and direct flash glare over handwritten vitals.',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildGuidelineBullet(
                            icon: Icons.security,
                            title: 'Zero Cloud Leakage',
                            desc: 'All optical extraction runs locally offline on this secured field device.',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildGuidelineBullet(
                            icon: Icons.check_circle_outline,
                            title: 'Clinician Verification',
                            desc: 'All extracted values must be reviewed by the Data Taker prior to commit.',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuidelineBullet({required IconData icon, required String title, required String desc}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: Colors.blueGrey),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
              Text(desc, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPageSlotCard({
    required int pageNumber,
    required String title,
    required String subtitle,
    required bool isCaptured,
    String? summaryText,
    required VoidCallback onCamera,
    required VoidCallback onGallery,
    required VoidCallback onClear,
  }) {
    return Card(
      elevation: isCaptured ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isCaptured ? AppTheme.primaryTeal : Colors.grey.shade300,
          width: isCaptured ? 1.8 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Page Badge & Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: isCaptured ? AppTheme.primaryTeal : Colors.blueGrey.shade100,
                        child: Text(
                          '$pageNumber',
                          style: TextStyle(
                            color: isCaptured ? Colors.white : Colors.blueGrey.shade800,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (isCaptured)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.successGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 14, color: AppTheme.successGreen),
                        SizedBox(width: 4),
                        Text('Ready', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.successGreen)),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Slot Empty', style: TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight)),
            const SizedBox(height: 14),

            // If captured, show summary & clear button
            if (isCaptured && summaryText != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.assignment_turned_in_outlined, size: 18, color: AppTheme.primaryTeal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        summaryText,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.primaryDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: onClear,
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(4.0),
                        child: Icon(Icons.close, size: 16, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Camera is only available on Android / iOS and web.
            // On Windows, image_picker does not support ImageSource.camera.
            if (kIsWeb || !Platform.isWindows) ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.camera_alt, size: 16),
                      label: const Text('Scan Camera', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      onPressed: onCamera,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.file_upload_outlined, size: 16),
                      label: const Text('Upload File', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      onPressed: onGallery,
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Windows: upload only (camera not supported by image_picker on desktop)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.file_upload_outlined, size: 16),
                  label: const Text('Upload Image File', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  onPressed: onGallery,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 13, color: Colors.blueGrey),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Camera capture is only available on Android / iOS',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade500),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================
  // LEFT PANE: DUAL-DOCUMENT PREVIEW & INSPECTION
  // ==========================================
  Widget _buildDocumentPreviewPane(OcrScanState ocrState) {
    final result = ocrState.scanResult!;
    final activePage = ocrState.activeInspectionPage;
    final isDual = result.isDualPage || (ocrState.hasPage1 && ocrState.hasPage2);

    final rawTextToShow = isDual
        ? (activePage == 1 ? (result.page1RawText ?? result.rawText) : (result.page2RawText ?? result.rawText))
        : result.rawText;

    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.image_search, color: AppTheme.primaryDark, size: 20),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Document Scan Inspection',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  '${(result.overallConfidence * 100).toInt()}% Match',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                backgroundColor: AppTheme.successGreen.withValues(alpha: 0.15),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Page 1 / Page 2 Toggle Bar for Dual-Page Form
          if (isDual) ...[
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('📄 Page 1 (Front: Demographics)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    selected: activePage == 1,
                    selectedColor: AppTheme.primaryLight,
                    onSelected: (_) => ref.read(ocrScanProvider.notifier).switchInspectionPage(1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('🩺 Page 2 (Back: POP & Vitals)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    selected: activePage == 2,
                    selectedColor: AppTheme.primaryLight,
                    onSelected: (_) => ref.read(ocrScanProvider.notifier).switchInspectionPage(2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade300),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
                ],
              ),
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isDual
                            ? 'PAGE $activePage OCR STREAM & METRICS CROP'
                            : 'PAPER FORM OCR STREAM CROP',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      rawTextToShow,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // RIGHT PANE: DIGITAL HUMAN VERIFICATION FORM
  // ==========================================
  Widget _buildDigitalVerificationPane(
    BuildContext context,
    WidgetRef ref,
    OcrScanState ocrState,
    OcrScanViewModel ocrVm,
    CampState campState,
    AuthState authState,
    DeviceSecurityState deviceState,
  ) {
    final result = ocrState.scanResult!;

    return Column(
      children: [
        // Simulation Warning Banner — shown when ML Kit OCR was unavailable
        if (result.isSimulated)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            color: Colors.amber.shade100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SIMULATION MODE — OCR Engine Unavailable',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Real-time OCR is only available on Android / iOS devices. '
                        'Sample demo data is shown below. '
                        'You MUST edit ALL fields manually before committing this record.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade900,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Top Header Bar with Return to Slots Button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.primaryDark),
                tooltip: 'Return to Document Upload Slots',
                onPressed: () => ocrVm.returnToCaptureSlots(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ocrState.isDualReady || result.isDualPage
                          ? 'Dual-Page Verification (दुवै पाना रुजु गर्नुहोस्)'
                          : (ocrState.hasPage1 ? 'Page 1 Verification (Front Page)' : 'Page 2 Verification (Back Page)'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.primaryDark),
                    ),
                    Text(
                      'AI Digitization: ${(result.overallConfidence * 100).toInt()}% Confidence • Cross-check against form',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.file_upload_outlined, size: 14),
                label: const Text('Capture Slots', style: TextStyle(fontSize: 11)),
                onPressed: () => ocrVm.returnToCaptureSlots(),
              ),
            ],
          ),
        ),

        // Tabs for Stations
        TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryTeal,
          unselectedLabelColor: AppTheme.textSecondaryLight,
          indicatorColor: AppTheme.primaryTeal,
          isScrollable: true,
          tabs: const [
            Tab(text: '1. Demographics'),
            Tab(text: '2. Obstetric History'),
            Tab(text: '3. POP Staging'),
            Tab(text: '4. Vitals & Diagnoses'),
            Tab(text: '✅ Verify Accuracy'),
          ],
        ),

        // Tab Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDemographicsTab(result, ocrVm, ocrState, campState.activeCamp?.id),
              _buildObstetricsTab(result, ocrVm),
              _buildPopStagingTab(result, ocrVm),
              _buildVitalsAndDiagnosesTab(result, ocrVm),
              _buildVerifyAccuracyTab(result),
            ],
          ),
        ),

        // Bottom Commit Bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: ocrState.isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    ocrState.isSaving ? 'Committing Record...' : 'Verify & Commit to Camp Database (दर्ता सम्पन्न गर्नुहोस्)',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  onPressed: ocrState.isSaving
                      ? null
                      : () async {
                          final activeCamp = campState.activeCamp;
                          if (activeCamp == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please open or select an active camp first!')),
                            );
                            return;
                          }

                          if (ocrState.duplicateResult.hasDuplicate) {
                            final proceed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
                                    SizedBox(width: 10),
                                    Text('Duplicate Warning', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  ],
                                ),
                                content: Text(
                                  'A patient with matching credentials already exists in this camp (ID: ${ocrState.duplicateResult.matchedPatient?.patientId} - ${ocrState.duplicateResult.matchedPatient?.fullName}).\n\nAre you sure you want to register a new entry for this paper form?',
                                  style: const TextStyle(fontSize: 13.5),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel & Review'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.amber.shade800,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Proceed & Register'),
                                  ),
                                ],
                              ),
                            );
                            if (proceed != true) return;
                          }

                          final savedPatient = await ocrVm.confirmAndCommit(
                            campId: activeCamp.id,
                            campCode: activeCamp.campCode,
                            userId: authState.currentUser?.id ?? 'usr-local',
                            userName: authState.currentUser?.name ?? 'Field Staff',
                            deviceId: deviceState.device?.deviceId ?? 'dev-local',
                          );

                          if (savedPatient != null && context.mounted) {
                            ref.read(campStateProvider.notifier).loadCamps();
                            ref.read(patientListProvider.notifier).loadPatients(activeCamp.id);
                            _showSuccessDialog(context, savedPatient);
                          } else if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ocrState.errorMessage ?? 'Failed to commit scanned form. Please verify required fields.'),
                                backgroundColor: Colors.red[700],
                              ),
                            );
                          }
                        },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Tab 1: Demographics
  Widget _buildDemographicsTab(OcrScanResultModel result, OcrScanViewModel vm, OcrScanState ocrState, String? campId) {
    final demo = result.demographics;

    final selectedProvince = demo['province']?.toString().isNotEmpty == true
        ? demo['province'].toString()
        : 'Bagmati';
    final validProvince = ClinicalConstants.nepalProvinces.contains(selectedProvince)
        ? selectedProvince
        : 'Bagmati';
    final districtList = NepalGeodata.districtsFor(validProvince);
    final selectedDistrict = demo['district']?.toString();
    final validDistrict = (selectedDistrict != null && districtList.contains(selectedDistrict))
        ? selectedDistrict
        : (districtList.isNotEmpty ? districtList.first : null);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live Duplicate Detection Warning Card
          if (ocrState.duplicateResult.hasDuplicate) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DUPLICATE REGISTRY DETECTED (दोहोरिएको बिरामी रेकर्ड)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF991B1B)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ocrState.duplicateResult.matchReasonEn ?? 'A patient with matching credentials already exists in this camp.',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF7F1D1D)),
                        ),
                        if (ocrState.duplicateResult.matchReasonNe != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            ocrState.duplicateResult.matchReasonNe!,
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF991B1B)),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Text(
                            'Existing Record: ${ocrState.duplicateResult.matchedPatient?.fullName} • ID: ${ocrState.duplicateResult.matchedPatient?.patientId} (Ward ${ocrState.duplicateResult.matchedPatient?.ward})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF991B1B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (!result.isDualPage && (demo.isEmpty || demo['firstName'] == null)) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Page 1 (Front: Demographics) was not photographed. Please enter patient information manually or tap "Capture Slots" above to upload Page 1.',
                      style: TextStyle(fontSize: 12, color: Colors.deepOrange),
                    ),
                  ),
                ],
              ),
            ),
          ],

          _buildFieldWithConfidence(
            label: 'First Name (नाम)',
            value: demo['firstName']?.toString() ?? '',
            fieldKey: 'name',
            result: result,
            onChanged: (val) => vm.updateDemographic('firstName', val, campId: campId),
          ),
          const SizedBox(height: 12),
          _buildFieldWithConfidence(
            label: 'Surname (थर)',
            value: demo['surname']?.toString() ?? '',
            fieldKey: 'name',
            result: result,
            onChanged: (val) => vm.updateDemographic('surname', val, campId: campId),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildFieldWithConfidence(
                  label: 'Age (उमेर)',
                  value: demo['age']?.toString() ?? '35',
                  fieldKey: 'age',
                  result: result,
                  keyboardType: TextInputType.number,
                  onChanged: (val) => vm.updateDemographic('age', int.tryParse(val) ?? 35, campId: campId),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('scan_marital_${demo['maritalStatus']}'),
                  initialValue: const ['married', 'unmarried', 'widow', 'divorced'].contains(demo['maritalStatus']?.toString().toLowerCase())
                      ? demo['maritalStatus']?.toString().toLowerCase()
                      : 'married',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Marital Status (वैवाहिक स्थिति)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'married', child: Text('Married (विवाहित)', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'unmarried', child: Text('Unmarried (अविवाहित)', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'widow', child: Text('Widow (एकल/विधवा)', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'divorced', child: Text('Divorced (सम्बन्धविच्छेद)', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (status) {
                    if (status != null) {
                      vm.updateDemographic('maritalStatus', status, campId: campId);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Administrative Location: Province & Cascading District
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('scan_prov_$validProvince'),
                  initialValue: validProvince,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Province (प्रदेश)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  items: ClinicalConstants.nepalProvinces.map((prov) {
                    return DropdownMenuItem(
                      value: prov,
                      child: Text(prov, style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (newProv) {
                    if (newProv != null) {
                      vm.updateDemographic('province', newProv, campId: campId);
                      final newDistricts = NepalGeodata.districtsFor(newProv);
                      final newDist = !newDistricts.contains(demo['district'])
                          ? (newDistricts.isNotEmpty ? newDistricts.first : '')
                          : demo['district'];
                      vm.updateDemographic('district', newDist, campId: campId);
                      final newPalikas = NepalGeodata.palikasFor(newDist);
                      if (!newPalikas.contains(demo['municipality'])) {
                        vm.updateDemographic('municipality', newPalikas.isNotEmpty ? newPalikas.first : '', campId: campId);
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('scan_dist_${validProvince}_$validDistrict'),
                  initialValue: validDistrict,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'District (जिल्ला)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  items: districtList.map((dist) {
                    return DropdownMenuItem(
                      value: dist,
                      child: Text(dist, style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (newDist) {
                    if (newDist != null) {
                      vm.updateDemographic('district', newDist, campId: campId);
                      final newPalikas = NepalGeodata.palikasFor(newDist);
                      if (!newPalikas.contains(demo['municipality'])) {
                        vm.updateDemographic('municipality', newPalikas.isNotEmpty ? newPalikas.first : '', campId: campId);
                      }
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Builder(
                  builder: (context) {
                    final palikas = NepalGeodata.palikasFor(
                      validDistrict,
                      extraPalikas: demo['municipality'] != null && demo['municipality'].toString().isNotEmpty
                          ? [demo['municipality'].toString()]
                          : null,
                    );
                    final currentPalika = palikas.firstWhere(
                      (p) => p.toLowerCase() == demo['municipality']?.toString().toLowerCase(),
                      orElse: () => palikas.isNotEmpty ? palikas.first : '',
                    );
                    return DropdownButtonFormField<String>(
                      key: ValueKey('scan_palika_${validDistrict}_${demo['municipality']}'),
                      initialValue: currentPalika.isNotEmpty ? currentPalika : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Palika / Municipality * (पालिका)',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                      items: palikas.map((p) {
                        return DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13)));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          vm.updateDemographic('municipality', val, campId: campId);
                        }
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFieldWithConfidence(
                  label: 'Ward Number (वडा नं)',
                  value: demo['ward']?.toString() ?? '03',
                  fieldKey: 'ward',
                  result: result,
                  onChanged: (val) => vm.updateDemographic('ward', val, campId: campId),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildFieldWithConfidence(
            label: 'Mobile Phone (मोबाइल नम्बर)',
            value: demo['mobile']?.toString() ?? '',
            fieldKey: 'mobile',
            result: result,
            keyboardType: TextInputType.phone,
            onChanged: (val) => vm.updateDemographic('mobile', val, campId: campId),
          ),
          const SizedBox(height: 12),
          _buildFieldWithConfidence(
            label: 'Husband / Father Name (श्रीमानको / बुबाको नाम)',
            value: demo['relativeName']?.toString() ?? '',
            fieldKey: 'relative',
            result: result,
            onChanged: (val) => vm.updateDemographic('relativeName', val, campId: campId),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildFieldWithConfidence(
                  label: 'Contact Person / सम्पर्क व्यक्ति',
                  value: demo['contactPerson']?.toString() ?? '',
                  fieldKey: 'contactPerson',
                  result: result,
                  onChanged: (val) => vm.updateDemographic('contactPerson', val),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFieldWithConfidence(
                  label: 'Contact Mobile / सम्पर्क नम्बर',
                  value: demo['contactMobile']?.toString() ?? '',
                  fieldKey: 'contactMobile',
                  result: result,
                  keyboardType: TextInputType.phone,
                  onChanged: (val) => vm.updateDemographic('contactMobile', val),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFieldWithConfidence(
                  label: 'Marriage Age / विवाह उमेर',
                  value: demo['maritalAge']?.toString() ?? '',
                  fieldKey: 'maritalAge',
                  result: result,
                  keyboardType: TextInputType.number,
                  onChanged: (val) => vm.updateDemographic('maritalAge', int.tryParse(val)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Primary Reasons for Visit (शिविरमा आउनुको कारण):',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final currentReasons = List<String>.from(demo['reasonsForVisit'] as List? ?? []);
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ClinicalConstants.visitReasonOptions.entries.map((entry) {
                  final key = entry.key;
                  final label = entry.value;
                  final isSelected = currentReasons.contains(key);
                  return FilterChip(
                    label: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? AppTheme.primaryTeal : Colors.black87,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: AppTheme.primaryLight,
                    checkmarkColor: AppTheme.primaryTeal,
                    onSelected: (selected) {
                      final updated = List<String>.from(currentReasons);
                      if (selected) {
                        if (!updated.contains(key)) updated.add(key);
                      } else {
                        updated.remove(key);
                      }
                      vm.updateDemographic('reasonsForVisit', updated, campId: campId);
                    },
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 16),
          const Divider(height: 24),
          const Text(
            'Informed Consent & Authorizations (सहमति विवरण):',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.grey.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                CheckboxListTile(
                  value: demo['consentTreatment'] as bool? ?? true,
                  title: const Text('Consent for Examination & Treatment', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: const Text('परीक्षण तथा आवश्यक उपचारको लागि स्वीकृति', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  activeColor: AppTheme.primaryTeal,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  onChanged: (val) {
                    vm.updateDemographic('consentTreatment', val ?? false, campId: campId);
                  },
                ),
                const Divider(height: 1),
                CheckboxListTile(
                  value: demo['consentStoreMedicalInfo'] as bool? ?? true,
                  title: const Text('Consent to Store Medical Information', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: const Text('स्वास्थ्य विवरण भण्डारण तथा अनुसन्धान सहमति', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  activeColor: AppTheme.primaryTeal,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  onChanged: (val) {
                    vm.updateDemographic('consentStoreMedicalInfo', val ?? false, campId: campId);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  // Tab 2: Obstetrics
  Widget _buildObstetricsTab(OcrScanResultModel result, OcrScanViewModel vm) {
    final obs = result.obstetrics;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.child_friendly, color: AppTheme.primaryTeal, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Obstetric History & Parity (प्रसूति इतिहास) — Cross-check with Yellow Form Box 2',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryDark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                children: [
                  _buildStepperCardRow(
                    label: 'Deliveries / Parity (सुत्केरी संख्या)',
                    description: 'Total live or stillborn deliveries',
                    value: obs['deliveries'] as int? ?? 3,
                    onChanged: (v) {
                      obs['deliveries'] = v;
                      vm.updateObstetric('deliveries', v);
                    },
                  ),
                  const Divider(height: 24),
                  _buildStepperCardRow(
                    label: 'Living Children (जीवित बालबच्चा)',
                    description: 'Number of living children at present',
                    value: obs['livingChildren'] as int? ?? 3,
                    onChanged: (v) {
                      obs['livingChildren'] = v;
                      vm.updateObstetric('livingChildren', v);
                    },
                  ),
                  const Divider(height: 24),
                  _buildStepperCardRow(
                    label: 'Abortions / Miscarriages (गर्भपतन)',
                    description: 'Spontaneous miscarriages or terminations',
                    value: obs['abortions'] as int? ?? 0,
                    onChanged: (v) {
                      obs['abortions'] = v;
                      vm.updateObstetric('abortions', v);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Station 1: Complaints Duration
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.schedule, color: AppTheme.primaryTeal, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Complaints Duration (समस्या सुरु भएको अवधि)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Cross-check with Yellow Form Station 1 duration checkboxes:',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      {'label': '< 3 months (< ३ महिना)', 'val': '< 3 months'},
                      {'label': '3-12 months (३-१२ महिना)', 'val': '3-12 months'},
                      {'label': '> 1 year (> १ वर्ष)', 'val': '> 1 year'},
                    ].map((item) {
                      final isSelected = (obs['complaintsDuration'] as String?) == item['val'];
                      return ChoiceChip(
                        label: Text(item['label']!),
                        selected: isSelected,
                        selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: isSelected ? AppTheme.primaryTeal : const Color(0xFF334155),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onSelected: (sel) {
                          vm.updateObstetric('complaintsDuration', sel ? item['val'] : null);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Station 1: 9 Chief Clinical Complaints Checkboxes
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.checklist_rounded, color: AppTheme.primaryTeal, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Chief Clinical Complaints (प्रमुख क्लिनिकल लक्षणहरू)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${((obs['clinicalComplaints'] as List?) ?? []).length} detected',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Select all presenting complaints matching physical Yellow Form Page 2 checkboxes:',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      {'key': 'Lower Abdominal Pain', 'label': 'Lower Abdominal Pain (तल्लो पेट दुख्ने)'},
                      {'key': 'White / Foul Discharge', 'label': 'White / Foul Discharge (सेतो / गन्हाउने पानी)'},
                      {'key': 'Pelvic Heaviness', 'label': 'Pelvic Heaviness (तल्लो पेट भारी हुने)'},
                      {'key': 'Burning Micturition', 'label': 'Burning Micturition (पिसाब पोल्ने)'},
                      {'key': 'Urinary Incontinence', 'label': 'Urinary Incontinence (पिसाब चुहिने)'},
                      {'key': 'Dyspareunia', 'label': 'Dyspareunia (सम्पर्कमा दुखाई)'},
                      {'key': 'Coital Bleeding', 'label': 'Coital Bleeding (सम्पर्कपछि रक्तस्राव)'},
                      {'key': 'Mass Per Vagina', 'label': 'Mass Per Vagina (केही बाहिर निस्कने)'},
                      {'key': 'Severe Backache', 'label': 'Severe Backache (अत्यधिक ढाड दुख्ने)'},
                    ].map((comp) {
                      final selectedComplaints = (obs['clinicalComplaints'] as List?)?.cast<String>() ?? [];
                      final isSelected = selectedComplaints.contains(comp['key']);
                      return FilterChip(
                        label: Text(comp['label']!),
                        selected: isSelected,
                        selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                        checkmarkColor: AppTheme.primaryTeal,
                        labelStyle: TextStyle(
                          color: isSelected ? AppTheme.primaryTeal : const Color(0xFF334155),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 11.5,
                        ),
                        onSelected: (_) {
                          vm.toggleClinicalComplaint(comp['key']!);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Tab 3: POP Staging
  Widget _buildPopStagingTab(OcrScanResultModel result, OcrScanViewModel vm) {
    final pop = result.popStaging;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!result.isDualPage && pop.isEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Page 2 (Back: POP Exam & Vitals) was not photographed. Values below are unset. You can edit them manually or tap "Capture Slots" above to upload Page 2.',
                      style: TextStyle(fontSize: 12, color: Colors.deepOrange),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Highest POP Stage Hero Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (pop['highestPopStage'] as int? ?? 0) >= 2
                  ? AppTheme.warningAmber.withValues(alpha: 0.15)
                  : AppTheme.successGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (pop['highestPopStage'] as int? ?? 0) >= 2
                    ? AppTheme.warningAmber
                    : AppTheme.successGreen,
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('HIGHEST POP STAGE (अन्तिम आङ खसेको तह):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'Stage ${pop['highestPopStage'] ?? 0}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                    ),
                  ],
                ),
                Chip(
                  label: Text(
                    (pop['highestPopStage'] as int? ?? 0) >= 2 ? 'Significant Prolapse' : 'Mild / Normal',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  backgroundColor: Colors.white,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Compartments
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildStageDropdown(
                    label: 'Anterior Compartment (Cystocele)',
                    value: pop['anteriorStage'] as int? ?? 2,
                    maxStage: 4,
                    onChanged: (v) => vm.updatePopStage('anteriorStage', v),
                  ),
                  const Divider(height: 24),
                  _buildStageDropdown(
                    label: 'Middle Compartment (Uterocervical)',
                    value: pop['middleStage'] as int? ?? 3,
                    maxStage: 4,
                    onChanged: (v) => vm.updatePopStage('middleStage', v),
                  ),
                  const Divider(height: 24),
                  _buildStageDropdown(
                    label: 'Posterior Compartment (Rectocele)',
                    value: pop['posteriorStage'] as int? ?? 1,
                    maxStage: 4,
                    onChanged: (v) => vm.updatePopStage('posteriorStage', v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Station 2: Pelvic Floor Tone & Uterus Inside
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Uterus Position & Pelvic Tone (पाठेघरको अवस्था तथा मांसपेशी तनाव):',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      const Text('Uterus Inside:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ChoiceChip(
                        label: const Text('Yes (भित्रै छ)'),
                        selected: pop['uterusInside'] == true,
                        selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                        onSelected: (sel) => vm.updatePopStage('uterusInside', true),
                      ),
                      ChoiceChip(
                        label: const Text('No / Prolapsed (बाहिर खसेको)'),
                        selected: pop['uterusInside'] == false,
                        selectedColor: Colors.orange.shade100,
                        onSelected: (sel) => vm.updatePopStage('uterusInside', false),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  const Text('Pelvic Floor Tone (पेल्भिक मांसपेशीको तनाव):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      {'val': 'normal', 'label': 'Normal (सामान्य)'},
                      {'val': 'weak', 'label': 'Weak (कमजोर)'},
                      {'val': 'hypertonic', 'label': 'Hypertonic (कडा / तनावग्रस्त)'},
                    ].map((t) {
                      final isSelected = (pop['pelvicFloorTone'] as String?)?.toLowerCase() == t['val'];
                      return ChoiceChip(
                        label: Text(t['label']!),
                        selected: isSelected,
                        selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: isSelected ? AppTheme.primaryTeal : const Color(0xFF334155),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onSelected: (_) => vm.updatePopStage('pelvicFloorTone', t['val']),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Station 2: Cervix Appearance & Vagina / Vulva
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cervix Appearance (पाठेघरको मुखको अवस्था):',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      'Normal / Smooth', 'Erosion', 'Hypertrophy', 'Polyp', 'Bleeding on Touch', 'Leukoplakia'
                    ].map((chip) {
                      final current = (pop['cervixRemarks'] as String? ?? '').toLowerCase();
                      final isSelected = current.contains(chip.toLowerCase());
                      return ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(chip, style: const TextStyle(fontSize: 11)),
                        selected: isSelected,
                        selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                        onSelected: (sel) {
                          vm.updatePopStage('cervixRemarks', sel ? chip : '');
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: pop['cervixRemarks'] as String? ?? '',
                    decoration: const InputDecoration(
                      hintText: 'Cervix clinical remarks or notes',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => vm.updatePopStage('cervixRemarks', val),
                  ),
                  const Divider(height: 28),
                  const Text(
                    'Vagina / Vulva (योनी तथा बाह्य अङ्गको अवस्था):',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      'Normal', 'Atrophic', 'Mild discharge', 'Condyloma', 'Ulcer', 'Lichen Sclerosus'
                    ].map((chip) {
                      final current = (pop['vaginaRemarks'] as String? ?? '').toLowerCase();
                      final isSelected = current.contains(chip.toLowerCase());
                      return ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(chip, style: const TextStyle(fontSize: 11)),
                        selected: isSelected,
                        selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                        onSelected: (sel) {
                          vm.updatePopStage('vaginaRemarks', sel ? chip : '');
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: pop['vaginaRemarks'] as String? ?? '',
                    decoration: const InputDecoration(
                      hintText: 'Vagina / Vulva clinical remarks or notes',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => vm.updatePopStage('vaginaRemarks', val),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Tab 4: Vitals & Diagnoses
  Widget _buildVitalsAndDiagnosesTab(OcrScanResultModel result, OcrScanViewModel vm) {
    final vitals = result.vitals;

    final sys = vitals['systolicBp'] as int? ?? 120;
    final dia = vitals['diastolicBp'] as int? ?? 80;
    final pulse = vitals['pulseRate'] as int? ?? 78;
    final spo2 = vitals['spo2'] as int? ?? 98;
    final glucose = vitals['bloodGlucose'] as int? ?? 110;

    final bpStatus = ClinicalValidationService.validateSystolicBp(sys);
    final bpDiaStatus = ClinicalValidationService.validateDiastolicBp(dia, systolic: sys);
    final ValidationSeverity bpSeverity = (bpStatus.isError || bpDiaStatus.isError)
        ? ValidationSeverity.error
        : (bpStatus.isWarning || bpDiaStatus.isWarning)
            ? ValidationSeverity.warning
            : ValidationSeverity.normal;

    final pulseStatus = ClinicalValidationService.validatePulse(pulse);
    final spo2Status = ClinicalValidationService.validateSpO2(spo2);
    final glucoseStatus = ClinicalValidationService.validateGlucose(glucose);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!result.isDualPage && vitals.isEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Page 2 (Back: Vitals & Prescriptions) was not photographed. Values below are unconfirmed. You can edit them manually or tap "Capture Slots" above to upload Page 2.',
                      style: TextStyle(fontSize: 12, color: Colors.deepOrange),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Text('Point-of-Care Vitals (भाइटल परीक्षण):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          const Text(
            'Directly edit detected vitals. Live clinical warnings and validation will update automatically.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
          ),
          const SizedBox(height: 12),

          // ── 1. BLOOD PRESSURE CARD (TWIN FIELDS) ────────────────
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: bpSeverity == ValidationSeverity.normal
                    ? AppTheme.successGreen.withValues(alpha: 0.3)
                    : bpSeverity == ValidationSeverity.warning
                        ? AppTheme.warningAmber
                        : AppTheme.dangerRose,
                width: bpSeverity == ValidationSeverity.normal ? 1 : 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.favorite, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Blood Pressure (रक्तचाप)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.primaryDark),
                        ),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: bpSeverity == ValidationSeverity.normal
                            ? AppTheme.successGreen.withValues(alpha: 0.15)
                            : bpSeverity == ValidationSeverity.warning
                                ? AppTheme.warningAmber.withValues(alpha: 0.2)
                                : AppTheme.dangerRose.withValues(alpha: 0.2),
                        label: Text(
                          bpSeverity == ValidationSeverity.normal
                              ? 'Normal ($sys/$dia)'
                              : bpSeverity == ValidationSeverity.warning
                                  ? 'Warning ($sys/$dia)'
                                  : 'Alert ($sys/$dia)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: bpSeverity == ValidationSeverity.normal
                                ? AppTheme.successGreen
                                : bpSeverity == ValidationSeverity.warning
                                    ? Colors.amber.shade900
                                    : AppTheme.dangerRose,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Standard unit: mmHg. Cross-check against Yellow Form Box 4.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('vital_sys_${result.scannedAt.millisecondsSinceEpoch}'),
                          initialValue: '$sys',
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Systolic (सिस्टोलिक)',
                            suffixText: 'mmHg',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixIcon: Icon(Icons.arrow_upward, size: 16, color: Colors.blueGrey),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          onChanged: (val) {
                            final parsed = int.tryParse(val.trim());
                            if (parsed != null) {
                              vm.updateVital('systolicBp', parsed);
                            }
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('/', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('vital_dia_${result.scannedAt.millisecondsSinceEpoch}'),
                          initialValue: '$dia',
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Diastolic (डायस्टोलिक)',
                            suffixText: 'mmHg',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixIcon: Icon(Icons.arrow_downward, size: 16, color: Colors.blueGrey),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          onChanged: (val) {
                            final parsed = int.tryParse(val.trim());
                            if (parsed != null) {
                              vm.updateVital('diastolicBp', parsed);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (bpStatus.messageEn != null || bpDiaStatus.messageEn != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (bpStatus.isError || bpDiaStatus.isError)
                            ? Colors.red.shade50
                            : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: (bpStatus.isError || bpDiaStatus.isError)
                                ? Colors.red.shade700
                                : Colors.amber.shade800,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              bpStatus.messageEn ?? bpDiaStatus.messageEn ?? '',
                              style: TextStyle(
                                fontSize: 11,
                                color: (bpStatus.isError || bpDiaStatus.isError)
                                    ? Colors.red.shade900
                                    : Colors.amber.shade900,
                              ),
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
          const SizedBox(height: 12),

          // ── 2. PULSE RATE & SPO2 SATURATION (ROW) ─────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pulse Card
              Expanded(
                child: Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: pulseStatus.severity == ValidationSeverity.normal
                          ? AppTheme.successGreen.withValues(alpha: 0.3)
                          : pulseStatus.severity == ValidationSeverity.warning
                              ? AppTheme.warningAmber
                              : AppTheme.dangerRose,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.monitor_heart, color: Colors.pinkAccent, size: 18),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'Pulse Rate',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: pulseStatus.severity == ValidationSeverity.normal
                                    ? AppTheme.successGreen.withValues(alpha: 0.15)
                                    : Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                pulseStatus.severity == ValidationSeverity.normal ? 'Normal' : 'Alert',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: pulseStatus.severity == ValidationSeverity.normal
                                      ? AppTheme.successGreen
                                      : Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: ValueKey('vital_pulse_${result.scannedAt.millisecondsSinceEpoch}'),
                          initialValue: '$pulse',
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'नाडी (bpm)',
                            suffixText: 'bpm',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          onChanged: (val) {
                            final parsed = int.tryParse(val.trim());
                            if (parsed != null) {
                              vm.updateVital('pulseRate', parsed);
                            }
                          },
                        ),
                        if (pulseStatus.messageEn != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            pulseStatus.messageEn!,
                            style: TextStyle(fontSize: 10, color: Colors.amber.shade900),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // SpO2 Card
              Expanded(
                child: Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: spo2Status.severity == ValidationSeverity.normal
                          ? AppTheme.successGreen.withValues(alpha: 0.3)
                          : spo2Status.severity == ValidationSeverity.warning
                              ? AppTheme.warningAmber
                              : AppTheme.dangerRose,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.air, color: Colors.blueAccent, size: 18),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'SpO2 Saturation',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: spo2Status.severity == ValidationSeverity.normal
                                    ? AppTheme.successGreen.withValues(alpha: 0.15)
                                    : Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                spo2Status.severity == ValidationSeverity.normal ? 'Normal' : 'Hypoxia',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: spo2Status.severity == ValidationSeverity.normal
                                      ? AppTheme.successGreen
                                      : Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: ValueKey('vital_spo2_${result.scannedAt.millisecondsSinceEpoch}'),
                          initialValue: '$spo2',
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'अक्सिजन (%)',
                            suffixText: '%',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          onChanged: (val) {
                            final parsed = int.tryParse(val.trim());
                            if (parsed != null) {
                              vm.updateVital('spo2', parsed);
                            }
                          },
                        ),
                        if (spo2Status.messageEn != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            spo2Status.messageEn!,
                            style: TextStyle(fontSize: 10, color: Colors.amber.shade900),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── 3. BLOOD GLUCOSE CARD ─────────────────────────────────
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: glucoseStatus.severity == ValidationSeverity.normal
                    ? AppTheme.successGreen.withValues(alpha: 0.3)
                    : glucoseStatus.severity == ValidationSeverity.warning
                        ? AppTheme.warningAmber
                        : AppTheme.dangerRose,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bloodtype, color: Colors.deepOrange, size: 18),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Blood Glucose / सुगर जाँच (RBS)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: glucoseStatus.severity == ValidationSeverity.normal
                              ? AppTheme.successGreen.withValues(alpha: 0.15)
                              : Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          glucoseStatus.severity == ValidationSeverity.normal
                              ? 'Normal ($glucose mg/dL)'
                              : 'Abnormal ($glucose mg/dL)',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: glucoseStatus.severity == ValidationSeverity.normal
                                ? AppTheme.successGreen
                                : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey('vital_glucose_${result.scannedAt.millisecondsSinceEpoch}'),
                    initialValue: '$glucose',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Random Blood Glucose (रक्त ग्लुकोज)',
                      suffixText: 'mg/dL',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val.trim());
                      if (parsed != null) {
                        vm.updateVital('bloodGlucose', parsed);
                      }
                    },
                  ),
                  if (glucoseStatus.messageEn != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      glucoseStatus.messageEn!,
                      style: TextStyle(fontSize: 10.5, color: Colors.amber.shade900),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Station 3: Rapid Lab Tests (Urine Dipstick & UPT)
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Point-of-Care Lab Tests (प्रयोगशाला जाँच):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryDark)),
                  const SizedBox(height: 10),
                  const Text('Urine Dipstick (पिसाब जाँच):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      final currentUrine = (vitals['urineTest'] as String? ?? 'normal').toLowerCase();
                      final isNormal = currentUrine == 'normal' || currentUrine.isEmpty;
                      final hasProtein = currentUrine.contains('protein');
                      final hasGlucose = currentUrine.contains('glucose');
                      final hasBlood = currentUrine.contains('blood');

                      void updateUrine(String type, bool selected) {
                        if (type == 'normal') {
                          vm.updateVital('urineTest', 'normal');
                          return;
                        }
                        final parts = <String>[];
                        if (type == 'protein' ? selected : hasProtein) parts.add('protein');
                        if (type == 'glucose' ? selected : hasGlucose) parts.add('glucose');
                        if (type == 'blood' ? selected : hasBlood) parts.add('blood');

                        if (parts.isEmpty) {
                          vm.updateVital('urineTest', 'normal');
                        } else {
                          vm.updateVital('urineTest', parts.join(', '));
                        }
                      }

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
                            onSelected: (sel) => updateUrine('normal', true),
                          ),
                          FilterChip(
                            label: const Text('Protein+ (प्रोटिन)'),
                            selected: hasProtein,
                            selectedColor: Colors.amber.shade100,
                            checkmarkColor: Colors.amber.shade900,
                            labelStyle: TextStyle(
                              color: hasProtein ? Colors.amber.shade900 : const Color(0xFF334155),
                              fontWeight: hasProtein ? FontWeight.bold : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            onSelected: (sel) => updateUrine('protein', sel),
                          ),
                          FilterChip(
                            label: const Text('Glucose+ (ग्लुकोज)'),
                            selected: hasGlucose,
                            selectedColor: Colors.orange.shade100,
                            checkmarkColor: Colors.deepOrange,
                            labelStyle: TextStyle(
                              color: hasGlucose ? Colors.deepOrange : const Color(0xFF334155),
                              fontWeight: hasGlucose ? FontWeight.bold : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            onSelected: (sel) => updateUrine('glucose', sel),
                          ),
                          FilterChip(
                            label: const Text('Blood+ (रगत)'),
                            selected: hasBlood,
                            selectedColor: Colors.red.shade100,
                            checkmarkColor: Colors.red.shade900,
                            labelStyle: TextStyle(
                              color: hasBlood ? Colors.red.shade900 : const Color(0xFF334155),
                              fontWeight: hasBlood ? FontWeight.bold : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            onSelected: (sel) => updateUrine('blood', sel),
                          ),
                        ],
                      );
                    },
                  ),
                  const Divider(height: 24),
                  const Text('Pregnancy Test (UPT) (गर्भ जाँच):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      {'val': 'neg', 'label': 'Negative (नेगेटिभ)'},
                      {'val': 'pos', 'label': 'Positive (पोजिटिभ)'},
                      {'val': 'not_done', 'label': 'Not Done (जाँच नगरिएको)'},
                    ].map((item) {
                      final isSelected = (vitals['pregnancyTest'] as String? ?? 'neg').toLowerCase() == item['val'];
                      return ChoiceChip(
                        label: Text(item['label']!),
                        selected: isSelected,
                        selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: isSelected ? AppTheme.primaryTeal : const Color(0xFF334155),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 11.5,
                        ),
                        onSelected: (_) => vm.updateVital('pregnancyTest', item['val']),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 4. DIAGNOSES DETECTED & VERIFICATION ──────────────────
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.healing, color: AppTheme.primaryTeal, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Diagnoses Detected (रोग पहिचान)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.primaryDark),
                        ),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: AppTheme.primaryLight,
                        label: Text(
                          '${result.diagnoses.length} Selected',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.primaryTeal),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Review OCR-detected diagnoses. Tap "×" on any chip to remove, or toggle below to add:',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                  ),
                  const SizedBox(height: 10),

                  // Currently Selected Active Diagnoses
                  if (result.diagnoses.isEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: Colors.blueGrey),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No diagnoses selected. Tap standard diagnoses below or type to add custom.',
                              style: TextStyle(fontSize: 11.5, color: Colors.blueGrey),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: result.diagnoses.map((dx) {
                        return InputChip(
                          avatar: const Icon(Icons.healing, size: 15, color: Colors.teal),
                          label: Text(dx, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          backgroundColor: Colors.teal.shade50,
                          deleteIcon: const Icon(Icons.cancel, size: 16, color: Colors.teal),
                          onDeleted: () => vm.removeDiagnosis(dx),
                        );
                      }).toList(),
                    ),
                  ],

                  const Divider(height: 24),
                  const Text(
                    'Standard Yellow Form Diagnoses (२१ वटा मानक रोगहरू):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryDark),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: ClinicalConstants.defaultDiagnoses.map((dx) {
                      final isSelected = result.diagnoses.contains(dx);
                      return FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(dx, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        selected: isSelected,
                        selectedColor: AppTheme.primaryLight,
                        checkmarkColor: AppTheme.primaryTeal,
                        onSelected: (selected) {
                          if (selected) {
                            vm.addDiagnosis(dx);
                          } else {
                            vm.removeDiagnosis(dx);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // Custom diagnosis text field
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customDiagnosisController,
                          decoration: const InputDecoration(
                            hintText: 'Add custom or other diagnosis (अन्य रोग)...',
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          onSubmitted: (val) {
                            if (val.trim().isNotEmpty) {
                              vm.addDiagnosis(val.trim());
                              _customDiagnosisController.clear();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          final val = _customDiagnosisController.text.trim();
                          if (val.isNotEmpty) {
                            vm.addDiagnosis(val);
                            _customDiagnosisController.clear();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 5. PRESCRIPTIONS DISPENSED & VERIFICATION ──────────────
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.medication, color: Colors.indigo, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Prescriptions Dispensed (औषधी)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.primaryDark),
                        ),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.indigo.shade50,
                        label: Text(
                          '${result.medications.length} Prescribed',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.indigo.shade800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tap "×" to remove incorrect medicine, or select from Station 5 medicines below:',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                  ),
                  const SizedBox(height: 10),

                  // Currently Selected Active Prescriptions
                  if (result.medications.isEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: Colors.blueGrey),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No medications recorded. Tap standard medicines below or type custom prescription.',
                              style: TextStyle(fontSize: 11.5, color: Colors.blueGrey),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: result.medications.map((rx) {
                        return InputChip(
                          avatar: const Icon(Icons.medication, size: 15, color: Colors.indigo),
                          label: Text(rx, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                          backgroundColor: Colors.indigo.shade50,
                          deleteIcon: const Icon(Icons.cancel, size: 16, color: Colors.indigo),
                          onDeleted: () => vm.removeMedication(rx),
                        );
                      }).toList(),
                    ),
                  ],

                  const Divider(height: 24),
                  const Text(
                    'Standard Yellow Form Medications (स्टेशन ५ औषधीहरू):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryDark),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: ClinicalConstants.defaultMedications.map((rx) {
                      final isSelected = result.medications.contains(rx);
                      return FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(rx, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        selected: isSelected,
                        selectedColor: Colors.indigo.shade100,
                        checkmarkColor: Colors.indigo.shade900,
                        onSelected: (selected) {
                          if (selected) {
                            vm.addMedication(rx);
                          } else {
                            vm.removeMedication(rx);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // Quick Suggestion Chips for Ring Pessaries & Common Camp Meds
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      'Ring Pessary 65mm',
                      'Ring Pessary 70mm',
                      'Paracetamol 500mg',
                      'Iron + Folic Acid',
                    ].map((quick) {
                      final hasQuick = result.medications.contains(quick);
                      return ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(hasQuick ? Icons.check : Icons.add, size: 14, color: AppTheme.primaryTeal),
                        label: Text(quick, style: const TextStyle(fontSize: 10.5)),
                        onPressed: () {
                          if (hasQuick) {
                            vm.removeMedication(quick);
                          } else {
                            vm.addMedication(quick);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),

                  // Custom prescription text field
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customMedicationController,
                          decoration: const InputDecoration(
                            hintText: 'Add custom medication or dosage (थप औषधी)...',
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          onSubmitted: (val) {
                            if (val.trim().isNotEmpty) {
                              vm.addMedication(val.trim());
                              _customMedicationController.clear();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          final val = _customMedicationController.text.trim();
                          if (val.isNotEmpty) {
                            vm.addMedication(val);
                            _customMedicationController.clear();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 6. SURGICAL REFERRAL & FOLLOW-UP DESTINATION ───────────
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.local_hospital, color: Colors.redAccent, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Surgical Referral & Follow-up (शल्यक्रिया सिफारिस)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.primaryDark),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text('Referral Hospital Destination (सिफारिस गरिएको अस्पताल):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      {'val': null, 'label': 'None (छैन)'},
                      {'val': 'Scheer Memorial Hospital', 'label': 'Scheer Memorial Hospital'},
                      {'val': 'Model Hospital', 'label': 'Model Hospital'},
                      {'val': 'Local Government Hospital', 'label': 'Local Government Hospital'},
                    ].map((item) {
                      final val = item['val'];
                      final isSelected = (val == null && (result.surgicalReferral == null || result.surgicalReferral!.isEmpty)) ||
                          (val != null && result.surgicalReferral?.toLowerCase().contains(val.toLowerCase().split(' ').first) == true);
                      return ChoiceChip(
                        label: Text(item['label']!),
                        selected: isSelected,
                        selectedColor: val == null ? Colors.grey.shade200 : Colors.red.shade100,
                        labelStyle: TextStyle(
                          color: isSelected ? (val == null ? Colors.black87 : Colors.red.shade900) : const Color(0xFF334155),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 11.5,
                        ),
                        onSelected: (_) => vm.updateSurgicalReferral(val),
                      );
                    }).toList(),
                  ),
                  const Divider(height: 20),
                  const Text('Follow-up Destination (फलो-अप कहाँ गर्ने):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      {'val': 'Health Post', 'label': 'Health Post / PHC (स्वास्थ्य चौकी)'},
                      {'val': 'Camp Follow-up Day', 'label': 'Camp Follow-up Day (पुनः शिविर)'},
                      {'val': 'Scheer Memorial Hospital', 'label': 'Scheer Memorial Hospital (अस्पताल)'},
                    ].map((item) {
                      final val = item['val']!;
                      final isSelected = (result.followUpDestination ?? 'Health Post').toLowerCase().contains(val.toLowerCase().split(' ').first);
                      return ChoiceChip(
                        label: Text(item['label']!),
                        selected: isSelected,
                        selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: isSelected ? AppTheme.primaryTeal : const Color(0xFF334155),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 11.5,
                        ),
                        onSelected: (_) => vm.updateFollowUpDestination(val),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 5: VERIFY OCR ACCURACY
  // ==========================================
  Widget _buildVerifyAccuracyTab(OcrScanResultModel result) {
    final demo = result.demographics;
    final obs = result.obstetrics;
    final vitals = result.vitals;
    final pop = result.popStaging;
    final conf = result.fieldConfidences;

    // Build the master list of all detected fields to verify
    final List<Map<String, dynamic>> fields = [
      // ── Demographics ──────────────────────────────────────
      {'key': 'firstName',     'label': 'First Name',        'section': 'Demographics', 'tabIndex': 0, 'value': demo['firstName']?.toString() ?? '—', 'confKey': 'name'},
      {'key': 'surname',       'label': 'Surname',           'section': 'Demographics', 'tabIndex': 0, 'value': demo['surname']?.toString() ?? '—',    'confKey': 'name'},
      {'key': 'age',           'label': 'Patient Age',       'section': 'Demographics', 'tabIndex': 0, 'value': demo['age']?.toString() ?? '—',        'confKey': 'age'},
      {'key': 'maritalStatus', 'label': 'Marital Status',    'section': 'Demographics', 'tabIndex': 0, 'value': demo['maritalStatus']?.toString() ?? '—', 'confKey': 'maritalStatus'},
      {'key': 'relativeName',  'label': 'Husband / Father',  'section': 'Demographics', 'tabIndex': 0, 'value': demo['relativeName']?.toString() ?? '—', 'confKey': 'relative'},
      {'key': 'mobile',        'label': 'Mobile No.',        'section': 'Demographics', 'tabIndex': 0, 'value': demo['mobile']?.toString() ?? '—',     'confKey': 'mobile'},
      {'key': 'contactPerson', 'label': 'Contact Person',    'section': 'Demographics', 'tabIndex': 0, 'value': demo['contactPerson']?.toString() ?? '—', 'confKey': 'contactPerson'},
      {'key': 'contactMobile', 'label': 'Contact Mobile',    'section': 'Demographics', 'tabIndex': 0, 'value': demo['contactMobile']?.toString() ?? '—', 'confKey': 'contactMobile'},
      {'key': 'maritalAge',    'label': 'Age at Marriage',   'section': 'Demographics', 'tabIndex': 0, 'value': demo['maritalAge']?.toString() ?? '—', 'confKey': 'maritalAge'},
      {'key': 'province',      'label': 'Province',          'section': 'Demographics', 'tabIndex': 0, 'value': demo['province']?.toString() ?? '—',   'confKey': 'location'},
      {'key': 'district',      'label': 'District',          'section': 'Demographics', 'tabIndex': 0, 'value': demo['district']?.toString() ?? '—',   'confKey': 'location'},
      {'key': 'municipality',  'label': 'Palika / Municipality', 'section': 'Demographics', 'tabIndex': 0, 'value': demo['municipality']?.toString() ?? '—', 'confKey': 'location'},
      {'key': 'ward',          'label': 'Ward No.',          'section': 'Demographics', 'tabIndex': 0, 'value': demo['ward']?.toString() ?? '—',       'confKey': 'ward'},
      {'key': 'consentTreatment', 'label': 'Consent: Treatment', 'section': 'Demographics', 'tabIndex': 0, 'value': (demo['consentTreatment'] as bool?) == false ? 'No' : 'Yes', 'confKey': 'consent'},
      {'key': 'consentStoreMedicalInfo', 'label': 'Consent: Store Info', 'section': 'Demographics', 'tabIndex': 0, 'value': (demo['consentStoreMedicalInfo'] as bool?) == false ? 'No' : 'Yes', 'confKey': 'consent'},
      // ── Obstetrics ────────────────────────────────────────
      {'key': 'deliveries',     'label': 'Deliveries (P)',   'section': 'Obstetrics',   'tabIndex': 1, 'value': obs['deliveries']?.toString() ?? '—',     'confKey': 'obstetrics'},
      {'key': 'livingChildren', 'label': 'Living Children',  'section': 'Obstetrics',   'tabIndex': 1, 'value': obs['livingChildren']?.toString() ?? '—', 'confKey': 'obstetrics'},
      {'key': 'abortions',      'label': 'Abortions',        'section': 'Obstetrics',   'tabIndex': 1, 'value': obs['abortions']?.toString() ?? '—',      'confKey': 'obstetrics'},
      // ── Visit Reasons ─────────────────────────────────────
      {'key': 'reasonsForVisit','label': 'Reasons for Visit','section': 'Visit Reasons','tabIndex': 1, 'value': (demo['reasonsForVisit'] as List?)?.join(', ') ?? '—', 'confKey': 'reasonsForVisit'},
      // ── POP Staging ───────────────────────────────────────
      {'key': 'anteriorStage',  'label': 'Anterior Stage',   'section': 'POP Staging',  'tabIndex': 2, 'value': pop['anteriorStage']?.toString() ?? '—',   'confKey': 'popStaging'},
      {'key': 'middleStage',    'label': 'Middle Stage',     'section': 'POP Staging',  'tabIndex': 2, 'value': pop['middleStage']?.toString() ?? '—',     'confKey': 'popStaging'},
      {'key': 'posteriorStage', 'label': 'Posterior Stage',  'section': 'POP Staging',  'tabIndex': 2, 'value': pop['posteriorStage']?.toString() ?? '—',  'confKey': 'popStaging'},
      {'key': 'highestStage',   'label': 'Highest POP Stage','section': 'POP Staging',  'tabIndex': 2, 'value': pop['highestPopStage']?.toString() ?? '—', 'confKey': 'popStaging'},
      {'key': 'uterusInside',   'label': 'Uterus Inside',    'section': 'POP Staging',  'tabIndex': 2, 'value': (pop['uterusInside'] as bool?) == true ? 'Yes' : 'No (Prolapsed)', 'confKey': 'popStaging'},
      {'key': 'pelvicTone',     'label': 'Pelvic Floor Tone','section': 'POP Staging',  'tabIndex': 2, 'value': pop['pelvicFloorTone']?.toString() ?? '—', 'confKey': 'popStaging'},
      // ── Vitals ────────────────────────────────────────────
      {'key': 'bp',             'label': 'Blood Pressure',   'section': 'Vitals',       'tabIndex': 3, 'value': '${vitals['systolicBp'] ?? '—'}/${vitals['diastolicBp'] ?? '—'} mmHg', 'confKey': 'bp'},
      {'key': 'pulse',          'label': 'Pulse Rate',       'section': 'Vitals',       'tabIndex': 3, 'value': '${vitals['pulseRate'] ?? '—'} bpm', 'confKey': 'pulse'},
      {'key': 'spo2',           'label': 'SpO2',             'section': 'Vitals',       'tabIndex': 3, 'value': '${vitals['spo2'] ?? '—'}%',         'confKey': 'spo2'},
      {'key': 'glucose',        'label': 'Blood Glucose',    'section': 'Vitals',       'tabIndex': 3, 'value': '${vitals['bloodGlucose'] ?? '—'} mg/dL', 'confKey': 'glucose'},
      {'key': 'urineTest',      'label': 'Urine Test',       'section': 'Vitals',       'tabIndex': 3, 'value': vitals['urineTest']?.toString() ?? '—',   'confKey': 'labs'},
      {'key': 'pregnancyTest',  'label': 'Pregnancy Test',   'section': 'Vitals',       'tabIndex': 3, 'value': vitals['pregnancyTest']?.toString() ?? '—','confKey': 'labs'},
      // ── Diagnoses & Medications ───────────────────────────
      {'key': 'diagnoses',      'label': 'Diagnoses',        'section': 'Clinical',     'tabIndex': 3, 'value': result.diagnoses.isEmpty ? '—' : result.diagnoses.join(', '), 'confKey': 'diagnoses'},
      {'key': 'medications',    'label': 'Medications',      'section': 'Clinical',     'tabIndex': 3, 'value': result.medications.isEmpty ? '—' : result.medications.join(', '), 'confKey': 'medications'},
      {'key': 'referral',       'label': 'Surgical Referral','section': 'Clinical',     'tabIndex': 3, 'value': result.surgicalReferral ?? 'None', 'confKey': 'diagnoses'},
      {'key': 'followUp',       'label': 'Follow-up',        'section': 'Clinical',     'tabIndex': 3, 'value': result.followUpDestination ?? '—', 'confKey': 'diagnoses'},
    ];

    final total = fields.length;
    final reviewed = _verifyMap.values.where((v) => v != null).length;
    final correct = _verifyMap.values.where((v) => v == true).length;
    final incorrect = _verifyMap.values.where((v) => v == false).length;

    // Group by section
    final sections = <String, List<Map<String, dynamic>>>{};
    for (final f in fields) {
      sections.putIfAbsent(f['section'] as String, () => []).add(f);
    }

    Color confColor(String? ck) {
      final c = conf[ck ?? ''] ?? 0.5;
      if (c >= 0.88) return Colors.green.shade700;
      if (c >= 0.70) return Colors.orange.shade700;
      return Colors.red.shade700;
    }

    Color confBg(String? ck) {
      final c = conf[ck ?? ''] ?? 0.5;
      if (c >= 0.88) return Colors.green.shade50;
      if (c >= 0.70) return Colors.orange.shade50;
      return Colors.red.shade50;
    }

    String confLabel(String? ck) {
      final c = conf[ck ?? ''] ?? 0.5;
      if (c >= 0.88) return 'HIGH ${(c * 100).toInt()}%';
      if (c >= 0.70) return 'MED ${(c * 100).toInt()}%';
      return 'LOW ${(c * 100).toInt()}%';
    }

    return Column(
      children: [
        // ── Score header ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: reviewed == 0
                ? Colors.grey.shade50
                : correct == reviewed
                    ? Colors.green.shade50
                    : Colors.blue.shade50,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reviewed == 0
                          ? 'Tap ✅ or ❌ next to each field to verify OCR accuracy'
                          : '$correct / $reviewed reviewed — $correct correct, $incorrect incorrect  (${total - reviewed} remaining)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: reviewed == 0 ? Colors.grey.shade700 : AppTheme.primaryDark,
                      ),
                    ),
                    if (reviewed > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: LinearProgressIndicator(
                          value: reviewed / total,
                          backgroundColor: Colors.grey.shade200,
                          color: AppTheme.primaryTeal,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
              if (reviewed > 0)
                TextButton.icon(
                  onPressed: () => setState(() => _verifyMap.clear()),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Reset All', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade600,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
            ],
          ),
        ),

        // ── Field list ────────────────────────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final section in sections.keys) ...[
                // Section divider
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Row(children: [
                    Container(width: 3, height: 14, color: AppTheme.primaryTeal,
                        margin: const EdgeInsets.only(right: 8)),
                    Text(section.toUpperCase(),
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal, letterSpacing: 1.1)),
                  ]),
                ),
                for (final f in sections[section]!) ...[
                  Builder(builder: (context) {
                    final key = f['key'] as String;
                    final verified = _verifyMap[key];
                    final confKey = f['confKey'] as String?;
                    final tabIdx = f['tabIndex'] as int? ?? 0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: verified == null
                              ? Colors.grey.shade200
                              : verified
                                  ? Colors.green.shade300
                                  : Colors.red.shade300,
                          width: verified != null ? 1.5 : 0.8,
                        ),
                      ),
                      color: verified == null
                          ? Colors.white
                          : verified
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            // Label + value
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text(f['label'] as String,
                                        style: const TextStyle(
                                            fontSize: 11, fontWeight: FontWeight.w600,
                                            color: AppTheme.primaryDark)),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: confBg(confKey),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(confLabel(confKey),
                                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                                              color: confColor(confKey))),
                                    ),
                                  ]),
                                  const SizedBox(height: 2),
                                  Text(f['value'] as String,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        color: (f['value'] as String) == '—'
                                            ? Colors.grey.shade400
                                            : AppTheme.primaryDark,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),

                            // ✅ / ❌ buttons + Edit link
                            const SizedBox(width: 8),
                            if (verified == false)
                              TextButton.icon(
                                onPressed: () => _tabController.animateTo(tabIdx),
                                icon: const Icon(Icons.edit_outlined, size: 13),
                                label: const Text('Edit', style: TextStyle(fontSize: 11)),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red.shade700,
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            _verifyButton(
                              icon: Icons.check_circle_outline,
                              color: Colors.green.shade600,
                              activeColor: Colors.green,
                              isActive: verified == true,
                              tooltip: 'Correct — OCR matched',
                              onTap: () => setState(() =>
                                  _verifyMap[key] = _verifyMap[key] == true ? null : true),
                            ),
                            const SizedBox(width: 4),
                            _verifyButton(
                              icon: Icons.cancel_outlined,
                              color: Colors.red.shade400,
                              activeColor: Colors.red,
                              isActive: verified == false,
                              tooltip: 'Wrong — OCR missed or incorrect',
                              onTap: () => setState(() =>
                                  _verifyMap[key] = _verifyMap[key] == false ? null : false),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _verifyButton({
    required IconData icon,
    required Color color,
    required Color activeColor,
    required bool isActive,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: isActive ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? activeColor : color.withValues(alpha: 0.4),
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Icon(icon, color: isActive ? activeColor : color, size: 20),
        ),
      ),
    );
  }

  // ==========================================
  // HELPER WIDGETS
  // ==========================================
  Widget _buildFieldWithConfidence({
    required String label,
    required String value,
    required String fieldKey,
    required OcrScanResultModel result,
    required ValueChanged<String> onChanged,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final tier = result.getConfidenceTier(fieldKey);
    final color = tier == 'HIGH'
        ? AppTheme.successGreen
        : tier == 'MEDIUM'
            ? AppTheme.warningAmber
            : AppTheme.dangerRose;

    return TextFormField(
      initialValue: value,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Chip(
            visualDensity: VisualDensity.compact,
            label: Text(tier, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
            backgroundColor: color,
          ),
        ),
      ),
    );
  }

  Widget _buildStepperCardRow({
    required String label,
    required String description,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove, size: 18, color: Colors.blueGrey),
                onPressed: value > 0 ? () => onChanged(value - 1) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '$value',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 18, color: AppTheme.primaryTeal),
                onPressed: () => onChanged(value + 1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStageDropdown({
    required String label,
    required int value,
    required int maxStage,
    required ValueChanged<int> onChanged,
  }) {
    final int effectiveMax = maxStage < 4 ? 4 : (value > maxStage ? value : maxStage);
    final int safeValue = value < 0 ? 0 : (value > effectiveMax ? effectiveMax : value);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
        DropdownButton<int>(
          value: safeValue,
          items: List.generate(
            effectiveMax + 1,
            (i) => DropdownMenuItem(value: i, child: Text('Stage $i')),
          ),
          onChanged: (v) => v != null ? onChanged(v) : null,
        ),
      ],
    );
  }


  void _showSuccessDialog(BuildContext context, PatientModel patient) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppTheme.successGreen, size: 28),
            SizedBox(width: 10),
            Text('Scan Committed!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The photographed Yellow Form was verified and committed to the camp database:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Patient ID: ${patient.patientId}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Name: ${patient.fullName}'),
                  Text('Age: ${patient.age} • Ward ${patient.ward}'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              ref.read(ocrScanProvider.notifier).resetScan();
            },
            child: const Text('Scan Another Form'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const PatientListView()),
              );
            },
            child: const Text('View Patient Roll'),
          ),
        ],
      ),
    );
  }
}
