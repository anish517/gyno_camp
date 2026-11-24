import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nepali_utils/nepali_utils.dart';

import '../../core/constants/clinical_constants.dart';
import '../../core/constants/nepal_geodata.dart';
import '../../core/services/clinical_validation_service.dart';
import '../../core/services/nepali_localization_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/nepali_date_helper.dart';
import '../../models/doctor_profile.dart';
import '../../models/nurse_profile.dart';
import '../../models/ocr_scan_result_model.dart';
import '../../models/patient_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../../viewmodels/master_lookup_viewmodel.dart';
import '../../viewmodels/ocr_scan_viewmodel.dart';
import '../../viewmodels/patient_list_viewmodel.dart';
import '../../viewmodels/sync_viewmodel.dart';
import '../patient/patient_list_view.dart';

/// Safely extracts complaintDetails as `Map<String, dynamic>` regardless of
/// whether Gemini returned it as a List of objects or a Map keyed by complaint.
Map<String, dynamic> _safeComplaintDetailsMap(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is List) {
    final result = <String, dynamic>{};
    for (final item in raw) {
      if (item is Map) {
        final key = item['complaint']?.toString().trim();
        if (key != null && key.isNotEmpty) {
          result[key] = <String, dynamic>{
            'duration': item['duration']?.toString() ?? '',
            'remarks': item['remarks']?.toString() ?? '',
            'subOption': item['subOptions'] is List
                ? (item['subOptions'] as List).join(', ')
                : (item['subOption']?.toString() ?? ''),
          };
        }
      }
    }
    return result;
  }
  return <String, dynamic>{};
}

class FormScanView extends ConsumerStatefulWidget {
  const FormScanView({super.key});

  @override
  ConsumerState<FormScanView> createState() => _FormScanViewState();
}

class _FormScanViewState extends ConsumerState<FormScanView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // Tracks per-field verification: true=correct, false=incorrect, null=not yet reviewed
  final Map<String, bool?> _verifyMap = {};
  final TextEditingController _customDiagnosisController =
      TextEditingController();
  final TextEditingController _customMedicationController =
      TextEditingController();
  final TextEditingController _offlineTokenHintController =
      TextEditingController();
  final TextEditingController _offlineDateHintController =
      TextEditingController();
  final TextEditingController _archiveSearchController =
      TextEditingController();
  final TransformationController _previewTransformController =
      TransformationController();
  bool _showImageInPreview = true;
  int _previewRotationQuarterTurns = 0;
  String _archiveSearchQuery = '';
  bool _archiveNeedsReviewOnly = false;
  bool _isArchiveExpanded = true;
  int _archiveVisibleCount = 10;
  int _pendingQueueVisibleCount = 10;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final userCampId = ref.read(userActiveCampProvider)?.id;
        ref.read(ocrScanProvider.notifier).loadOfflineQueue(campId: userCampId);
      }
    });
  }

  @override
  void dispose() {
    _customDiagnosisController.dispose();
    _customMedicationController.dispose();
    _offlineTokenHintController.dispose();
    _offlineDateHintController.dispose();
    _archiveSearchController.dispose();
    _previewTransformController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ocrState = ref.watch(ocrScanProvider);
    final ocrVm = ref.read(ocrScanProvider.notifier);
    final campState = ref.watch(campStateProvider);
    final userActiveCamp = ref.watch(userActiveCampProvider);
    final authState = ref.watch(authStateProvider);
    final deviceState = ref.watch(deviceSecurityProvider);

    void handleBackNavigation() {
      if (ocrState.hasScanResult) {
        ocrVm.returnToCaptureSlots();
      } else {
        if (ocrState.isReviewingCommittedScan) {
          ocrVm.resetScan();
        }
        Navigator.of(context).maybePop();
      }
    }

    final showLeadingBack =
        ocrState.hasScanResult || Navigator.of(context).canPop();

    return PopScope(
      canPop: !ocrState.hasScanResult,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (ocrState.hasScanResult) {
          ocrVm.returnToCaptureSlots();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 68,
          elevation: 0,
          backgroundColor: Colors.transparent,
          flexibleSpace: AppTheme.brandAppBarFlexibleSpace,
          bottom: AppTheme.brandAppBarBottomLine,
          iconTheme: const IconThemeData(color: Color(0xFF1E0A38)),
          leading: showLeadingBack
              ? IconButton(
                  key: const ValueKey('form_scan_appbar_back_btn'),
                  tooltip: ocrState.hasScanResult
                      ? 'Back to Scan & Auto-Fill'
                      : 'Back to Dashboard',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: handleBackNavigation,
                )
              : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Scan & Auto-Fill (फाराम स्क्यान)',
              style: TextStyle(
                fontSize: 17.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E0A38),
                letterSpacing: -0.3,
              ),
            ),
            Text(
              userActiveCamp != null
                  ? 'Camp: ${userActiveCamp.campCode} • ${userActiveCamp.name}'
                  : 'OCR & OMR Split-Screen Verification',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          if (ocrState.hasScanResult)
            IconButton(
              tooltip: 'Clear & Retake',
              icon: const Icon(Icons.refresh),
              onPressed: () => ocrVm.resetScan(),
            ),
        ],
      ),
      body: ocrState.isProcessing
          ? Center(
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 36,
                    vertical: 32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.5,
                          color: AppTheme.primaryTeal,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        ocrState.processingStep ??
                            'Scanning & Digitizing Yellow Form...',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Extracting demographics, OMR checkboxes, vitals and diagnoses',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondaryLight,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
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
                        child: _buildDigitalVerificationPane(
                          context,
                          ref,
                          ocrState,
                          ocrVm,
                          campState,
                          authState,
                          deviceState,
                        ),
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      Expanded(
                        child: _buildDigitalVerificationPane(
                          context,
                          ref,
                          ocrState,
                          ocrVm,
                          campState,
                          authState,
                          deviceState,
                        ),
                      ),
                    ],
                  );
                }
              },
            ),
      ),
    );
  }

  // ==========================================
  // INITIAL CAPTURE PROMPT (DUAL-PAGE SLOTS)
  // ==========================================
  Widget _buildCapturePrompt(BuildContext context, OcrScanViewModel ocrVm) {
    final ocrState = ref.watch(ocrScanProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 500;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 16.0 : 24.0,
          vertical: isCompact ? 16.0 : 24.0,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Scan & Auto-Fill Yellow Form',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isCompact ? 20 : 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Capture both Page 1 (Front: Demographics & Anamnesis) and Page 2 (Back: POP Staging & Treatment).\nThe clinical intake engine will parse and merge both sides into a unified electronic record.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.textSecondaryLight,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),

              // Instruction Banner: Block Letters for Scan Accuracy
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF93C5FD),
                    width: 1.2,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      color: Color(0xFF1D4ED8),
                      size: 22,
                    ),
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
                    isCaptured: ocrState.hasPage1 || ocrState.hasPage1Image,
                    imageBytes: ocrState.page1ImageBytes,
                    imagePath: ocrState.page1ImagePath,
                    summaryText: ocrState.hasPage1
                        ? '${ocrState.page1Scan!.demographics["firstName"] ?? "Patient"} ${ocrState.page1Scan!.demographics["surname"] ?? ""} (${ocrState.page1Scan!.demographics["age"] ?? 35}y) • Ward ${ocrState.page1Scan!.demographics["ward"] ?? "03"}'
                        : (ocrState.hasPage1Image
                            ? 'Page 1 image captured — ready for offline storage or digitization'
                            : null),
                    onCamera: () => ocrVm.capturePage(1),
                    onGallery: () => ocrVm.pickPage(1),
                    onClear: () => ocrVm.clearSlot(1),
                    onPreviewImage: ocrState.hasPage1Image
                        ? () => _showFullScreenFormPreviewDialog(
                              context,
                              page1Bytes: ocrState.page1ImageBytes,
                              page2Bytes: ocrState.page2ImageBytes,
                              initialPage: 1,
                            )
                        : null,
                  );

                  final slot2 = _buildPageSlotCard(
                    pageNumber: 2,
                    title: 'Page 2 (Back Page)',
                    subtitle: 'POP Staging, Vitals, Diagnoses & Prescriptions',
                    isCaptured: ocrState.hasPage2 || ocrState.hasPage2Image,
                    imageBytes: ocrState.page2ImageBytes,
                    imagePath: ocrState.page2ImagePath,
                    summaryText: ocrState.hasPage2
                        ? '${(ocrState.page2Scan!.vitals["systolicBp"] != null && ocrState.page2Scan!.vitals["diastolicBp"] != null) ? "BP ${ocrState.page2Scan!.vitals["systolicBp"]}/${ocrState.page2Scan!.vitals["diastolicBp"]}" : "Vitals not recorded"} • ${ocrState.page2Scan!.diagnoses.length} Diagnoses'
                        : (ocrState.hasPage2Image
                            ? 'Page 2 image captured — ready for offline storage or digitization'
                            : null),
                    onCamera: () => ocrVm.capturePage(2),
                    onGallery: () => ocrVm.pickPage(2),
                    onClear: () => ocrVm.clearSlot(2),
                    onPreviewImage: ocrState.hasPage2Image
                        ? () => _showFullScreenFormPreviewDialog(
                              context,
                              page1Bytes: ocrState.page1ImageBytes,
                              page2Bytes: ocrState.page2ImageBytes,
                              initialPage: 2,
                            )
                        : null,
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
                      children: [slot1, const SizedBox(height: 16), slot2],
                    );
                  }
                },
              ),
              const SizedBox(height: 18),

              // Offline Notice & Save to Local Storage Card (stays above primary Review CTA)
              _buildOfflineNoticeAndSaveCard(context, ocrState, ocrVm),

              // Primary Action: Review Captured Data (immediately below Save Offline Scan)
              if (ocrState.hasPage1 || ocrState.hasPage2) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.fact_check_outlined, size: 22),
                    label: Text(
                      ocrState.isDualReady
                          ? 'Review & Verify Complete Dual-Page Intake (दुवै पाना रुजु गर्नुहोस्)'
                          : (ocrState.hasPage1
                                ? 'Review Page 1 (Front) Only & Fill Page 2 Manually'
                                : 'Review Page 2 (Back) Only & Fill Page 1 Manually'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondaryLight,
                      fontStyle: FontStyle.italic,
                    ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.document_scanner_outlined, size: 18),
                    label: const Text(
                      'Scan Both Pages (Edge Detect & OMR)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => ocrVm.scanBothPagesWithDocumentScanner(),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(
                      Icons.photo_library_outlined,
                      size: 18,
                      color: AppTheme.primaryTeal,
                    ),
                    label: const Text(
                      'Select Both Images at Once (Multi-Select)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => ocrVm.pickBothPages(),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // Growing Offline Pending Queue & Retained Scanned Form Photos Archive
              // Placed below primary review/capture actions so 250+ scans never push
              // the Review & Verify button off-screen.
              _buildOfflineQueueAndArchiveSection(context, ocrState, ocrVm),
              const SizedBox(height: 14),

              // Enterprise Clinical Guidance Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: LayoutBuilder(
                  builder: (context, guideBox) {
                    final isCompact = guideBox.maxWidth < 500;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: AppTheme.primaryTeal,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Clinical Quality Standards & Digitization Protocols',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppTheme.primaryDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (isCompact) ...[
                          _buildGuidelineBullet(
                            icon: Icons.crop_free,
                            title: 'Boundary Alignment',
                            desc: 'Ensure all 4 corner registration marks are clearly inside the camera frame.',
                          ),
                          const SizedBox(height: 8),
                          _buildGuidelineBullet(
                            icon: Icons.wb_sunny_outlined,
                            title: 'Optimal Lighting',
                            desc: 'Avoid harsh shadows and direct flash glare over handwritten vitals.',
                          ),
                          const SizedBox(height: 8),
                          _buildGuidelineBullet(
                            icon: Icons.cloud_sync_outlined,
                            title: 'Offline Scan Queue',
                            desc: 'Scans captured without Internet are stored locally and synced automatically once online.',
                          ),
                          const SizedBox(height: 8),
                          _buildGuidelineBullet(
                            icon: Icons.check_circle_outline,
                            title: 'Clinician Verification',
                            desc: 'All extracted values must be reviewed by the Data Taker prior to commit.',
                          ),
                        ] else ...[
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
                                  icon: Icons.cloud_sync_outlined,
                                  title: 'Offline Scan Queue',
                                  desc: 'Scans captured without Internet are stored locally and synced automatically once online.',
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
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuidelineBullet({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: Colors.blueGrey),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineNoticeAndSaveCard(
    BuildContext context,
    OcrScanState ocrState,
    OcrScanViewModel ocrVm,
  ) {
    final authState = ref.watch(authStateProvider);
    final deviceState = ref.watch(deviceSecurityProvider);
    final activeCamp = ref.watch(userActiveCampProvider);

    final showNotice =
        ocrState.errorMessage != null || ocrState.isOfflineModeDetected;
    if (!showNotice && !ocrState.hasAnyCapturedImage) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showNotice)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF59E0B), width: 1.4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      color: Color(0xFFD97706),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ocrState.isOfflineModeDetected
                            ? 'Offline Scan Ready — Save to Local Storage & Auto-Sync When Online'
                            : 'Scan Notice',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
                if (ocrState.errorMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    ocrState.errorMessage!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ],
              ],
            ),
          ),

        if (ocrState.hasAnyCapturedImage)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF86EFAC), width: 1.4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.save_alt_rounded,
                      color: Color(0xFF15803D),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Save Offline Scan to Local Storage (इन्टरनेट आएपछि स्वतः सिङ्क हुनेछ)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: Color(0xFF166534),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Store captured Yellow Form image(s) on this device now. As soon as Internet reconnects, the system will extract and sync the full patient & clinical record automatically.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF15803D)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _offlineTokenHintController,
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          labelText: 'Optional Token ID (e.g. KTM01-0012)',
                          labelStyle: TextStyle(fontSize: 11.5),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _offlineDateHintController,
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          labelText: 'Optional Date BS (e.g. 2083-08-01)',
                          labelStyle: TextStyle(fontSize: 11.5),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.offline_pin_outlined, size: 19),
                    label: const Text(
                      'Save Scan to Local Storage (Sync After Internet Connection)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: ocrState.isSaving
                        ? null
                        : () async {
                            if (activeCamp == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please select or open an active camp first!',
                                  ),
                                ),
                              );
                              return;
                            }
                            final queued = await ocrVm.saveCurrentScanOffline(
                              campId: activeCamp.id,
                              campCode: activeCamp.campCode,
                              userId:
                                  authState.currentUser?.id ?? 'usr-local',
                              userName:
                                  authState.currentUser?.name ?? 'Field Staff',
                              userRole:
                                  authState.currentUser?.role.toString() ??
                                  'DataTaker',
                              deviceId:
                                  deviceState.device?.deviceId ?? 'dev-local',
                              patientIdHint:
                                  _offlineTokenHintController.text.trim(),
                              intakeDateHint:
                                  _offlineDateHintController.text.trim(),
                            );
                            if (queued != null && context.mounted) {
                              _offlineTokenHintController.clear();
                              _offlineDateHintController.clear();
                              ref
                                  .read(syncStateProvider.notifier)
                                  .refreshPendingCounts();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: Color(0xFF15803D),
                                  content: Text(
                                    '✅ Scan saved to local storage! Will auto-extract & sync when Internet is connected.',
                                  ),
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

  Widget _buildOfflineQueueAndArchiveSection(
    BuildContext context,
    OcrScanState ocrState,
    OcrScanViewModel ocrVm,
  ) {
    if (ocrState.pendingOfflineQueue.isEmpty &&
        ocrState.completedScanArchive.isEmpty) {
      return const SizedBox.shrink();
    }

    final authState = ref.watch(authStateProvider);
    final deviceState = ref.watch(deviceSecurityProvider);
    final activeCamp = ref.watch(userActiveCampProvider);

    final pendingList = ocrState.pendingOfflineQueue;
    final visiblePending = pendingList.take(_pendingQueueVisibleCount).toList();

    final allArchive = ocrState.completedScanArchive;
    final needsReviewCount = allArchive.where((e) => e.needsReview).length;
    final queryLower = _archiveSearchQuery.trim().toLowerCase();
    final filteredArchive = allArchive.where((item) {
      if (_archiveNeedsReviewOnly && !item.needsReview) return false;
      if (queryLower.isEmpty) return true;
      final name = (item.committedPatientName ?? '').toLowerCase();
      final token =
          (item.committedPatientId ?? item.patientIdHint ?? '').toLowerCase();
      final camp = item.campCode.toLowerCase();
      return name.contains(queryLower) ||
          token.contains(queryLower) ||
          camp.contains(queryLower);
    }).toList();
    final visibleArchive = filteredArchive.take(_archiveVisibleCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pendingList.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primaryTeal.withValues(alpha: 0.35),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.cloud_queue,
                      color: AppTheme.primaryTeal,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Locally Stored Offline Scans (${pendingList.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.sync, size: 16),
                      label: const Text(
                        'Sync & Extract All Now',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: ocrState.isProcessing
                          ? null
                          : () async {
                              final count = await ocrVm.syncAllOfflineScans(
                                defaultUserId:
                                    authState.currentUser?.id ?? 'usr-local',
                                defaultUserName:
                                    authState.currentUser?.name ??
                                    'Field Staff',
                                defaultUserRole:
                                    authState.currentUser?.role.toString() ??
                                    'DataTaker',
                                defaultDeviceId:
                                    deviceState.device?.deviceId ?? 'dev-local',
                              );
                              if (context.mounted) {
                                if (activeCamp != null) {
                                  ref
                                      .read(patientListProvider.notifier)
                                      .loadPatients(activeCamp.id);
                                }
                                ref
                                    .read(campStateProvider.notifier)
                                    .loadCamps();
                                ref
                                    .read(syncStateProvider.notifier)
                                    .refreshPendingCounts();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      count > 0
                                          ? '✅ Extracted & synced $count offline scan(s)! Photos retained below for review & correction.'
                                          : 'Could not extract scans yet — please check Internet connection.',
                                    ),
                                  ),
                                );
                              }
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...visiblePending.map((item) {
                  final hasP1 =
                      item.page1Bytes != null && item.page1Bytes!.isNotEmpty;
                  final hasP2 =
                      item.page2Bytes != null && item.page2Bytes!.isNotEmpty;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.description_outlined,
                          size: 20,
                          color: AppTheme.primaryTeal,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.campCode} • ${hasP1 && hasP2 ? "Dual-Page (P1+P2)" : (hasP1 ? "Page 1" : "Page 2")}'
                                '${item.patientIdHint != null && item.patientIdHint!.isNotEmpty ? " • ID: ${item.patientIdHint}" : ""}'
                                '${item.intakeDateHint != null && item.intakeDateHint!.isNotEmpty ? " • Date: ${item.intakeDateHint}" : ""}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                              Text(
                                'Status: ${item.status.toUpperCase()}${item.errorMessage != null ? " (${item.errorMessage})" : ""}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: item.status == 'failed'
                                      ? Colors.red.shade700
                                      : Colors.blueGrey,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Preview Stored Yellow Form',
                          icon: const Icon(
                            Icons.visibility_outlined,
                            size: 18,
                            color: AppTheme.primaryTeal,
                          ),
                          onPressed: () => _showFullScreenFormPreviewDialog(
                            context,
                            page1Bytes: item.page1Bytes,
                            page2Bytes: item.page2Bytes,
                            initialPage: hasP1 ? 1 : 2,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Extract & Commit Now',
                          icon: const Icon(
                            Icons.cloud_upload_outlined,
                            size: 18,
                            color: Colors.indigo,
                          ),
                          onPressed: ocrState.isProcessing
                              ? null
                              : () async {
                                  final ok = await ocrVm
                                      .processSingleOfflineQueueItem(item);
                                  if (context.mounted) {
                                    if (ok && activeCamp != null) {
                                      ref
                                          .read(patientListProvider.notifier)
                                          .loadPatients(activeCamp.id);
                                      ref
                                          .read(campStateProvider.notifier)
                                          .loadCamps();
                                    }
                                    ref
                                        .read(syncStateProvider.notifier)
                                        .refreshPendingCounts();
                                  }
                                },
                        ),
                        IconButton(
                          tooltip: 'Delete Queued Scan',
                          icon: Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Colors.red.shade600,
                          ),
                          onPressed: () async {
                            await ocrVm.deleteOfflineQueueItem(item.id);
                            ref
                                .read(syncStateProvider.notifier)
                                .refreshPendingCounts();
                          },
                        ),
                      ],
                    ),
                  );
                }),
                if (pendingList.length > _pendingQueueVisibleCount ||
                    _pendingQueueVisibleCount > 10)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        Text(
                          'Showing ${visiblePending.length} of ${pendingList.length} pending scans',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.blueGrey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_pendingQueueVisibleCount > 10)
                              TextButton(
                                onPressed: () => setState(
                                  () => _pendingQueueVisibleCount = 10,
                                ),
                                child: const Text('Show Less'),
                              ),
                            if (pendingList.length > _pendingQueueVisibleCount)
                              OutlinedButton(
                                onPressed: () => setState(
                                  () => _pendingQueueVisibleCount += 20,
                                ),
                                child: const Text('Load More (+20)'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

        if (allArchive.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primaryTeal.withValues(alpha: 0.35),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () =>
                      setState(() => _isArchiveExpanded = !_isArchiveExpanded),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.photo_library_outlined,
                        color: AppTheme.primaryTeal,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Scanned Form Photos — Review & Correction (${allArchive.length})',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppTheme.primaryDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Retained Page 1 & Page 2 scan photos for post-sync clinical verification, correction, or photo cleanup.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.blueGrey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: _isArchiveExpanded
                            ? 'Collapse Scanned Form Photos'
                            : 'Expand Scanned Form Photos',
                        icon: Icon(
                          _isArchiveExpanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          color: AppTheme.primaryDark,
                        ),
                        onPressed: () => setState(
                          () => _isArchiveExpanded = !_isArchiveExpanded,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isArchiveExpanded) ...[
                  if (allArchive.length > 5) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 200,
                            maxWidth: 360,
                          ),
                          child: TextField(
                            key: const ValueKey('archive_search_field'),
                            controller: _archiveSearchController,
                            onChanged: (value) => setState(() {
                              _archiveSearchQuery = value;
                              _archiveVisibleCount = 10;
                            }),
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: AppTheme.primaryTeal,
                              ),
                              suffixIcon: _archiveSearchQuery.isNotEmpty
                                  ? IconButton(
                                      tooltip: 'Clear Search',
                                      icon: const Icon(Icons.close, size: 16),
                                      onPressed: () {
                                        _archiveSearchController.clear();
                                        setState(() {
                                          _archiveSearchQuery = '';
                                          _archiveVisibleCount = 10;
                                        });
                                      },
                                    )
                                  : null,
                              hintText: 'Search patient name, Token ID, or camp...',
                              hintStyle: const TextStyle(fontSize: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),
                        ChoiceChip(
                          label: Text(
                            'All (${allArchive.length})',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          selected: !_archiveNeedsReviewOnly,
                          onSelected: (_) => setState(() {
                            _archiveNeedsReviewOnly = false;
                            _archiveVisibleCount = 10;
                          }),
                        ),
                        if (needsReviewCount > 0)
                          ChoiceChip(
                            label: Text(
                              'Needs Review ($needsReviewCount)',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            selected: _archiveNeedsReviewOnly,
                            onSelected: (_) => setState(() {
                              _archiveNeedsReviewOnly = true;
                              _archiveVisibleCount = 10;
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (visibleArchive.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text(
                          'No matching scanned form photos found.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.blueGrey.shade600,
                          ),
                        ),
                      ),
                    )
                  else
                    ...visibleArchive.map((item) {
                  final p1Bytes = item.page1Bytes;
                  final p2Bytes = item.page2Bytes;
                  final hasP1 = p1Bytes != null && p1Bytes.isNotEmpty;
                  final hasP2 = p2Bytes != null && p2Bytes.isNotEmpty;
                  final patientTitle =
                      (item.committedPatientName != null &&
                          item.committedPatientName!.trim().isNotEmpty)
                      ? item.committedPatientName!.trim()
                      : 'Committed Patient Record';
                  final patientToken =
                      (item.committedPatientId != null &&
                          item.committedPatientId!.trim().isNotEmpty)
                      ? item.committedPatientId!.trim()
                      : (item.patientIdHint ?? item.campCode);
                  final pageSummary = hasP1 && hasP2
                      ? 'Dual-Page (P1+P2)'
                      : (hasP1 ? 'Page 1 Only' : 'Page 2 Only');

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: item.needsReview
                          ? const Color(0xFFFFFBEB)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: item.needsReview
                            ? Colors.amber.shade300
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, itemBox) {
                        final isNarrowCard = itemBox.maxWidth < 520;
                        final thumbnailsWidget = InkWell(
                          onTap: () => _showFullScreenFormPreviewDialog(
                            context,
                            page1Bytes: p1Bytes,
                            page2Bytes: p2Bytes,
                            initialPage: hasP1 ? 1 : 2,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasP1)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.memory(
                                    p1Bytes,
                                    width: 38,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      width: 38,
                                      height: 48,
                                      color: Colors.grey.shade200,
                                      child: const Icon(
                                        Icons.image_outlined,
                                        size: 18,
                                        color: AppTheme.primaryTeal,
                                      ),
                                    ),
                                  ),
                                ),
                              if (hasP1 && hasP2) const SizedBox(width: 4),
                              if (hasP2)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.memory(
                                    p2Bytes,
                                    width: 38,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      width: 38,
                                      height: 48,
                                      color: Colors.grey.shade200,
                                      child: const Icon(
                                        Icons.image_outlined,
                                        size: 18,
                                        color: AppTheme.primaryTeal,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );

                        final detailsWidget = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  patientTitle,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryTeal.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    patientToken,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryDark,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: item.needsReview
                                        ? Colors.amber.shade100
                                        : Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    item.needsReview
                                        ? 'AUTO-SAVED • NEEDS REVIEW'
                                        : 'VERIFIED',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: item.needsReview
                                          ? Colors.amber.shade900
                                          : Colors.green.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${item.campCode} • $pageSummary',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.blueGrey.shade700,
                              ),
                            ),
                          ],
                        );

                        final actionsRow = Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Preview Stored Yellow Form Photo',
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 18,
                                color: AppTheme.primaryTeal,
                              ),
                              onPressed: () => _showFullScreenFormPreviewDialog(
                                context,
                                page1Bytes: p1Bytes,
                                page2Bytes: p2Bytes,
                                initialPage: hasP1 ? 1 : 2,
                              ),
                            ),
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                              ),
                              icon: const Icon(
                                Icons.fact_check_outlined,
                                size: 15,
                              ),
                              label: const Text(
                                'Review & Correct',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: ocrState.isProcessing
                                  ? null
                                  : () async {
                                      await ocrVm.openArchivedScanForReview(
                                        item,
                                      );
                                    },
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Delete Stored Scan Photo',
                              icon: Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Colors.red.shade600,
                              ),
                              onPressed: () => _showDeleteScanPhotoDialog(
                                context,
                                ocrVm,
                                item,
                              ),
                            ),
                          ],
                        );

                        if (isNarrowCard) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  thumbnailsWidget,
                                  const SizedBox(width: 10),
                                  Expanded(child: detailsWidget),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: actionsRow,
                              ),
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            thumbnailsWidget,
                            const SizedBox(width: 12),
                            Expanded(child: detailsWidget),
                            actionsRow,
                          ],
                        );
                      },
                    ),
                  );
                }),
                  if (filteredArchive.length > _archiveVisibleCount ||
                      _archiveVisibleCount > 10)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Text(
                            'Showing ${visibleArchive.length} of ${filteredArchive.length} scanned forms',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.blueGrey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_archiveVisibleCount > 10)
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _archiveVisibleCount = 10),
                                  child: const Text('Show Less'),
                                ),
                              if (filteredArchive.length > _archiveVisibleCount)
                                OutlinedButton(
                                  key: const ValueKey('archive_load_more_btn'),
                                  onPressed: () => setState(
                                    () => _archiveVisibleCount += 20,
                                  ),
                                  child: const Text('Load More (+20)'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
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
    Uint8List? imageBytes,
    String? imagePath,
    String? summaryText,
    required VoidCallback onCamera,
    required VoidCallback onGallery,
    required VoidCallback onClear,
    VoidCallback? onPreviewImage,
  }) {
    final hasImage = imageBytes != null && imageBytes.isNotEmpty;
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
                        backgroundColor: isCaptured
                            ? AppTheme.primaryTeal
                            : Colors.blueGrey.shade100,
                        child: Text(
                          '$pageNumber',
                          style: TextStyle(
                            color: isCaptured
                                ? Colors.white
                                : Colors.blueGrey.shade800,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (isCaptured)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.successGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 14,
                              color: AppTheme.successGreen,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Ready',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.successGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Slot Empty',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blueGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 14),

            // Visual Thumbnail Preview of Scanned Yellow Form when imageBytes exist
            if (hasImage) ...[
              InkWell(
                onTap: onPreviewImage,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 125,
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEFCE8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        imageBytes,
                        fit: BoxFit.cover,
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.zoom_in,
                                size: 14,
                                color: Colors.white,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Preview Yellow Form',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // If captured, show summary & clear button
            if (isCaptured && summaryText != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.primaryTeal.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.assignment_turned_in_outlined,
                      size: 18,
                      color: AppTheme.primaryTeal,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        summaryText,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onPreviewImage != null)
                      IconButton(
                        tooltip: 'Preview Scanned Form',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.visibility_outlined,
                          size: 17,
                          color: AppTheme.primaryTeal,
                        ),
                        onPressed: onPreviewImage,
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.camera_alt, size: 16),
                      label: const Text(
                        'Scan Camera',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: onCamera,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.file_upload_outlined, size: 16),
                      label: const Text(
                        'Upload File',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.file_upload_outlined, size: 16),
                  label: const Text(
                    'Upload Image File',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: onGallery,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 13,
                    color: Colors.blueGrey,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Camera capture is only available on Android / iOS',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blueGrey.shade500,
                      ),
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

  Future<void> _showDeleteScanPhotoDialog(
    BuildContext context,
    OcrScanViewModel ocrVm,
    OfflineScanQueueItem item,
  ) async {
    final hasP1 = item.hasPage1;
    final hasP2 = item.hasPage2;
    final patientLabel =
        (item.committedPatientName != null &&
            item.committedPatientName!.trim().isNotEmpty)
        ? '${item.committedPatientName} (${item.committedPatientId ?? item.campCode})'
        : (item.committedPatientId ?? item.patientIdHint ?? item.campCode);

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.hide_image_outlined, color: AppTheme.dangerRose),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Delete Stored Scan Photo?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose which stored Yellow Form scan photo(s) to remove for $patientLabel.',
              style: const TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 18,
                    color: Color(0xFF15803D),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The committed patient and clinical visit record in the database will NOT be deleted.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF166534),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          if (hasP1 && hasP2) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.filter_1_rounded, size: 16),
              label: const Text('Delete Page 1 Photo'),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                await ocrVm.deleteScanPhoto(item.id, pageNumber: 1);
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.filter_2_rounded, size: 16),
              label: const Text('Delete Page 2 Photo'),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                await ocrVm.deleteScanPhoto(item.id, pageNumber: 2);
              },
            ),
          ],
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerRose,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_forever_outlined, size: 16),
            label: Text(
              hasP1 && hasP2 ? 'Delete Both Photos' : 'Delete Stored Photo',
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await ocrVm.deleteScanPhoto(item.id);
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // LEFT PANE: DUAL-DOCUMENT PREVIEW & INSPECTION
  // ==========================================
  Widget _buildDocumentPreviewPane(OcrScanState ocrState) {
    final result = ocrState.scanResult!;
    final activePage = ocrState.activeInspectionPage;
    final isDual =
        result.isDualPage || (ocrState.hasPage1 && ocrState.hasPage2);

    final rawTextToShow = isDual
        ? (activePage == 1
              ? (result.page1RawText ?? result.rawText)
              : (result.page2RawText ?? result.rawText))
        : result.rawText;

    final Uint8List? activeImageBytes = activePage == 1
        ? (ocrState.page1ImageBytes ?? ocrState.page2ImageBytes)
        : (ocrState.page2ImageBytes ?? ocrState.page1ImageBytes);
    final bool hasVisualImage =
        activeImageBytes != null && activeImageBytes.isNotEmpty;

    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ocrState.isReviewingCommittedScan)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF93C5FD)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.fact_check_outlined,
                    size: 16,
                    color: Color(0xFF1D4ED8),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'REVIEW & CORRECTION MODE • Saving updates the existing patient & clinical visit record in-place.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.image_search,
                      color: AppTheme.primaryDark,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Scanned Yellow Form Preview',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (ocrState.activeArchiveItemId != null && hasVisualImage)
                IconButton(
                  tooltip:
                      'Delete Page $activePage Photo (Keeps Patient Record)',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Colors.red.shade600,
                  ),
                  onPressed: () async {
                    await ref
                        .read(ocrScanProvider.notifier)
                        .deleteScanPhoto(
                          ocrState.activeArchiveItemId!,
                          pageNumber: activePage,
                        );
                  },
                ),
              IconButton(
                tooltip: 'Open Full-Screen Form Preview',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.open_in_full_rounded,
                  size: 18,
                  color: AppTheme.primaryTeal,
                ),
                onPressed: () => _showFullScreenFormPreviewDialog(
                  context,
                  page1Bytes: ocrState.page1ImageBytes,
                  page2Bytes: ocrState.page2ImageBytes,
                  initialPage: activePage,
                  rawTextFallback: rawTextToShow,
                ),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  '${(result.overallConfidence * 100).toInt()}% Match',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
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
                  child: Material(
                    color: activePage == 1
                        ? AppTheme.primaryTeal
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => ref
                          .read(ocrScanProvider.notifier)
                          .switchInspectionPage(1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: activePage == 1
                                ? AppTheme.primaryTeal
                                : const Color(0xFF94A3B8),
                            width: 1.3,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              activePage == 1
                                  ? Icons.check_circle
                                  : Icons.description_outlined,
                              size: 15,
                              color: activePage == 1
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Page 1 (Front: Demographics)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: activePage == 1
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: activePage == 2
                        ? AppTheme.primaryTeal
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => ref
                          .read(ocrScanProvider.notifier)
                          .switchInspectionPage(2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: activePage == 2
                                ? AppTheme.primaryTeal
                                : const Color(0xFF94A3B8),
                            width: 1.3,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              activePage == 2
                                  ? Icons.check_circle
                                  : Icons.medical_information_outlined,
                              size: 15,
                              color: activePage == 2
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Page 2 (Back: POP & Vitals)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: activePage == 2
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Image vs OCR Text Switcher + Zoom/Rotate Controls
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Material(
                  color: _showImageInPreview
                      ? AppTheme.primaryTeal
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(7),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: () => setState(() => _showImageInPreview = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: _showImageInPreview
                              ? AppTheme.primaryTeal
                              : const Color(0xFF94A3B8),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showImageInPreview
                                ? Icons.check_circle
                                : Icons.image_outlined,
                            size: 15,
                            color: _showImageInPreview
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Form Image',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _showImageInPreview
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: !_showImageInPreview
                      ? AppTheme.primaryTeal
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(7),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: () => setState(() => _showImageInPreview = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: !_showImageInPreview
                              ? AppTheme.primaryTeal
                              : const Color(0xFF94A3B8),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            !_showImageInPreview
                                ? Icons.check_circle
                                : Icons.subject_rounded,
                            size: 15,
                            color: !_showImageInPreview
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'OCR Text',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: !_showImageInPreview
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                if (hasVisualImage && _showImageInPreview) ...[
                  IconButton(
                    tooltip: 'Rotate 90°',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.rotate_right, size: 17),
                    onPressed: () => setState(() {
                      _previewRotationQuarterTurns =
                          (_previewRotationQuarterTurns + 1) % 4;
                    }),
                  ),
                  IconButton(
                    tooltip: 'Reset Zoom (1:1)',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.center_focus_strong, size: 17),
                    onPressed: () {
                      _previewTransformController.value = Matrix4.identity();
                    },
                  ),
                ],
              ],
            ),
          ),

          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: hasVisualImage && _showImageInPreview
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        InteractiveViewer(
                          transformationController: _previewTransformController,
                          minScale: 0.5,
                          maxScale: 5.0,
                          child: Center(
                            child: RotatedBox(
                              quarterTurns: _previewRotationQuarterTurns,
                              child: Image.memory(
                                activeImageBytes,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 10,
                          top: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade800.withValues(
                                alpha: 0.9,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'PAGE $activePage SCANNED YELLOW FORM (PINCH / SCROLL TO ZOOM)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade700,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isDual
                                    ? 'PAGE $activePage OCR STREAM & METRICS CROP'
                                    : 'PAPER FORM OCR STREAM CROP',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
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
          ),
        ],
      ),
    );
  }

  void _showFullScreenFormPreviewDialog(
    BuildContext context, {
    Uint8List? page1Bytes,
    Uint8List? page2Bytes,
    int initialPage = 1,
    String? rawTextFallback,
  }) {
    int selectedPage = initialPage;
    int rotationTurns = 0;
    final transformCtrl = TransformationController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final activeBytes = selectedPage == 1
                ? (page1Bytes ?? page2Bytes)
                : (page2Bytes ?? page1Bytes);
            final hasP1 = page1Bytes != null && page1Bytes.isNotEmpty;
            final hasP2 = page2Bytes != null && page2Bytes.isNotEmpty;

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1000,
                  maxHeight: 820,
                ),
                child: Column(
                  children: [
                    // Dialog Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E293B),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.document_scanner_outlined,
                                color: Colors.amber,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Scanned Yellow Form Preview (स्क्यान गरिएको फाराम)',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Rotate 90°',
                                icon: const Icon(
                                  Icons.rotate_right,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setDialogState(() {
                                    rotationTurns = (rotationTurns + 1) % 4;
                                  });
                                },
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Reset Zoom',
                                icon: const Icon(
                                  Icons.center_focus_strong,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                                onPressed: () {
                                  transformCtrl.value = Matrix4.identity();
                                },
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Close Preview',
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                          if (hasP1 && hasP2) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Material(
                                    color: selectedPage == 1
                                        ? Colors.amber.shade400
                                        : const Color(0xFF334155),
                                    borderRadius: BorderRadius.circular(8),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () {
                                        setDialogState(() {
                                          selectedPage = 1;
                                          transformCtrl.value =
                                              Matrix4.identity();
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: selectedPage == 1
                                                ? Colors.amber.shade400
                                                : Colors.white54,
                                            width: 1.2,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              selectedPage == 1
                                                  ? Icons.check_circle
                                                  : Icons.description_outlined,
                                              size: 15,
                                              color: selectedPage == 1
                                                  ? const Color(0xFF0F172A)
                                                  : Colors.white,
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                'Page 1 (Front)',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: selectedPage == 1
                                                      ? const Color(0xFF0F172A)
                                                      : Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Material(
                                    color: selectedPage == 2
                                        ? Colors.amber.shade400
                                        : const Color(0xFF334155),
                                    borderRadius: BorderRadius.circular(8),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () {
                                        setDialogState(() {
                                          selectedPage = 2;
                                          transformCtrl.value =
                                              Matrix4.identity();
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: selectedPage == 2
                                                ? Colors.amber.shade400
                                                : Colors.white54,
                                            width: 1.2,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              selectedPage == 2
                                                  ? Icons.check_circle
                                                  : Icons
                                                        .medical_information_outlined,
                                              size: 15,
                                              color: selectedPage == 2
                                                  ? const Color(0xFF0F172A)
                                                  : Colors.white,
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                'Page 2 (Back)',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: selectedPage == 2
                                                      ? const Color(0xFF0F172A)
                                                      : Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: activeBytes != null && activeBytes.isNotEmpty
                          ? InteractiveViewer(
                              transformationController: transformCtrl,
                              minScale: 0.5,
                              maxScale: 6.0,
                              child: Center(
                                child: RotatedBox(
                                  quarterTurns: rotationTurns,
                                  child: Image.memory(
                                    activeBytes,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              margin: const EdgeInsets.all(20),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  rawTextFallback ??
                                      'No camera/file image attached for this template record.',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
        // Top Header Bar with Return to Slots & Preview Form Buttons
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 480;
              return Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppTheme.primaryDark,
                    ),
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
                              : (ocrState.hasPage1
                                    ? 'Page 1 Verification (Front Page)'
                                    : 'Page 2 Verification (Back Page)'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isNarrow ? 12.5 : 13.5,
                            color: AppTheme.primaryDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Form Digitization: ${(result.overallConfidence * 100).toInt()}% Confidence',
                          style: TextStyle(
                            fontSize: isNarrow ? 10 : 11,
                            color: AppTheme.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 14),
                    label: Text(
                      isNarrow ? 'Preview' : 'Preview Form',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onPressed: () => _showFullScreenFormPreviewDialog(
                      context,
                      page1Bytes: ocrState.page1ImageBytes,
                      page2Bytes: ocrState.page2ImageBytes,
                      initialPage: ocrState.activeInspectionPage,
                      rawTextFallback: result.rawText,
                    ),
                  ),
                  if (!isNarrow) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.file_upload_outlined, size: 14),
                      label: const Text(
                        'Capture Slots',
                        style: TextStyle(fontSize: 11),
                      ),
                      onPressed: () => ocrVm.returnToCaptureSlots(),
                    ),
                  ],
                ],
              );
            },
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
              _buildDemographicsTab(
                result,
                ocrVm,
                ocrState,
                ref.watch(userActiveCampProvider)?.id,
                campCode: ref.watch(userActiveCampProvider)?.campCode,
              ),
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
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    ocrState.isSaving ? 'Committing Record...' : 'Verify & Commit to Camp Database (दर्ता सम्पन्न गर्नुहोस्)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: ocrState.isSaving
                      ? null
                      : () async {
                          final activeCamp = ref.read(userActiveCampProvider);
                          if (activeCamp == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please open or select an active camp first!',
                                ),
                              ),
                            );
                            return;
                          }

                          if (ocrState.duplicateResult.hasDuplicate) {
                            final proceed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                title: const Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      color: Colors.amber,
                                      size: 28,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Duplicate Warning',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
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

                          String canonicalizeCampDoctor(String raw) {
                            final trimmed = raw.trim();
                            if (trimmed.isEmpty) return '';
                            final match = activeCamp.doctorProfiles
                                .where((d) => DoctorProfile.namesMatch(d.formattedLabel, trimmed))
                                .firstOrNull;
                            return match?.toStorageString() ?? trimmed;
                          }

                          String canonicalizeCampNurse(String raw) {
                            final trimmed = raw.trim();
                            if (trimmed.isEmpty) return '';
                            final match = activeCamp.nurseProfiles
                                .where((n) => NurseProfile.namesMatch(n.formattedLabel, trimmed))
                                .firstOrNull;
                            return match?.toStorageString() ?? trimmed;
                          }

                          final rawResultDoc =
                              ocrState.scanResult?.examiningDoctor;
                          final resultDoc = (rawResultDoc != null &&
                                  rawResultDoc.trim().isNotEmpty)
                              ? canonicalizeCampDoctor(rawResultDoc)
                              : null;
                          final rawAttendingDoctors =
                              ocrState
                                      .scanResult
                                      ?.attendingDoctors
                                      .isNotEmpty ==
                                  true
                              ? ocrState.scanResult!.attendingDoctors
                              : (resultDoc != null && resultDoc.isNotEmpty
                                    ? [resultDoc]
                                    : const <String>[]);
                          final dedupedDoctors = <String, String>{};
                          for (final d in rawAttendingDoctors) {
                            final resolved = canonicalizeCampDoctor(d);
                            final key = DoctorProfile.canonicalKey(resolved);
                            if (resolved.isNotEmpty && key.isNotEmpty) {
                              dedupedDoctors.putIfAbsent(key, () => resolved);
                            }
                          }
                          final List<String> resultAttendingDoctors =
                              dedupedDoctors.values.toList();

                          final rawResultNurse =
                              ocrState.scanResult?.examiningNurse;
                          final resultNurse = (rawResultNurse != null &&
                                  rawResultNurse.trim().isNotEmpty)
                              ? canonicalizeCampNurse(rawResultNurse)
                              : null;
                          final rawAttendingNurses =
                              ocrState.scanResult?.attendingNurses.isNotEmpty ==
                                  true
                              ? ocrState.scanResult!.attendingNurses
                              : (resultNurse != null && resultNurse.isNotEmpty
                                    ? [resultNurse]
                                    : const <String>[]);
                          final dedupedNurses = <String, String>{};
                          for (final n in rawAttendingNurses) {
                            final resolved = canonicalizeCampNurse(n);
                            final key = NurseProfile.canonicalKey(resolved);
                            if (resolved.isNotEmpty && key.isNotEmpty) {
                              dedupedNurses.putIfAbsent(key, () => resolved);
                            }
                          }
                          final List<String> resultAttendingNurses =
                              dedupedNurses.values.toList();

                          final savedPatient = await ocrVm.confirmAndCommit(
                            campId: activeCamp.id,
                            campCode: activeCamp.campCode,
                            userId: authState.currentUser?.id ?? 'usr-local',
                            userName:
                                authState.currentUser?.name ?? 'Field Staff',
                            userRole:
                                authState.currentUser?.role.toString() ??
                                'DataTaker',
                            deviceId:
                                deviceState.device?.deviceId ?? 'dev-local',
                            primaryDoctorName: resultDoc,
                            attendingDoctorNames: resultAttendingDoctors,
                            primaryNurseName: resultNurse,
                            attendingNurseNames: resultAttendingNurses,
                          );

                          if (savedPatient != null && context.mounted) {
                            ref.read(campStateProvider.notifier).loadCamps();
                            ref
                                .read(patientListProvider.notifier)
                                .loadPatients(activeCamp.id);
                            ref
                                .read(syncStateProvider.notifier)
                                .refreshPendingCounts();
                            _showSuccessDialog(context, savedPatient);
                          } else if (context.mounted) {
                            final latestError =
                                ref.read(ocrScanProvider).errorMessage;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  latestError ??
                                      'Failed to commit scanned form. Please verify required fields.',
                                ),
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
  Widget _buildDemographicsTab(
    OcrScanResultModel result,
    OcrScanViewModel vm,
    OcrScanState ocrState,
    String? campId, {
    String? campCode,
  }) {
    final demo = result.demographics;

    final rawDist = demo['district']?.toString().trim() ?? '';
    String? matchedGlobalDistrict;
    if (rawDist.isNotEmpty) {
      for (final d in NepalGeodata.allDistricts) {
        if (d.toLowerCase() == rawDist.toLowerCase() ||
            rawDist.toLowerCase().contains(d.toLowerCase())) {
          matchedGlobalDistrict = d;
          break;
        }
      }
    }

    final rawProv = demo['province']?.toString().trim() ?? '';
    String? matchedProvince;
    if (rawProv.isNotEmpty) {
      for (final p in ClinicalConstants.nepalProvinces) {
        if (p.toLowerCase() == rawProv.toLowerCase() ||
            rawProv.toLowerCase().contains(p.toLowerCase())) {
          matchedProvince = p;
          break;
        }
      }
    }

    // If a valid Nepal district was scanned (e.g. 'Dhankuta') and either no province
    // was set or the province doesn't contain that district, automatically infer the
    // correct province ('Koshi') so the District DropdownButton always contains validDistrict.
    final validProvince = (matchedGlobalDistrict != null &&
            (matchedProvince == null ||
                !NepalGeodata.districtsFor(matchedProvince)
                    .contains(matchedGlobalDistrict)))
        ? NepalGeodata.provinceOf(matchedGlobalDistrict)
        : (matchedProvince ?? 'Bagmati');

    final districtList =
        NepalGeodata.districtsFor(validProvince).toSet().toList();
    final validDistrict = (matchedGlobalDistrict != null &&
            districtList.contains(matchedGlobalDistrict))
        ? matchedGlobalDistrict
        : (districtList.isNotEmpty ? districtList.first : '');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Token Conflict Warning Card
          if (ocrState.isPatientIdConflict) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Color(0xFFDC2626),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TOKEN ID CONFLICT (टोकन नं. दोहोरिएको छ)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ocrState.patientIdConflictReason ??
                              'This Patient Token ID is already registered.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7F1D1D),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryPurple,
                    ),
                    icon: const Icon(Icons.autorenew, size: 16),
                    label: const Text(
                      'Auto-Generate',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: () {
                      vm.updateDemographic(
                        'patientId',
                        '',
                        campId: campId,
                        campCode: campCode,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],

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
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFDC2626),
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DUPLICATE REGISTRY DETECTED (दोहोरिएको बिरामी रेकर्ड)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ocrState.duplicateResult.matchReasonEn ?? 'A patient with matching credentials already exists in this camp.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7F1D1D),
                          ),
                        ),
                        if (ocrState.duplicateResult.matchReasonNe != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            ocrState.duplicateResult.matchReasonNe!,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF991B1B),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Text(
                            'Existing Record: ${ocrState.duplicateResult.matchedPatient?.fullName} • ID: ${ocrState.duplicateResult.matchedPatient?.patientId} (Ward ${ocrState.duplicateResult.matchedPatient?.ward})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                              color: Color(0xFF991B1B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (!result.isDualPage &&
              (demo.isEmpty || demo['firstName'] == null)) ...[
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

          // ── Page 1 Header: Consultation Triage & Registration Date (परामर्श तथा दर्ता मिति) ──
          Card(
            elevation: 1.5,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: !result.isUnassigned
                    ? const Color(0xFF7C3AED)
                    : Colors.purple.shade200,
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOcrSectionHeader(
                    icon: Icons.medical_information_rounded,
                    iconColor: const Color(0xFF7C3AED),
                    title:
                        'Consultation Triage & Date (परामर्श तथा दर्ता मिति)',
                    titleStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: Color(0xFF5B21B6),
                    ),
                    dateChip: _buildStationDateChip(
                      context: context,
                      field: 'intakeDate',
                      label: 'Intake Date',
                      dateStr:
                          result.intakeDate ??
                          demo['intakeDate'] as String? ??
                          demo['date'] as String?,
                      onDateSelected: (d) =>
                          vm.updateStationDate('intakeDate', d),
                    ),
                    extraChip: !result.isUnassigned
                        ? Chip(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: result.isCounseling
                                ? const Color(0xFFEDE9FE)
                                : const Color(0xFFCCFBF1),
                            avatar: Icon(
                              Icons.check,
                              size: 14,
                              color: result.isCounseling
                                  ? const Color(0xFF7C3AED)
                                  : const Color(0xFF0D9488),
                            ),
                            label: Text(
                              result.isCounseling
                                  ? 'Counseling'
                                  : 'Gynocheckup',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: result.isCounseling
                                    ? const Color(0xFF7C3AED)
                                    : const Color(0xFF0D9488),
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Page 1 Header Triage — Cross-check with physical Yellow Form top checkboxes:',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        avatar: Icon(
                          Icons.do_not_disturb_alt_rounded,
                          size: 14,
                          color: result.isUnassigned
                              ? const Color(0xFF64748B)
                              : Colors.grey,
                        ),
                        label: const Text(
                          'None / Unassigned (तोकिएको छैन)',
                          style: TextStyle(fontSize: 12),
                        ),
                        selected: result.isUnassigned,
                        selectedColor: const Color(0xFFF1F5F9),
                        onSelected: (selected) {
                          if (selected) vm.setTreatmentLevel(null);
                        },
                      ),
                      ChoiceChip(
                        avatar: Icon(
                          Icons.record_voice_over_rounded,
                          size: 14,
                          color: result.isCounseling
                              ? const Color(0xFF7C3AED)
                              : Colors.grey,
                        ),
                        label: const Text(
                          'Counseling (काउन्सिलिङ)',
                          style: TextStyle(fontSize: 12),
                        ),
                        selected: result.isCounseling,
                        selectedColor: const Color(0xFFEDE9FE),
                        onSelected: (selected) {
                          vm.setTreatmentLevel(selected ? 'counseling' : null);
                        },
                      ),
                      ChoiceChip(
                        avatar: Icon(
                          Icons.health_and_safety_rounded,
                          size: 14,
                          color: result.isGynocheckup
                              ? const Color(0xFF0D9488)
                              : Colors.grey,
                        ),
                        label: const Text(
                          'Gynocheckup (गाइनो जाँच)',
                          style: TextStyle(fontSize: 12),
                        ),
                        selected: result.isGynocheckup,
                        selectedColor: const Color(0xFFCCFBF1),
                        onSelected: (selected) {
                          vm.setTreatmentLevel(
                            selected ? 'gyno_checkup' : null,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Patient Token ID & Registration Date Section ──
          Builder(
            builder: (context) {
              final detectedId =
                  (result.patientId ??
                          result.patientTokenId ??
                          demo['patientId'] as String? ??
                          demo['patientTokenId'] as String? ??
                          '')
                      .trim();
              final detectedDate =
                  (result.intakeDate ??
                          demo['intakeDate'] as String? ??
                          demo['date'] as String? ??
                          result.examDate ??
                          result.anamnesisDate ??
                          '')
                      .trim();
              final isDetected = detectedId.isNotEmpty;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDetected
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDetected
                        ? const Color(0xFF86EFAC)
                        : const Color(0xFFCBD5E1),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact = constraints.maxWidth < 520;
                        final titleWidget = Row(
                          children: [
                            Icon(
                              isDetected ? Icons.qr_code_scanner : Icons.tag,
                              size: 18,
                              color: isDetected
                                  ? const Color(0xFF16A34A)
                                  : AppTheme.primaryPurple,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Patient Token ID / बिरामी टोकन नं.',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          ],
                        );

                        final badge = Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isDetected
                                ? const Color(0xFFDCFCE7)
                                : const Color(0xFFEDE9FE),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isDetected
                                  ? const Color(0xFF86EFAC)
                                  : const Color(0xFFDDD6FE),
                            ),
                          ),
                          child: Text(
                            isDetected
                                ? 'Detected from Form (फारमबाट पहिचान)'
                                : 'Auto-Generate on Save (स्वतः उत्पन्न हुनेछ)',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: isDetected
                                  ? const Color(0xFF15803D)
                                  : AppTheme.primaryPurple,
                            ),
                          ),
                        );

                        if (isCompact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              titleWidget,
                              const SizedBox(height: 6),
                              badge,
                            ],
                          );
                        }

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: titleWidget),
                            const SizedBox(width: 8),
                            badge,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: ValueKey('token_id_${result.rawText.hashCode}'),
                      initialValue: detectedId,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        hintText: 'Leave blank to auto-generate sequentially (e.g. 00042 or GC-DHN-2026-00042)',
                        hintStyle: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey,
                        ),
                        suffixIcon: detectedId.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                tooltip: 'Clear to auto-generate',
                                onPressed: () {
                                  vm.updateDemographic(
                                    'patientId',
                                    '',
                                    campId: campId,
                                    campCode: campCode,
                                  );
                                },
                              )
                            : null,
                      ),
                      onChanged: (val) {
                        vm.updateDemographic(
                          'patientId',
                          val,
                          campId: campId,
                          campCode: campCode,
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_month_outlined,
                          size: 17,
                          color: AppTheme.primaryTeal,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Registration Date (BS) / दर्ता मिति (बि.सं.)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        if (detectedDate.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'BS: $detectedDate',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF15803D),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      key: ValueKey('intake_date_${result.rawText.hashCode}'),
                      initialValue: detectedDate,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        hintText:
                            'YYYY-MM-DD in Bikram Sambat (e.g. 2083-08-01) — defaults to today if blank',
                        hintStyle: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey,
                        ),
                        suffixIcon: detectedDate.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                tooltip: 'Clear date',
                                onPressed: () {
                                  vm.updateStationDate('intakeDate', null);
                                },
                              )
                            : null,
                      ),
                      onChanged: (val) {
                        vm.updateStationDate(
                          'intakeDate',
                          val.trim().isEmpty ? null : val.trim(),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),

          _buildFieldWithConfidence(
            label: 'First Name (नाम)',
            value: demo['firstName']?.toString() ?? '',
            fieldKey: 'firstName',
            result: result,
            onChanged: (val) =>
                vm.updateDemographic('firstName', val, campId: campId),
          ),
          const SizedBox(height: 12),
          _buildFieldWithConfidence(
            label: 'Surname (थर)',
            value: demo['surname']?.toString() ?? '',
            fieldKey: 'surname',
            result: result,
            onChanged: (val) =>
                vm.updateDemographic('surname', val, campId: campId),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 550;
              final ageField = _buildFieldWithConfidence(
                label: 'Age (उमेर)',
                value: demo['age']?.toString() ?? '35',
                fieldKey: 'age',
                result: result,
                keyboardType: TextInputType.number,
                onChanged: (val) => vm.updateDemographic(
                  'age',
                  int.tryParse(val) ?? 35,
                  campId: campId,
                ),
              );
              final maritalField = DropdownButtonFormField<String>(
                key: ValueKey('scan_marital_${demo['maritalStatus']}'),
                initialValue:
                    const [
                      'married',
                      'unmarried',
                      'widow',
                      'divorced',
                    ].contains(demo['maritalStatus']?.toString().toLowerCase())
                    ? demo['maritalStatus']?.toString().toLowerCase()
                    : 'married',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Marital Status (वैवाहिक स्थिति)',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                selectedItemBuilder: (context) => const [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Married (विवाहित)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Unmarried (अविवाहित)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Widow (एकल/विधवा)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Divorced (सम्बन्धविच्छेद)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ],
                items: const [
                  DropdownMenuItem(
                    value: 'married',
                    child: Text(
                      'Married (विवाहित)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'unmarried',
                    child: Text(
                      'Unmarried (अविवाहित)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'widow',
                    child: Text(
                      'Widow (एकल/विधवा)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'divorced',
                    child: Text(
                      'Divorced (सम्बन्धविच्छेद)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
                onChanged: (status) {
                  if (status != null) {
                    vm.updateDemographic(
                      'maritalStatus',
                      status,
                      campId: campId,
                    );
                  }
                },
              );

              if (isNarrow) {
                return Column(
                  children: [
                    ageField,
                    const SizedBox(height: 12),
                    maritalField,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: ageField),
                  const SizedBox(width: 12),
                  Expanded(child: maritalField),
                ],
              );
            },
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
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
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
                        vm.updateDemographic(
                          'municipality',
                          newPalikas.isNotEmpty ? newPalikas.first : '',
                          campId: campId,
                        );
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
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
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
                        vm.updateDemographic(
                          'municipality',
                          newPalikas.isNotEmpty ? newPalikas.first : '',
                          campId: campId,
                        );
                      }
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 550;
              final palikaField = Builder(
                builder: (context) {
                  final rawPalikas = NepalGeodata.palikasFor(
                    validDistrict,
                    extraPalikas:
                        demo['municipality'] != null &&
                            demo['municipality'].toString().trim().isNotEmpty
                        ? [demo['municipality'].toString().trim()]
                        : null,
                  );
                  final seenLower = <String>{};
                  final palikas = <String>[];
                  for (final p in rawPalikas) {
                    if (seenLower.add(p.toLowerCase())) {
                      palikas.add(p);
                    }
                  }
                  final currentPalika = palikas.firstWhere(
                    (p) =>
                        p.toLowerCase() ==
                        demo['municipality']?.toString().trim().toLowerCase(),
                    orElse: () => palikas.isNotEmpty ? palikas.first : '',
                  );
                  return DropdownButtonFormField<String>(
                    key: ValueKey(
                      'scan_palika_${validDistrict}_${demo['municipality']}',
                    ),
                    initialValue: currentPalika.isNotEmpty
                        ? currentPalika
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Palika / Municipality * (पालिका)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                    ),
                    items: palikas.map((p) {
                      return DropdownMenuItem(
                        value: p,
                        child: Text(p, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        vm.updateDemographic(
                          'municipality',
                          val,
                          campId: campId,
                        );
                      }
                    },
                  );
                },
              );

              final wardField = _buildFieldWithConfidence(
                label: 'Ward Number (वडा नं)',
                value: demo['ward']?.toString() ?? '03',
                fieldKey: 'ward',
                result: result,
                keyboardType: TextInputType.number,
                onChanged: (val) =>
                    vm.updateDemographic('ward', val, campId: campId),
              );

              if (isNarrow) {
                return Column(
                  children: [
                    palikaField,
                    const SizedBox(height: 12),
                    wardField,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 2, child: palikaField),
                  const SizedBox(width: 12),
                  Expanded(child: wardField),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _buildFieldWithConfidence(
            label: 'Mobile Phone (मोबाइल नम्बर)',
            value: demo['mobile']?.toString() ?? '',
            fieldKey: 'mobile',
            result: result,
            keyboardType: TextInputType.phone,
            onChanged: (val) =>
                vm.updateDemographic('mobile', val, campId: campId),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 550;
              final relativeNameField = _buildFieldWithConfidence(
                label: 'Husband / Father Name (श्रीमान् / बुबाको नाम)',
                value: demo['relativeName']?.toString() ?? '',
                fieldKey: 'relativeName',
                result: result,
                onChanged: (val) =>
                    vm.updateDemographic('relativeName', val, campId: campId),
              );
              final relativeSurnameField = _buildFieldWithConfidence(
                label: 'Relative Surname (थर)',
                value: demo['relativeSurname']?.toString() ?? '',
                fieldKey: 'relativeSurname',
                result: result,
                onChanged: (val) => vm.updateDemographic(
                  'relativeSurname',
                  val,
                  campId: campId,
                ),
              );

              if (isNarrow) {
                return Column(
                  children: [
                    relativeNameField,
                    const SizedBox(height: 12),
                    relativeSurnameField,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 3, child: relativeNameField),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: relativeSurnameField),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Relation / नाता:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final rel in [
                    'Husband',
                    'Father',
                    'Mother',
                    'Guardian',
                    'Other',
                  ])
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        rel == 'Husband'
                            ? 'Husband (श्रीमान्)'
                            : rel == 'Father'
                            ? 'Father (बुबा)'
                            : rel == 'Mother'
                            ? 'Mother (आमा)'
                            : rel == 'Guardian'
                            ? 'Guardian (अभिभावक)'
                            : 'Other (अन्य)',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                              (demo['relativeType']?.toString().toLowerCase() ==
                                  rel.toLowerCase())
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color:
                              (demo['relativeType']?.toString().toLowerCase() ==
                                  rel.toLowerCase())
                              ? Colors.white
                              : const Color(0xFF334155),
                        ),
                      ),
                      selected:
                          demo['relativeType']?.toString().toLowerCase() ==
                          rel.toLowerCase(),
                      selectedColor: const Color(0xFF1B5E20),
                      onSelected: (selected) {
                        if (selected) {
                          vm.updateRelativeType(rel);
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 550;
              final contactPersonField = _buildFieldWithConfidence(
                label: 'Contact Person / सम्पर्क व्यक्ति',
                value: demo['contactPerson']?.toString() ?? '',
                fieldKey: 'contactPerson',
                result: result,
                onChanged: (val) => vm.updateDemographic('contactPerson', val),
              );
              final contactMobileField = _buildFieldWithConfidence(
                label: 'Contact Mobile / सम्पर्क नम्बर',
                value: demo['contactMobile']?.toString() ?? '',
                fieldKey: 'contactMobile',
                result: result,
                keyboardType: TextInputType.phone,
                onChanged: (val) => vm.updateDemographic('contactMobile', val),
              );
              final maritalAgeField = _buildFieldWithConfidence(
                label: 'Marriage Age / विवाह उमेर',
                value: demo['maritalAge']?.toString() ?? '',
                fieldKey: 'maritalAge',
                result: result,
                keyboardType: TextInputType.number,
                onChanged: (val) =>
                    vm.updateDemographic('maritalAge', int.tryParse(val)),
              );

              if (isNarrow) {
                return Column(
                  children: [
                    contactPersonField,
                    const SizedBox(height: 12),
                    contactMobileField,
                    const SizedBox(height: 12),
                    maritalAgeField,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 2, child: contactPersonField),
                  const SizedBox(width: 12),
                  Expanded(child: contactMobileField),
                  const SizedBox(width: 12),
                  Expanded(child: maritalAgeField),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'Primary Reasons for Visit (शिविरमा आउनुको कारण):',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final currentReasons = List<String>.from(
                demo['reasonsForVisit'] as List? ?? [],
              );
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ClinicalConstants.visitReasonOptions.entries.map((
                  entry,
                ) {
                  final key = entry.key;
                  final label = entry.value;
                  final isSelected =
                      currentReasons.contains(key) ||
                      currentReasons.any((r) {
                        final rLower = r.toLowerCase();
                        return rLower == key.toLowerCase() ||
                            rLower == label.toLowerCase() ||
                            (key == 'something hanging out' &&
                                (rLower.contains('hanging') ||
                                    rLower.contains('prolapse') ||
                                    rLower.contains('पाठेघर खस्ने'))) ||
                            (key == 'discharge and or itching' &&
                                (rLower.contains('discharge') ||
                                    rLower.contains('itching') ||
                                    rLower.contains('स्राव') ||
                                    rLower.contains('चिलाउने'))) ||
                            (key == 'problems passing urine' &&
                                (rLower.contains('urine') ||
                                    rLower.contains('पिसाब'))) ||
                            (key == 'problems passing stool' &&
                                (rLower.contains('stool') ||
                                    rLower.contains('दिसा'))) ||
                            (key == 'menstrual problem' &&
                                (rLower.contains('menstrual') ||
                                    rLower.contains('महिनावारी'))) ||
                            (key == 'infertility' &&
                                (rLower.contains('infertility') ||
                                    rLower.contains('बाँझोपन'))) ||
                            (key == 'pain' &&
                                (rLower.contains('pain') ||
                                    rLower.contains('दुखाई'))) ||
                            (key == 'checkup' &&
                                (rLower.contains('checkup') ||
                                    rLower.contains('जाँच')));
                      });
                  return FilterChip(
                    label: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? AppTheme.primaryTeal
                            : Colors.black87,
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
                        updated.removeWhere(
                          (r) =>
                              r == key ||
                              r == label ||
                              r.toLowerCase().contains(key),
                        );
                      }
                      vm.updateDemographic(
                        'reasonsForVisit',
                        updated,
                        campId: campId,
                      );
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
                  title: const Text(
                    'Consent for Examination & Treatment',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'परीक्षण तथा आवश्यक उपचारको लागि स्वीकृति',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  activeColor: AppTheme.primaryTeal,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  onChanged: (val) {
                    vm.updateDemographic(
                      'consentTreatment',
                      val ?? false,
                      campId: campId,
                    );
                  },
                ),
                const Divider(height: 1),
                CheckboxListTile(
                  value: demo['consentStoreMedicalInfo'] as bool? ?? true,
                  title: const Text(
                    'Consent to Store Medical Information',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'स्वास्थ्य विवरण भण्डारण तथा अनुसन्धान सहमति',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  activeColor: AppTheme.primaryTeal,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  onChanged: (val) {
                    vm.updateDemographic(
                      'consentStoreMedicalInfo',
                      val ?? false,
                      campId: campId,
                    );
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
              border: Border.all(
                color: AppTheme.primaryTeal.withValues(alpha: 0.2),
              ),
            ),
            child: _buildOcrSectionHeader(
              icon: Icons.child_friendly,
              iconColor: AppTheme.primaryTeal,
              title: 'Station 1: Obstetric History & Anamnesis (पहिलो स्टेशन: विगत तथा प्रसूति विवरण)',
              titleStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryDark,
              ),
              dateChip: _buildStationDateChip(
                context: context,
                field: 'anamnesisDate',
                label: 'Anamnesis Date',
                dateStr:
                    result.effectiveAnamnesisDate ??
                    result.anamnesisDate ??
                    result.demographics['anamnesisDate'] as String? ??
                    result.intakeDate ??
                    result.demographics['intakeDate'] as String? ??
                    result.demographics['date'] as String?,
                onDateSelected: (d) => vm.updateStationDate('anamnesisDate', d),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
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

          // Station 1: 9 Chief Clinical Complaints Checkboxes
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.checklist_rounded,
                        color: AppTheme.primaryTeal,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Chief Clinical Complaints (प्रमुख क्लिनिकल लक्षणहरू)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${((obs['clinicalComplaints'] as List?) ?? []).length} detected',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Select all presenting complaints matching physical Yellow Form Page 2 checkboxes:',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 9 canonical Yellow Form complaints with per-complaint duration, options & remarks
                  ...() {
                    final patientReasons =
                        ((result.demographics['reasonsForVisit'] as List?) ??
                                [])
                            .map((r) => r.toString().toLowerCase().trim())
                            .toList();

                    final standardComplaints = [
                      {
                        'key': 'prolapse',
                        'label': 'Something hanging out / Prolapse (पाठेघर खस्ने समस्या)',
                        'subCategory': 'Pelvic Floor & Prolapse',
                        'hasDuration': true,
                        'options': ['pessary', 'surgery'],
                        'optionPrefix': 'Previous treatment',
                        'matches': (List<String> r) => r.any(
                          (x) =>
                              x.contains('hanging') ||
                              x.contains('prolapse') ||
                              x.contains('पाठेघर'),
                        ),
                      },
                      {
                        'key': 'discharge',
                        'label':
                            'Discharge and/or Itching (पानी बग्ने / चिलाउने)',
                        'subCategory': 'Infections & Discharge',
                        'hasDuration': true,
                        'options': [
                          'white',
                          'yellow',
                          'green',
                          'grey',
                          'smelly',
                        ],
                        'optionPrefix': 'Discharge colour',
                        'matches': (List<String> r) => r.any(
                          (x) =>
                              x.contains('discharge') ||
                              x.contains('itching') ||
                              x.contains('स्राव') ||
                              x.contains('चिलाउने'),
                        ),
                      },
                      {
                        'key': 'urine',
                        'label':
                            'Problems passing urine (पिसाब सम्बन्धी समस्या)',
                        'subCategory': 'Urinary Symptoms',
                        'hasDuration': true,
                        'options': ['stress', 'urge', 'continuous flow'],
                        'optionPrefix': 'Incontinence type',
                        'matches': (List<String> r) => r.any(
                          (x) => x.contains('urine') || x.contains('पिसाब'),
                        ),
                      },
                      {
                        'key': 'stool',
                        'label':
                            'Problems passing stool (दिसा सम्बन्धी समस्या)',
                        'subCategory': 'Pelvic Floor & Prolapse',
                        'hasDuration': true,
                        'options': <String>[],
                        'optionPrefix': null,
                        'matches': (List<String> r) => r.any(
                          (x) => x.contains('stool') || x.contains('दिसा'),
                        ),
                      },
                      {
                        'key': 'menstrual',
                        'label': 'Menstrual problem (महिनावारी समस्या)',
                        'subCategory': 'Reproductive & Sexual',
                        'hasDuration': false,
                        'options': [
                          'dysmenorrhoea',
                          'metrorrhagia',
                          'menorrhagia',
                          'postmenopausal bleeding',
                        ],
                        'optionPrefix': 'Symptom type',
                        'matches': (List<String> r) => r.any(
                          (x) =>
                              x.contains('menstrual') ||
                              x.contains('महिनावारी'),
                        ),
                      },
                      {
                        'key': 'infertility',
                        'label': 'Infertility (निःसन्तान समस्या)',
                        'subCategory': 'Reproductive & Sexual',
                        'hasDuration': true,
                        'isInfertilityDuration': true,
                        'options': <String>[],
                        'optionPrefix': null,
                        'matches': (List<String> r) => r.any(
                          (x) =>
                              x.contains('infertility') ||
                              x.contains('बाँझोपन'),
                        ),
                      },
                      {
                        'key': 'lower_abdomen_pain',
                        'label': 'Lower abdomen pain (तल्लो पेट दुख्ने)',
                        'subCategory': 'Pelvic & Abdominal',
                        'hasDuration': true,
                        'options': <String>[],
                        'optionPrefix': null,
                        'matches': (List<String> r) => r.any(
                          (x) =>
                              x == 'pain' ||
                              x.contains('दुख्ने') ||
                              ((x.contains('abdomen') ||
                                      x.contains('तल्लो पेट')) &&
                                  x.contains('pain')),
                        ),
                      },
                      {
                        'key': 'lower_back_pain',
                        'label': 'Lower back pain (कम्मर / ढाड दुख्ने)',
                        'subCategory': 'Musculoskeletal & General',
                        'hasDuration': true,
                        'options': <String>[],
                        'optionPrefix': null,
                        'matches': (List<String> r) => r.any(
                          (x) =>
                              x == 'pain' ||
                              x.contains('दुख्ने') ||
                              ((x.contains('back') ||
                                      x.contains('ढाड') ||
                                      x.contains('कम्मर')) &&
                                  x.contains('pain')),
                        ),
                      },
                      {
                        'key': 'checkup',
                        'label': 'General checkup (सामान्य स्वास्थ्य जाँच)',
                        'subCategory': 'General / Other',
                        'hasDuration': false,
                        'options': [
                          'routine wellness screening',
                          'follow-up checkup',
                          'general counseling',
                        ],
                        'optionPrefix': 'Checkup type',
                        'matches': (List<String> r) => r.any(
                          (x) => x.contains('checkup') || x.contains('जाँच'),
                        ),
                      },
                    ];

                    final List<Map<String, dynamic>> resolvedComplaints = [];
                    final lookupState = ref.watch(masterLookupProvider);
                    final activeMasterComplaints =
                        lookupState.activeChiefComplaints;

                    if (activeMasterComplaints.isNotEmpty) {
                      for (final masterItem in activeMasterComplaints) {
                        final code = masterItem.code.toLowerCase().trim();
                        final stdMatch = standardComplaints
                            .cast<Map<String, dynamic>?>()
                            .firstWhere(
                              (s) =>
                                  s != null &&
                                  (s['key'] == code ||
                                      masterItem.labelEn.toLowerCase().contains(
                                        s['key'] as String,
                                      ) ||
                                      (s['label'] as String)
                                          .toLowerCase()
                                          .contains(
                                            masterItem.labelEn.toLowerCase(),
                                          )),
                              orElse: () => null,
                            );

                        final title = masterItem.labelNe.isNotEmpty
                            ? '${masterItem.labelEn} (${masterItem.labelNe})'
                            : masterItem.labelEn;

                        final canonicalKey = stdMatch != null
                            ? (stdMatch['key'] as String)
                            : code;
                        resolvedComplaints.add({
                          'key': canonicalKey,
                          'code': code,
                          'canonicalKey': canonicalKey,
                          'label': title,
                          'hasDuration': stdMatch?['hasDuration'] ?? true,
                          'isInfertilityDuration':
                              stdMatch?['isInfertilityDuration'] == true ||
                              code.contains('infertility'),
                          'options':
                              (stdMatch?['options'] as List<String>?) ??
                              <String>[],
                          'optionPrefix': stdMatch?['optionPrefix'] as String?,
                          'isIntakeReason': patientReasons.any(
                            (r) =>
                                r.contains(canonicalKey) ||
                                r.contains(code) ||
                                r.contains(masterItem.labelEn.toLowerCase()) ||
                                (masterItem.labelNe.isNotEmpty &&
                                    r.contains(
                                      masterItem.labelNe.toLowerCase(),
                                    )),
                          ),
                        });
                      }
                    } else {
                      for (final std in standardComplaints) {
                        final matchesFn =
                            std['matches'] as bool Function(List<String>);
                        final keyStr = std['key'] as String;
                        resolvedComplaints.add({
                          'key': keyStr,
                          'code': keyStr,
                          'canonicalKey': keyStr,
                          'label': std['label'] as String,
                          'hasDuration': std['hasDuration'] as bool,
                          'isInfertilityDuration':
                              std['isInfertilityDuration'] == true,
                          'options': std['options'] as List<String>,
                          'optionPrefix': std['optionPrefix'] as String?,
                          'isIntakeReason': matchesFn(patientReasons),
                        });
                      }
                    }

                    return resolvedComplaints.map((comp) {
                      final cKey = comp['key'] as String;
                      final canonicalKey =
                          comp['canonicalKey'] as String? ?? cKey;
                      final rawCode = comp['code'] as String? ?? cKey;
                      final label = comp['label'] as String;
                      final hasDuration = comp['hasDuration'] as bool;
                      final isInfertilityDuration =
                          comp['isInfertilityDuration'] == true;
                      final options = (comp['options'] as List<String>?) ?? [];
                      final optionPrefix = comp['optionPrefix'] as String?;
                      final isIntakeReason = comp['isIntakeReason'] == true;

                      final selectedComplaints =
                          (obs['clinicalComplaints'] as List?)
                              ?.map((e) => e.toString().toLowerCase().trim())
                              .where((e) => e.isNotEmpty)
                              .toList() ??
                          <String>[];

                      bool matchesComplaintItem(String target) {
                        final t = target.toLowerCase().trim();
                        if (t.isEmpty) return false;
                        if (selectedComplaints.contains(t)) return true;
                        for (final s in selectedComplaints) {
                          if (s == t || s.contains(t) || t.contains(s)) {
                            return true;
                          }
                          if ((t.contains('prolapse') ||
                                  t.contains('hanging') ||
                                  t.contains('पाठेघर')) &&
                              (s.contains('prolapse') ||
                                  s.contains('hanging') ||
                                  s.contains('पाठेघर'))) {
                            return true;
                          }
                          if ((t.contains('discharge') ||
                                  t.contains('itching') ||
                                  t.contains('स्राव')) &&
                              (s.contains('discharge') ||
                                  s.contains('itching') ||
                                  s.contains('स्राव'))) {
                            return true;
                          }
                          if ((t.contains('urine') || t.contains('पिसाब')) &&
                              (s.contains('urine') || s.contains('पिसाब'))) {
                            return true;
                          }
                          if ((t.contains('stool') || t.contains('दिसा')) &&
                              (s.contains('stool') || s.contains('दिसा'))) {
                            return true;
                          }
                          if ((t.contains('menstrual') ||
                                  t.contains('महिनावारी')) &&
                              (s.contains('menstrual') ||
                                  s.contains('महिनावारी'))) {
                            return true;
                          }
                          if ((t.contains('infertility') ||
                                  t.contains('बाँझोपन') ||
                                  t.contains('निःसन्तान')) &&
                              (s.contains('infertility') ||
                                  s.contains('बाँझोपन') ||
                                  s.contains('निःसन्तान'))) {
                            return true;
                          }
                          if ((t == 'lower_abdomen_pain' ||
                                  (t.contains('pain') &&
                                      !t.contains('back'))) &&
                              (s == 'lower_abdomen_pain' ||
                                  (s.contains('pain') &&
                                      !s.contains('back')))) {
                            return true;
                          }
                          if ((t == 'lower_back_pain' ||
                                  t.contains('back') ||
                                  t.contains('ढाड') ||
                                  t.contains('कम्मर')) &&
                              (s == 'lower_back_pain' ||
                                  s.contains('back') ||
                                  s.contains('ढाड') ||
                                  s.contains('कम्मर'))) {
                            return true;
                          }
                          if ((t.contains('checkup') || t.contains('जाँच')) &&
                              (s.contains('checkup') || s.contains('जाँच'))) {
                            return true;
                          }
                        }
                        return false;
                      }

                      final isSelected =
                          matchesComplaintItem(cKey) ||
                          matchesComplaintItem(canonicalKey) ||
                          matchesComplaintItem(rawCode);

                      final details = _safeComplaintDetailsMap(
                        obs['complaintDetails'],
                      );
                      final item = Map<String, dynamic>.from(
                        (details[cKey] ??
                                    details[canonicalKey] ??
                                    details[rawCode] ??
                                    details[cKey.replaceAll('_', ' ')] ??
                                    details[canonicalKey.replaceAll('_', ' ')])
                                as Map? ??
                            {},
                      );

                      final currentDuration =
                          (item['duration'] as String?) ??
                          (obs['complaintsDuration'] as String? ?? '< 1 year');
                      final currentRemarks = (item['remarks'] as String?) ?? '';

                      // Extract selected sub-options
                      final rawSub =
                          item['subOption'] ??
                          item['options'] ??
                          item['subOptions'];
                      List<String> selectedSubOptions = [];
                      if (rawSub is List) {
                        selectedSubOptions = rawSub
                            .map((e) => e.toString().toLowerCase().trim())
                            .toList();
                      } else if (rawSub is String && rawSub.isNotEmpty) {
                        selectedSubOptions = rawSub
                            .split(',')
                            .map((e) => e.toLowerCase().trim())
                            .toList();
                      }

                      final durationsList = isInfertilityDuration
                          ? ClinicalConstants.infertilityDurations
                          : ClinicalConstants.anamnesisDurations;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: isSelected
                              ? AppTheme.primaryLight.withValues(alpha: 0.15)
                              : Colors.grey.shade50,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isSelected
                                  ? AppTheme.primaryTeal.withValues(alpha: 0.5)
                                  : Colors.grey.shade300,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CheckboxListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 0,
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? AppTheme.primaryDark
                                              : const Color(0xFF334155),
                                        ),
                                      ),
                                    ),
                                    if (isIntakeReason) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryTeal
                                              .withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: AppTheme.primaryTeal
                                                .withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: const Text(
                                          'Reported in Intake',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primaryTeal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                value: isSelected,
                                activeColor: AppTheme.primaryTeal,
                                onChanged: (_) {
                                  vm.toggleClinicalComplaint(cKey);
                                },
                              ),
                              if (isSelected) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    0,
                                    14,
                                    12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Divider(height: 10),
                                      if (hasDuration) ...[
                                        const Text(
                                          'Duration since onset (सुरु भएको अवधि):',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: durationsList.map((dur) {
                                            final isDurSelected =
                                                currentDuration == dur ||
                                                dur.toLowerCase().replaceAll(
                                                      ' ',
                                                      '',
                                                    ) ==
                                                    currentDuration
                                                        .toLowerCase()
                                                        .replaceAll(' ', '') ||
                                                (dur.contains('> 1 year') &&
                                                    currentDuration.contains(
                                                      '>1y',
                                                    )) ||
                                                (dur.contains('< 1 year') &&
                                                    currentDuration.contains(
                                                      '<1y',
                                                    )) ||
                                                (dur.contains('< 1month') &&
                                                    currentDuration.contains(
                                                      '1m',
                                                    ));
                                            return ChoiceChip(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              label: Text(
                                                dur,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                              selected: isDurSelected,
                                              selectedColor: AppTheme
                                                  .primaryTeal
                                                  .withValues(alpha: 0.2),
                                              labelStyle: TextStyle(
                                                color: isDurSelected
                                                    ? AppTheme.primaryTeal
                                                    : const Color(0xFF334155),
                                                fontWeight: isDurSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                              onSelected: (sel) {
                                                if (sel) {
                                                  vm.updateComplaintDetail(
                                                    cKey,
                                                    duration: dur,
                                                  );
                                                }
                                              },
                                            );
                                          }).toList(),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      if (options.isNotEmpty) ...[
                                        Text(
                                          optionPrefix != null
                                              ? '$optionPrefix (प्रकार / विवरण):'
                                              : 'Clinical Presentation / Subtypes:',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: options.map((opt) {
                                            final isOptChecked =
                                                selectedSubOptions.any(
                                                  (s) =>
                                                      s ==
                                                          opt
                                                              .toLowerCase()
                                                              .trim() ||
                                                      opt
                                                          .toLowerCase()
                                                          .trim()
                                                          .contains(s) ||
                                                      s.contains(
                                                        opt
                                                            .toLowerCase()
                                                            .trim(),
                                                      ),
                                                );
                                            return FilterChip(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              label: Text(
                                                '${NepaliLocalizationService.translate(opt)} ($opt)',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: isOptChecked
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                              selected: isOptChecked,
                                              selectedColor:
                                                  AppTheme.primaryLight,
                                              checkmarkColor:
                                                  AppTheme.primaryTeal,
                                              labelStyle: TextStyle(
                                                color: isOptChecked
                                                    ? AppTheme.primaryTeal
                                                    : const Color(0xFF334155),
                                              ),
                                              onSelected: (sel) {
                                                final updatedList =
                                                    List<String>.from(
                                                      selectedSubOptions,
                                                    );
                                                if (sel) {
                                                  if (!updatedList.contains(
                                                    opt.toLowerCase(),
                                                  )) {
                                                    updatedList.add(
                                                      opt.toLowerCase(),
                                                    );
                                                  }
                                                } else {
                                                  updatedList.remove(
                                                    opt.toLowerCase(),
                                                  );
                                                }
                                                vm.updateComplaintDetail(
                                                  cKey,
                                                  subOption: updatedList,
                                                );
                                              },
                                            );
                                          }).toList(),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      const SizedBox(height: 4),
                                      TextFormField(
                                        key: ValueKey(
                                          'complaint_remarks_${cKey}_$currentRemarks',
                                        ),
                                        initialValue: currentRemarks,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 10,
                                              ),
                                          labelText:
                                              'Clinical Remarks / टिप्पणी ($cKey)',
                                          hintText: 'Enter clinical remarks, details or severity...',
                                          prefixIcon: const Icon(
                                            Icons.edit_note_rounded,
                                            size: 20,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            borderSide: const BorderSide(
                                              color: Color(0xFFCBD5E1),
                                            ),
                                          ),
                                        ),
                                        onChanged: (val) {
                                          vm.updateComplaintDetail(
                                            cKey,
                                            remarks: val,
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    });
                  }(),
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

          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.primaryTeal.withValues(alpha: 0.2),
              ),
            ),
            child: _buildOcrSectionHeader(
              icon: Icons.medical_services_outlined,
              iconColor: AppTheme.primaryTeal,
              title: 'Station 2: POP Staging & Clinical Examination (पाठेघर खस्ने जाँच)',
              titleStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryDark,
              ),
              dateChip: _buildStationDateChip(
                context: context,
                field: 'examDate',
                label: 'Exam Date',
                dateStr: result.examDate,
                onDateSelected: (d) => vm.updateStationDate('examDate', d),
              ),
            ),
          ),

          // POP Staging (POP anterior wall, POP middle part, POP posterior wall)
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'POP Staging (Yellow Form Page 2):',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStageDropdown(
                    label: 'POP anterior wall (अगाडिको भित्ता):',
                    value: pop['anteriorStage'] as int? ?? 0,
                    maxStage: 3,
                    onChanged: (v) => vm.updatePopStage('anteriorStage', v),
                  ),
                  const Divider(height: 24),
                  _buildStageDropdown(
                    label: 'POP middle part (बीचको भाग - Uterine):',
                    value: pop['middleStage'] as int? ?? 0,
                    maxStage: 4,
                    onChanged: (v) => vm.updatePopStage('middleStage', v),
                  ),
                  const Divider(height: 24),
                  _buildStageDropdown(
                    label: 'POP posterior wall (पछाडिको भित्ता):',
                    value: pop['posteriorStage'] as int? ?? 0,
                    maxStage: 3,
                    onChanged: (v) => vm.updatePopStage('posteriorStage', v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Station 4 Highest POP Stage on Yellow Form
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(
                        child: Text(
                          'Highest POP Stage (अधिकतम स्टेज):',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      () {
                        final highestVal =
                            (pop['highestPopStage'] ??
                                    pop['highestStage'] ??
                                    pop['stage'])
                                as int?;
                        if (highestVal == null) return const SizedBox.shrink();
                        return Chip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: AppTheme.primaryTeal,
                          label: Text(
                            'Stage $highestVal',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        );
                      }(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Directly detected from Station 4 summary on Yellow Form:',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final highestVal =
                          (pop['highestPopStage'] ??
                                  pop['highestStage'] ??
                                  pop['stage'])
                              as int?;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(5, (stage) {
                          final isSelected = highestVal == stage;
                          return ChoiceChip(
                            label: Text('Stage $stage'),
                            selected: isSelected,
                            selectedColor: AppTheme.primaryTeal.withValues(
                              alpha: 0.2,
                            ),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? AppTheme.primaryTeal
                                  : const Color(0xFF334155),
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                vm.updatePopStage('highestPopStage', stage);
                              }
                            },
                          );
                        }),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Station 2: Pelvic Floor Tone & Uterus Inside
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Uterus Inside & Pelvic Floor Muscle (पाठेघरको अवस्था तथा पेल्भिक मांसपेशी):',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      const Text(
                        'Uterus Inside:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('Yes'),
                        selected: pop['uterusInside'] == true,
                        selectedColor: AppTheme.primaryTeal.withValues(
                          alpha: 0.2,
                        ),
                        onSelected: (sel) =>
                            vm.updatePopStage('uterusInside', true),
                      ),
                      ChoiceChip(
                        label: const Text('No'),
                        selected: pop['uterusInside'] == false,
                        selectedColor: Colors.orange.shade100,
                        onSelected: (sel) =>
                            vm.updatePopStage('uterusInside', false),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  const Text(
                    'Pelvic Floor Muscle (पेल्भिक मांसपेशी):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        [
                          {'val': 'normal', 'label': 'Normal (सामान्य)'},
                          {'val': 'weak', 'label': 'Weak (कमजोर)'},
                          {
                            'val': 'hypertonic',
                            'label': 'Hypertonic (कडा / तनावग्रस्त)',
                          },
                        ].map((t) {
                          final isSelected =
                              (pop['pelvicFloorTone'] as String?)
                                  ?.toLowerCase() ==
                              t['val'];
                          return ChoiceChip(
                            label: Text(t['label']!),
                            selected: isSelected,
                            selectedColor: AppTheme.primaryTeal.withValues(
                              alpha: 0.2,
                            ),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? AppTheme.primaryTeal
                                  : const Color(0xFF334155),
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 12,
                            ),
                            onSelected: (_) =>
                                vm.updatePopStage('pelvicFloorTone', t['val']),
                          );
                        }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Station 2: 4 Anatomical Examinations (Vulva, Vagina, Cervix, Uterus)
          // 1. Vulva Examination
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(
                        child: Text(
                          '1. Vulva Examination (बाह्य अङ्ग / भल्भा):',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text(
                          'Normal (सामान्य)',
                          style: TextStyle(fontSize: 11),
                        ),
                        selected:
                            (pop['vulvaRemarks'] as String? ?? '')
                                .trim()
                                .toLowerCase() ==
                            'normal',
                        selectedColor: AppTheme.primaryTeal.withValues(
                          alpha: 0.2,
                        ),
                        onSelected: (sel) {
                          vm.updatePopStage(
                            'vulvaRemarks',
                            sel ? 'Normal' : '',
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: Key('vulvaRemarks_${pop['vulvaRemarks']}'),
                    initialValue: pop['vulvaRemarks'] as String? ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Vulva Remarks (सामान्य नभएमा कैफियत)',
                      hintText: 'Redness, vesicle, ulcer, lesion, atrophic changes...',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => vm.updatePopStage('vulvaRemarks', val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 2. Vagina Examination
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(
                        child: Text(
                          '2. Vagina Examination (योनीको अवस्था):',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text(
                          'Normal (सामान्य)',
                          style: TextStyle(fontSize: 11),
                        ),
                        selected:
                            (pop['vaginaRemarks'] as String? ?? '')
                                .trim()
                                .toLowerCase() ==
                            'normal',
                        selectedColor: AppTheme.primaryTeal.withValues(
                          alpha: 0.2,
                        ),
                        onSelected: (sel) {
                          vm.updatePopStage(
                            'vaginaRemarks',
                            sel ? 'Normal' : '',
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: Key('vaginaRemarks_${pop['vaginaRemarks']}'),
                    initialValue: pop['vaginaRemarks'] as String? ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Vagina Remarks (सामान्य नभएमा कैफियत)',
                      hintText:
                          'Discharge, cystocele, rectocele, atrophic mucosa...',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => vm.updatePopStage('vaginaRemarks', val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 3. Cervix Appearance
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(
                        child: Text(
                          '3. Cervix Appearance (पाठेघरको मुखको अवस्था):',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text(
                          'Normal / Smooth (सामान्य)',
                          style: TextStyle(fontSize: 11),
                        ),
                        selected:
                            (pop['cervixRemarks'] as String? ?? '')
                                    .trim()
                                    .toLowerCase() ==
                                'normal' ||
                            (pop['cervixRemarks'] as String? ?? '')
                                    .trim()
                                    .toLowerCase() ==
                                'normal / smooth',
                        selectedColor: AppTheme.primaryTeal.withValues(
                          alpha: 0.2,
                        ),
                        onSelected: (sel) {
                          vm.updatePopStage(
                            'cervixRemarks',
                            sel ? 'Normal / Smooth' : '',
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: Key('cervixRemarks_${pop['cervixRemarks']}'),
                    initialValue: pop['cervixRemarks'] as String? ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Cervix Remarks (सामान्य नभएमा कैफियत)',
                      hintText:
                          'Erosion, polyp, bleeding on touch, hypertrophy...',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => vm.updatePopStage('cervixRemarks', val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 4. Uterus Examination
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(
                        child: Text(
                          '4. Uterus Examination (पाठेघर सम्बन्धी कैफियत):',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text(
                          'Normal (सामान्य)',
                          style: TextStyle(fontSize: 11),
                        ),
                        selected:
                            (pop['uterusRemarks'] as String? ?? '')
                                    .trim()
                                    .toLowerCase() ==
                                'normal' ||
                            (pop['uterusRemarks'] as String? ?? '')
                                    .trim()
                                    .toLowerCase() ==
                                'normal size',
                        selectedColor: AppTheme.primaryTeal.withValues(
                          alpha: 0.2,
                        ),
                        onSelected: (sel) {
                          vm.updatePopStage(
                            'uterusRemarks',
                            sel ? 'Normal' : '',
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: Key('uterusRemarks_${pop['uterusRemarks']}'),
                    initialValue: pop['uterusRemarks'] as String? ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Uterus Remarks (सामान्य नभएमा कैफियत)',
                      hintText:
                          'Bulky, tender, fibroid, restricted, retroverted...',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => vm.updatePopStage('uterusRemarks', val),
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
  Widget _buildVitalsAndDiagnosesTab(
    OcrScanResultModel result,
    OcrScanViewModel vm,
  ) {
    final vitals = result.vitals;

    final int? sys = () {
      final v = (vitals['systolicBp'] as num?)?.toInt();
      return (v != null && v > 0) ? v : null;
    }();
    final int? dia = () {
      final v = (vitals['diastolicBp'] as num?)?.toInt();
      return (v != null && v > 0) ? v : null;
    }();
    final int? pulse = () {
      final v = ((vitals['pulseRate'] ?? vitals['pulse']) as num?)?.toInt();
      return (v != null && v > 0) ? v : null;
    }();
    final int? spo2 = () {
      final v = (vitals['spo2'] as num?)?.toInt();
      return (v != null && v > 0) ? v : null;
    }();
    final int? glucose = () {
      final v = ((vitals['bloodGlucose'] ?? vitals['glucose']) as num?)?.toInt();
      return (v != null && v > 0) ? v : null;
    }();
    final bool hasBp = sys != null || dia != null;

    final bpStatus = ClinicalValidationService.validateSystolicBp(sys);
    final bpDiaStatus = ClinicalValidationService.validateDiastolicBp(
      dia,
      systolic: sys,
    );
    final ValidationSeverity bpSeverity =
        (bpStatus.isError || bpDiaStatus.isError)
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

          const Text(
            'Point-of-Care Vitals (भाइटल परीक्षण):',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
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
                      const Icon(
                        Icons.favorite,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Blood Pressure (रक्तचाप)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: !hasBp
                            ? Colors.grey.shade200
                            : bpSeverity == ValidationSeverity.normal
                            ? AppTheme.successGreen.withValues(alpha: 0.15)
                            : bpSeverity == ValidationSeverity.warning
                            ? AppTheme.warningAmber.withValues(alpha: 0.2)
                            : AppTheme.dangerRose.withValues(alpha: 0.2),
                        label: Text(
                          !hasBp
                              ? 'Not Recorded'
                              : bpSeverity == ValidationSeverity.normal
                              ? 'Normal (${sys ?? "—"}/${dia ?? "—"})'
                              : bpSeverity == ValidationSeverity.warning
                              ? 'Warning (${sys ?? "—"}/${dia ?? "—"})'
                              : 'Alert (${sys ?? "—"}/${dia ?? "—"})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: !hasBp
                                ? const Color(0xFF64748B)
                                : bpSeverity == ValidationSeverity.normal
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
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 400;
                      final sysField = TextFormField(
                        key: ValueKey(
                          'vital_sys_${result.scannedAt.millisecondsSinceEpoch}',
                        ),
                        initialValue: sys != null ? '$sys' : '',
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          labelText: isNarrow
                              ? 'Systolic'
                              : 'Systolic (सिस्टोलिक)',
                          hintText: '—',
                          suffixText: 'mmHg',
                          suffixStyle: const TextStyle(
                            fontSize: 13,
                            color: Colors.blueGrey,
                          ),
                          border: const OutlineInputBorder(),
                          isDense: false,
                          prefixIcon: isNarrow
                              ? null
                              : const Icon(
                                  Icons.arrow_upward,
                                  size: 16,
                                  color: Colors.blueGrey,
                                ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        onChanged: (val) {
                          final trimmed = val.trim();
                          if (trimmed.isEmpty) {
                            vm.updateVital('systolicBp', null);
                            return;
                          }
                          final parsed = int.tryParse(trimmed);
                          if (parsed != null) {
                            vm.updateVital('systolicBp', parsed);
                          }
                        },
                      );
                      final diaField = TextFormField(
                        key: ValueKey(
                          'vital_dia_${result.scannedAt.millisecondsSinceEpoch}',
                        ),
                        initialValue: dia != null ? '$dia' : '',
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          labelText: isNarrow
                              ? 'Diastolic'
                              : 'Diastolic (डायस्टोलिक)',
                          hintText: '—',
                          suffixText: 'mmHg',
                          suffixStyle: const TextStyle(
                            fontSize: 13,
                            color: Colors.blueGrey,
                          ),
                          border: const OutlineInputBorder(),
                          isDense: false,
                          prefixIcon: isNarrow
                              ? null
                              : const Icon(
                                  Icons.arrow_downward,
                                  size: 16,
                                  color: Colors.blueGrey,
                                ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        onChanged: (val) {
                          final trimmed = val.trim();
                          if (trimmed.isEmpty) {
                            vm.updateVital('diastolicBp', null);
                            return;
                          }
                          final parsed = int.tryParse(trimmed);
                          if (parsed != null) {
                            vm.updateVital('diastolicBp', parsed);
                          }
                        },
                      );
                      if (isNarrow) {
                        return Column(
                          children: [
                            sysField,
                            const SizedBox(height: 10),
                            diaField,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: sysField),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '/',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          Expanded(child: diaField),
                        ],
                      );
                    },
                  ),
                  if (bpStatus.messageEn != null ||
                      bpDiaStatus.messageEn != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
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

          // ── 2. PULSE RATE & SPO2 SATURATION (RESPONSIVE) ─────────
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 480;

              final pulseCard = Card(
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
                          const Icon(
                            Icons.monitor_heart,
                            color: Colors.pinkAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Pulse Rate',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: pulse == null
                                  ? Colors.grey.shade200
                                  : pulseStatus.severity ==
                                      ValidationSeverity.normal
                                  ? AppTheme.successGreen.withValues(
                                      alpha: 0.15,
                                    )
                                  : Colors.amber.shade100,
                            ),
                            child: Text(
                              pulse == null
                                  ? 'Not Recorded'
                                  : pulseStatus.severity == ValidationSeverity.normal
                                  ? 'Normal'
                                  : 'Alert',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: pulse == null
                                    ? const Color(0xFF64748B)
                                    : pulseStatus.severity ==
                                        ValidationSeverity.normal
                                    ? AppTheme.successGreen
                                    : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: ValueKey(
                          'vital_pulse_${result.scannedAt.millisecondsSinceEpoch}',
                        ),
                        initialValue: pulse != null ? '$pulse' : '',
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'नाडी (bpm)',
                          hintText: '—',
                          suffixText: 'bpm',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                        ),
                        onChanged: (val) {
                          final trimmed = val.trim();
                          if (trimmed.isEmpty) {
                            vm.updateVital('pulseRate', null);
                            return;
                          }
                          final parsed = int.tryParse(trimmed);
                          if (parsed != null) {
                            vm.updateVital('pulseRate', parsed);
                          }
                        },
                      ),
                      if (pulseStatus.messageEn != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          pulseStatus.messageEn!,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );

              final spo2Card = Card(
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
                          const Icon(
                            Icons.air,
                            color: Colors.blueAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'SpO2 Saturation',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: spo2 == null
                                  ? Colors.grey.shade200
                                  : spo2Status.severity ==
                                      ValidationSeverity.normal
                                  ? AppTheme.successGreen.withValues(
                                      alpha: 0.15,
                                    )
                                  : Colors.amber.shade100,
                            ),
                            child: Text(
                              spo2 == null
                                  ? 'Not Recorded'
                                  : spo2Status.severity == ValidationSeverity.normal
                                  ? 'Normal'
                                  : 'Hypoxia',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: spo2 == null
                                    ? const Color(0xFF64748B)
                                    : spo2Status.severity ==
                                        ValidationSeverity.normal
                                    ? AppTheme.successGreen
                                    : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: ValueKey(
                          'vital_spo2_${result.scannedAt.millisecondsSinceEpoch}',
                        ),
                        initialValue: spo2 != null ? '$spo2' : '',
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'अक्सिजन (%)',
                          hintText: '—',
                          suffixText: '%',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                        ),
                        onChanged: (val) {
                          final trimmed = val.trim();
                          if (trimmed.isEmpty) {
                            vm.updateVital('spo2', null);
                            return;
                          }
                          final parsed = int.tryParse(trimmed);
                          if (parsed != null) {
                            vm.updateVital('spo2', parsed);
                          }
                        },
                      ),
                      if (spo2Status.messageEn != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          spo2Status.messageEn!,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );

              if (isNarrow) {
                return Column(
                  children: [pulseCard, const SizedBox(height: 10), spo2Card],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: pulseCard),
                  const SizedBox(width: 10),
                  Expanded(child: spo2Card),
                ],
              );
            },
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
                      const Icon(
                        Icons.bloodtype,
                        color: Colors.deepOrange,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Blood Glucose / सुगर जाँच (RBS)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: glucose == null
                              ? Colors.grey.shade200
                              : glucoseStatus.severity ==
                                  ValidationSeverity.normal
                              ? AppTheme.successGreen.withValues(alpha: 0.15)
                              : Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          glucose == null
                              ? 'Not Recorded'
                              : glucoseStatus.severity == ValidationSeverity.normal
                              ? 'Normal ($glucose mg/dL)'
                              : 'Abnormal ($glucose mg/dL)',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: glucose == null
                                ? const Color(0xFF64748B)
                                : glucoseStatus.severity ==
                                    ValidationSeverity.normal
                                ? AppTheme.successGreen
                                : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey(
                      'vital_glucose_${result.scannedAt.millisecondsSinceEpoch}',
                    ),
                    initialValue: glucose != null ? '$glucose' : '',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Random Blood Glucose (रक्त ग्लुकोज)',
                      hintText: '—',
                      suffixText: 'mg/dL',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (val) {
                      final trimmed = val.trim();
                      if (trimmed.isEmpty) {
                        vm.updateVital('bloodGlucose', null);
                        return;
                      }
                      final parsed = int.tryParse(trimmed);
                      if (parsed != null) {
                        vm.updateVital('bloodGlucose', parsed);
                      }
                    },
                  ),
                  if (glucoseStatus.messageEn != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      glucoseStatus.messageEn!,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.amber.shade900,
                      ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOcrSectionHeader(
                    icon: Icons.biotech_outlined,
                    iconColor: AppTheme.primaryDark,
                    title: 'Point-of-Care Lab Tests (प्रयोगशाला जाँच):',
                    titleStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryDark,
                    ),
                    dateChip: _buildStationDateChip(
                      context: context,
                      field: 'labTestDate',
                      label: 'Lab Date',
                      dateStr: result.labTestDate,
                      onDateSelected: (d) =>
                          vm.updateStationDate('labTestDate', d),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Urine Test (पिसाब जाँच):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      final currentUrine =
                          (vitals['urineTest'] as String? ?? 'normal')
                              .toLowerCase();
                      final isNormal =
                          currentUrine == 'normal' || currentUrine.isEmpty;
                      final isPos =
                          !isNormal &&
                          (currentUrine.contains('pos') ||
                              currentUrine.contains('+') ||
                              currentUrine.contains('protein') ||
                              currentUrine.contains('glucose') ||
                              currentUrine.contains('blood'));

                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Normal (सामान्य)'),
                            selected: isNormal,
                            selectedColor: AppTheme.primaryTeal.withValues(
                              alpha: 0.2,
                            ),
                            labelStyle: TextStyle(
                              color: isNormal
                                  ? AppTheme.primaryTeal
                                  : const Color(0xFF334155),
                              fontWeight: isNormal
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            onSelected: (_) =>
                                vm.updateVital('urineTest', 'normal'),
                          ),
                          ChoiceChip(
                            label: const Text('Positive (पोजिटिभ)'),
                            selected: isPos,
                            selectedColor: Colors.purple.shade100,
                            labelStyle: TextStyle(
                              color: isPos
                                  ? Colors.purple.shade900
                                  : const Color(0xFF334155),
                              fontWeight: isPos
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            onSelected: (_) =>
                                vm.updateVital('urineTest', 'pos'),
                          ),
                        ],
                      );
                    },
                  ),
                  const Divider(height: 24),
                  const Text(
                    'Pregnancy Test (UPT) (गर्भ जाँच):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        [
                          {'val': 'neg', 'label': 'Negative (नेगेटिभ)'},
                          {'val': 'pos', 'label': 'Positive (पोजिटिभ)'},
                        ].map((item) {
                          final rawPreg =
                              (vitals['pregnancyTest'] as String? ?? 'neg')
                                  .toLowerCase()
                                  .trim();
                          final isSelected =
                              rawPreg == item['val'] ||
                              (item['val'] == 'neg' &&
                                  (rawPreg == 'negative' ||
                                      rawPreg.startsWith('neg'))) ||
                              (item['val'] == 'pos' &&
                                  (rawPreg == 'positive' ||
                                      rawPreg.startsWith('pos')));
                          return ChoiceChip(
                            label: Text(item['label']!),
                            selected: isSelected,
                            selectedColor: AppTheme.primaryTeal.withValues(
                              alpha: 0.2,
                            ),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? AppTheme.primaryTeal
                                  : const Color(0xFF334155),
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            onSelected: (_) =>
                                vm.updateVital('pregnancyTest', item['val']),
                          );
                        }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── ECG Examination (ईसीजी परीक्षण) ─────────────────────────
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.monitor_heart,
                        color: AppTheme.primaryTeal,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'ECG Examination (ईसीजी परीक्षण):',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        [
                          {
                            'val': 'Normal Sinus',
                            'label': 'Normal Sinus (सामान्य)',
                          },
                          {'val': 'Abnormal', 'label': 'Abnormal (असामान्य)'},
                          {
                            'val': 'Not Done',
                            'label': 'Not Done (जाँच नगरिएको)',
                          },
                        ].map((item) {
                          final rawEcg = (vitals['ecg'] as String? ?? '')
                              .trim();
                          final isSelected =
                              rawEcg.toLowerCase() ==
                                  item['val']!.toLowerCase() ||
                              (item['val'] == 'Normal Sinus' &&
                                  (rawEcg.toLowerCase().contains('normal') ||
                                      rawEcg.toLowerCase().contains(
                                        'sinus',
                                      ))) ||
                              (item['val'] == 'Abnormal' &&
                                  rawEcg.toLowerCase().contains('abnormal')) ||
                              (item['val'] == 'Not Done' &&
                                  (rawEcg.toLowerCase().contains('not') ||
                                      rawEcg.toLowerCase().contains('done')));
                          return ChoiceChip(
                            label: Text(item['label']!),
                            selected: isSelected,
                            selectedColor: AppTheme.primaryTeal.withValues(
                              alpha: 0.2,
                            ),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? AppTheme.primaryTeal
                                  : const Color(0xFF334155),
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            onSelected: (_) {
                              vm.updateVital('ecg', item['val']);
                            },
                          );
                        }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: ValueKey(
                      'vital_ecgNotes_${result.scannedAt.millisecondsSinceEpoch}',
                    ),
                    initialValue: vitals['ecgNotes'] as String? ?? '',
                    decoration: const InputDecoration(
                      labelText: 'ECG Findings / Notes (ईसीजी कैफियत)',
                      hintText:
                          'Rate, rhythm, axis, ST-T changes if abnormal...',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (val) {
                      vm.updateVital('ecgNotes', val.trim());
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 4. DIAGNOSES DETECTED & VERIFICATION ──────────────────
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOcrSectionHeader(
                    icon: Icons.healing,
                    iconColor: AppTheme.primaryTeal,
                    title: 'Diagnoses Detected (रोग पहिचान)',
                    titleStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: AppTheme.primaryDark,
                    ),
                    dateChip: _buildStationDateChip(
                      context: context,
                      field: 'conclusionDate',
                      label: 'Conclusion Date',
                      dateStr: result.conclusionDate,
                      onDateSelected: (d) =>
                          vm.updateStationDate('conclusionDate', d),
                    ),
                    extraChip: Chip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppTheme.primaryLight,
                      label: Text(
                        '${result.diagnoses.length} Selected',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: AppTheme.primaryTeal,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Review OCR-detected diagnoses. Tap "×" on any chip to remove, or toggle below to add:',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondaryLight,
                    ),
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
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Colors.blueGrey,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No diagnoses selected. Tap standard diagnoses below or type to add custom.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.blueGrey,
                              ),
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
                          avatar: const Icon(
                            Icons.healing,
                            size: 15,
                            color: Colors.teal,
                          ),
                          label: Text(
                            dx,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          backgroundColor: Colors.teal.shade50,
                          deleteIcon: const Icon(
                            Icons.cancel,
                            size: 16,
                            color: Colors.teal,
                          ),
                          onDeleted: () => vm.removeDiagnosis(dx),
                        );
                      }).toList(),
                    ),
                  ],

                  const Divider(height: 24),
                  const Text(
                    'Standard Yellow Form Diagnoses (२१ वटा मानक रोगहरू):',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: ClinicalConstants.defaultDiagnoses.map((dx) {
                      final isSelected = result.diagnoses.contains(dx);
                      return FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          dx,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
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
                            hintText:
                                'Add custom or other diagnosis (अन्य रोग)...',
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text(
                          'Add',
                          style: TextStyle(fontSize: 12),
                        ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOcrSectionHeader(
                    icon: Icons.medication,
                    iconColor: Colors.indigo,
                    title: 'Prescriptions Dispensed (औषधी)',
                    titleStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: AppTheme.primaryDark,
                    ),
                    dateChip: _buildStationDateChip(
                      context: context,
                      field: 'treatmentDate',
                      label: 'Treatment Date',
                      dateStr: result.treatmentDate,
                      onDateSelected: (d) =>
                          vm.updateStationDate('treatmentDate', d),
                    ),
                    extraChip: Chip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.indigo.shade50,
                      label: Text(
                        '${result.medications.length} Prescribed',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: Colors.indigo.shade800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tap "×" to remove incorrect medicine, or select from Station 5 medicines below:',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondaryLight,
                    ),
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
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Colors.blueGrey,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No medications recorded. Tap standard medicines below or type custom prescription.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.blueGrey,
                              ),
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
                          avatar: const Icon(
                            Icons.medication,
                            size: 15,
                            color: Colors.indigo,
                          ),
                          label: Text(
                            rx,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          backgroundColor: Colors.indigo.shade50,
                          deleteIcon: const Icon(
                            Icons.cancel,
                            size: 16,
                            color: Colors.indigo,
                          ),
                          onDeleted: () => vm.removeMedication(rx),
                        );
                      }).toList(),
                    ),
                  ],

                  const Divider(height: 24),
                  const Text(
                    'Standard Yellow Form Medications (स्टेशन ५ औषधीहरू):',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: ClinicalConstants.defaultMedications.map((rx) {
                      final isSelected = result.medications.contains(rx);
                      return FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          rx,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
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

                  // Custom prescription text field
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customMedicationController,
                          decoration: const InputDecoration(
                            hintText:
                                'Add custom medication or dosage (थप औषधी)...',
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text(
                          'Add',
                          style: TextStyle(fontSize: 12),
                        ),
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

          // ── 6. SPECIALIZED COUNSELING (Station 5: spec counseling) ──
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.record_voice_over,
                        color: AppTheme.primaryTeal,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Specialized Counseling (स्टेशन ५: विशेष परामर्श)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Cross-check with physical Yellow Form Station 5 (spec counseling) checkboxes:',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        [
                          {
                            'key': 'Weak pelvic floor',
                            'label':
                                'Weak pelvic floor (कमजोर पेल्भिक मांसपेशी)',
                          },
                          {'key': 'POP', 'label': 'POP (पाठेघर खसेको समस्या)'},
                          {
                            'key': 'Stress incontinence',
                            'label':
                                'Stress incontinence (खोक्दा पिसाब चुहिने)',
                          },
                          {
                            'key': 'Urge incontinence',
                            'label': 'Urge incontinence (हतारिने पिसाब)',
                          },
                          {
                            'key': 'Abdominal pain',
                            'label': 'Abdominal pain (तल्लो पेट दुख्ने)',
                          },
                        ].map((topic) {
                          final isSelected = result.counseling.any(
                            (c) =>
                                c.toLowerCase().contains(
                                  topic['key']!.toLowerCase(),
                                ) ||
                                topic['key']!.toLowerCase().contains(
                                  c.toLowerCase(),
                                ),
                          );
                          return FilterChip(
                            label: Text(topic['label']!),
                            selected: isSelected,
                            selectedColor: AppTheme.primaryTeal.withValues(
                              alpha: 0.2,
                            ),
                            checkmarkColor: AppTheme.primaryTeal,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? AppTheme.primaryTeal
                                  : const Color(0xFF334155),
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            onSelected: (_) {
                              vm.toggleCounseling(topic['key']!);
                            },
                          );
                        }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 7. PESSARY FITTING & INSERTION (स्टेशन ५: पेसरी) ───────────
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: result.ringPessary
                    ? AppTheme.primaryTeal
                    : Colors.grey.shade300,
                width: result.ringPessary ? 1.5 : 1.0,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.radio_button_unchecked,
                        color: AppTheme.primaryTeal,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Pessary Fitting & Insertion (पेसरी राखिएको)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                      Switch(
                        value: result.ringPessary,
                        activeThumbColor: AppTheme.primaryTeal,
                        onChanged: (val) {
                          vm.updatePessary(
                            ringPessary: val,
                            pessaryType: val
                                ? (result.pessaryType ?? 'ring')
                                : null,
                            size: val ? (result.ringPessarySize ?? 70) : null,
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Cross-check with Yellow Form Station 5 (pessary) options and size:',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondaryLight,
                    ),
                  ),
                  if (result.ringPessary) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Pessary Type (पेसरीको प्रकार):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          [
                            {'key': 'ring', 'label': 'Ring (सामान्य रिङ्ग)'},
                            {
                              'key': 'ring with support',
                              'label': 'Ring with support (सपोर्ट सहित)',
                            },
                            {
                              'key': 'ring with knob',
                              'label': 'Ring with knob (नब सहित)',
                            },
                          ].map((t) {
                            final currentType = (result.pessaryType ?? 'ring')
                                .toLowerCase();
                            final isSelected =
                                currentType == t['key']!.toLowerCase();
                            return ChoiceChip(
                              label: Text(t['label']!),
                              selected: isSelected,
                              selectedColor: AppTheme.primaryLight,
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? AppTheme.primaryDark
                                    : const Color(0xFF334155),
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 11.5,
                              ),
                              onSelected: (selected) {
                                if (selected) {
                                  vm.updatePessary(
                                    ringPessary: true,
                                    pessaryType: t['key']!,
                                    size: result.ringPessarySize ?? 70,
                                  );
                                }
                              },
                            );
                          }).toList(),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Pessary Size (साइज mm):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [55, 60, 65, 70, 75, 80, 85].map((sz) {
                        final isSelected = result.ringPessarySize == sz;
                        return ChoiceChip(
                          label: Text('${sz}mm'),
                          selected: isSelected,
                          selectedColor: AppTheme.primaryTeal.withValues(
                            alpha: 0.2,
                          ),
                          labelStyle: TextStyle(
                            color: isSelected
                                ? AppTheme.primaryTeal
                                : const Color(0xFF334155),
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              vm.updatePessary(
                                ringPessary: true,
                                pessaryType: result.pessaryType ?? 'ring',
                                size: sz,
                              );
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 140,
                          child: TextFormField(
                            key: ValueKey(
                              'custom_pessary_size_${result.ringPessarySize}',
                            ),
                            initialValue:
                                result.ringPessarySize != null &&
                                    ![
                                      55,
                                      60,
                                      65,
                                      70,
                                      75,
                                      80,
                                      85,
                                    ].contains(result.ringPessarySize)
                                ? '${result.ringPessarySize}'
                                : '',
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Custom mm',
                              hintText: 'e.g. 62',
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                            onChanged: (val) {
                              final sz = int.tryParse(val.trim());
                              if (sz != null && sz > 0) {
                                vm.updatePessary(
                                  ringPessary: true,
                                  pessaryType: result.pessaryType ?? 'ring',
                                  size: sz,
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 8. SURGICAL REFERRAL & FOLLOW-UP DESTINATION ───────────
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.local_hospital,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Surgical Referral & Follow-up (शल्यक्रिया सिफारिस)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Referral Hospital Destination (सिफारिस गरिएको अस्पताल):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      final lookupState = ref.watch(masterLookupProvider);
                      final referralHosps = lookupState.activeReferralHospitals
                          .map((h) => h.labelEn)
                          .where(
                            (h) =>
                                !h.toLowerCase().contains('scheer') &&
                                !h.toLowerCase().contains('model') &&
                                !h.toLowerCase().contains('government') &&
                                !h.toLowerCase().contains('loc') &&
                                h != 'Health Post' &&
                                h != 'GynaeSupport Nurse',
                          )
                          .toList();

                      final items = [
                        {'val': null, 'label': 'None (छैन)'},
                        {'val': 'Scheer Memorial', 'label': 'Scheer Memorial'},
                        {'val': 'Model Hosp', 'label': 'Model Hosp'},
                        {
                          'val': 'loc government',
                          'label': 'Local Government (loc government)',
                        },
                        ...referralHosps.map((h) => {'val': h, 'label': h}),
                      ];

                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: items.map((item) {
                          final val = item['val'];
                          final isSelected =
                              (val == null &&
                                  (result.surgicalReferral == null ||
                                      result.surgicalReferral!.isEmpty)) ||
                              (val != null &&
                                  result.surgicalReferral
                                          ?.toLowerCase()
                                          .contains(
                                            val.toLowerCase().split(' ').first,
                                          ) ==
                                      true);
                          return ChoiceChip(
                            label: Text(item['label']!),
                            selected: isSelected,
                            selectedColor: val == null
                                ? Colors.grey.shade200
                                : Colors.red.shade100,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? (val == null
                                        ? Colors.black87
                                        : Colors.red.shade900)
                                  : const Color(0xFF334155),
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            onSelected: (_) => vm.updateSurgicalReferral(val),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const Divider(height: 20),
                  const Text(
                    'Follow-up Destination (फलो-अप कहाँ गर्ने):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      final lookupState = ref.watch(masterLookupProvider);
                      final referralHosps = lookupState.activeReferralHospitals
                          .map((h) => h.labelEn)
                          .where(
                            (h) =>
                                !h.toLowerCase().contains('scheer') &&
                                !h.toLowerCase().contains('model') &&
                                h != 'Health Post' &&
                                h != 'GynaeSupport Nurse',
                          )
                          .toList();

                      final rawDest = (result.followUpDestination ?? '').trim();
                      final rawDestLow = rawDest.toLowerCase();
                      final isNoFollowUp = rawDestLow == 'no follow up needed';
                      final isHealthPost = rawDestLow == 'health post';
                      final isGynaeNurse = rawDestLow == 'gynaesupport nurse';
                      final isCampFollowUp = rawDestLow == 'camp follow-up day';
                      final isHospital =
                          rawDest.isNotEmpty &&
                          !isNoFollowUp &&
                          !isHealthPost &&
                          !isGynaeNurse &&
                          !isCampFollowUp;

                      final destItems = [
                        {
                          'val': 'No follow up needed',
                          'label': 'No follow up needed (फलो-अप आवश्यक छैन)',
                        },
                        {
                          'val': 'Health Post',
                          'label': 'Health Post (स्वास्थ्य चौकी)',
                        },
                        {
                          'val': 'GynaeSupport Nurse',
                          'label': 'GynaeSupport Nurse (गाइने सपोर्ट नर्स)',
                        },
                        {'val': 'Hospital', 'label': 'Hospital (अस्पताल)'},
                        {
                          'val': 'Camp Follow-up Day',
                          'label': 'Camp Follow-up Day (पुनः शिविर)',
                        },
                      ];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: destItems.map((item) {
                              final val = item['val']!;
                              final isSelected = (val == 'Hospital')
                                  ? isHospital
                                  : (rawDestLow == val.toLowerCase());
                              return ChoiceChip(
                                label: Text(item['label']!),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryTeal.withValues(
                                  alpha: 0.2,
                                ),
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? AppTheme.primaryTeal
                                      : const Color(0xFF334155),
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 11.5,
                                ),
                                onSelected: (_) {
                                  if (val == 'Hospital') {
                                    final currentHosp =
                                        (isHospital && rawDestLow != 'hospital')
                                        ? rawDest
                                        : 'Hospital';
                                    vm.updateFollowUpDestination(currentHosp);
                                  } else {
                                    vm.updateFollowUpDestination(val);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                          if (isHospital) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryTeal.withValues(
                                  alpha: 0.05,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppTheme.primaryTeal.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.local_hospital_rounded,
                                        size: 16,
                                        color: AppTheme.primaryTeal,
                                      ),
                                      const SizedBox(width: 6),
                                      const Expanded(
                                        child: Text(
                                          'Referral / Follow-up Hospital Name (सिफारिस गरिएको अस्पतालको नाम):',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primaryDark,
                                          ),
                                        ),
                                      ),
                                      if (rawDest.isNotEmpty &&
                                          rawDestLow != 'hospital') ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: Colors.green.shade300,
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.check_circle_rounded,
                                                size: 12,
                                                color: Colors.green,
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                'Detected from form',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    key: ValueKey(
                                      'hosp_dest_field_${rawDestLow == 'hospital' ? '' : rawDest}',
                                    ),
                                    initialValue: (rawDestLow == 'hospital')
                                        ? ''
                                        : rawDest,
                                    decoration: InputDecoration(
                                      labelText: 'Hospital Name / Center (अस्पताल वा संस्थाको नाम)',
                                      hintText: 'Enter or edit hospital name (e.g. GANDAKI PROVINCIAL HOSPITAL, Bir Hospital...)',
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: const OutlineInputBorder(),
                                      prefixIcon: const Icon(
                                        Icons.edit_location_alt_rounded,
                                        size: 18,
                                      ),
                                      suffixIcon:
                                          rawDest.isNotEmpty &&
                                              rawDestLow != 'hospital'
                                          ? IconButton(
                                              icon: const Icon(
                                                Icons.clear,
                                                size: 16,
                                              ),
                                              tooltip: 'Clear hospital name',
                                              onPressed: () =>
                                                  vm.updateFollowUpDestination(
                                                    'Hospital',
                                                  ),
                                            )
                                          : null,
                                    ),
                                    onChanged: (val) {
                                      final clean = val.trim();
                                      vm.updateFollowUpDestination(
                                        clean.isNotEmpty ? clean : 'Hospital',
                                      );
                                    },
                                  ),
                                  if (referralHosps.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        const Text(
                                          'Quick Select:',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF64748B),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        ...referralHosps.map((h) {
                                          final isQuickSelected =
                                              rawDestLow == h.toLowerCase();
                                          return ActionChip(
                                            label: Text(h),
                                            backgroundColor: isQuickSelected
                                                ? AppTheme.primaryTeal
                                                      .withValues(alpha: 0.2)
                                                : Colors.white,
                                            labelStyle: TextStyle(
                                              fontSize: 11,
                                              color: isQuickSelected
                                                  ? AppTheme.primaryTeal
                                                  : const Color(0xFF334155),
                                              fontWeight: isQuickSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                            onPressed: () =>
                                                vm.updateFollowUpDestination(h),
                                          );
                                        }),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 9. EXAMINING DOCTOR ASSIGNMENT (जाँच गर्ने चिकित्सक) ───
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color:
                    (result.examiningDoctor != null &&
                        result.examiningDoctor!.isNotEmpty)
                    ? AppTheme.primaryTeal
                    : Colors.amber.shade400,
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.person_pin_rounded,
                        color: AppTheme.primaryTeal,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Examining / Attending Doctor (जाँच गर्ने चिकित्सक)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                      if (result.attendingDoctors.isNotEmpty ||
                          (result.examiningDoctor != null &&
                              result.examiningDoctor!.isNotEmpty))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check,
                                size: 13,
                                color: AppTheme.primaryDark,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${result.attendingDoctors.isNotEmpty ? result.attendingDoctors.length : 1} Selected',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: AppTheme.primaryDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (result.attendingDoctors.isNotEmpty ||
                      (result.examiningDoctor != null &&
                          result.examiningDoctor!.isNotEmpty)) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children:
                          (result.attendingDoctors.isNotEmpty
                                  ? result.attendingDoctors
                                  : [result.examiningDoctor!])
                              .map(
                                (doc) => Chip(
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: AppTheme.primaryLight,
                                  avatar: const Icon(
                                    Icons.check,
                                    size: 13,
                                    color: AppTheme.primaryDark,
                                  ),
                                  label: Text(
                                    doc,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: AppTheme.primaryDark,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ],
                  const SizedBox(height: 6),
                  const Text(
                    'Select clinician(s) who performed Station 2 POP exam & treatment for this patient (multi-select):',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Builder(
                    builder: (context) {
                      final activeCamp = ref.watch(userActiveCampProvider);
                      final List<String> campDoctors =
                          activeCamp?.doctorNames.isNotEmpty == true
                          ? activeCamp!.doctorNames
                          : (activeCamp?.doctorName.trim().isNotEmpty == true
                                ? [activeCamp!.doctorName.trim()]
                                : <String>[]);

                      if (campDoctors.isEmpty) {
                        return const Text(
                          'No doctors assigned to active camp in settings.',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            color: Colors.blueGrey,
                          ),
                        );
                      }

                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: campDoctors.map((doc) {
                          final cleanDoc = doc.toLowerCase().startsWith('dr')
                              ? doc
                              : 'Dr. $doc';
                          final isSelected =
                              result.examiningDoctor == cleanDoc ||
                              result.examiningDoctor == doc ||
                              result.attendingDoctors.contains(cleanDoc) ||
                              result.attendingDoctors.contains(doc) ||
                              _isNameFuzzyMatch(
                                doc,
                                result.attendingDoctors,
                                result.examiningDoctor,
                              );
                          return FilterChip(
                            avatar: CircleAvatar(
                              radius: 12,
                              backgroundColor: isSelected
                                  ? Colors.white
                                  : AppTheme.primaryTeal.withValues(
                                      alpha: 0.15,
                                    ),
                              child: Icon(
                                Icons.medical_services,
                                size: 13,
                                color: isSelected
                                    ? AppTheme.primaryTeal
                                    : Colors.blueGrey,
                              ),
                            ),
                            label: Text(
                              cleanDoc,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: AppTheme.primaryTeal.withValues(
                              alpha: 0.2,
                            ),
                            checkmarkColor: AppTheme.primaryTeal,
                            onSelected: (selected) {
                              vm.toggleAttendingDoctor(cleanDoc);
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 10. ATTENDING NURSE ASSIGNMENT (सेवा दिने नर्स) ───
          if (ref.watch(userActiveCampProvider)?.showNurseOnForms ?? false) ...[
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color:
                    (result.attendingNurses.isNotEmpty ||
                        (result.examiningNurse != null &&
                            result.examiningNurse!.isNotEmpty))
                    ? const Color(0xFF81005D)
                    : Colors.pink.shade200,
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.badge_outlined,
                        color: Color(0xFF81005D),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Attending Nurse (सेवा दिने नर्स)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: Color(0xFF81005D),
                          ),
                        ),
                      ),
                      if (result.attendingNurses.isNotEmpty ||
                          (result.examiningNurse != null &&
                              result.examiningNurse!.isNotEmpty))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCE7F3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check,
                                size: 13,
                                color: Color(0xFF81005D),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${result.attendingNurses.isNotEmpty ? result.attendingNurses.length : 1} Selected',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: Color(0xFF81005D),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (result.attendingNurses.isNotEmpty ||
                      (result.examiningNurse != null &&
                          result.examiningNurse!.isNotEmpty)) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children:
                          (result.attendingNurses.isNotEmpty
                                  ? result.attendingNurses
                                  : [result.examiningNurse!])
                              .map(
                                (nurse) => Chip(
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: const Color(0xFFFCE7F3),
                                  avatar: const Icon(
                                    Icons.check,
                                    size: 13,
                                    color: Color(0xFF81005D),
                                  ),
                                  label: Text(
                                    nurse,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Color(0xFF81005D),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ],
                  const SizedBox(height: 6),
                  const Text(
                    'Select nurse(s) who assisted Station 2 examination or provided care (multi-select):',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Builder(
                    builder: (context) {
                      final activeCamp = ref.watch(userActiveCampProvider);
                      final List<NurseProfile> campNurses =
                          activeCamp?.nurseProfiles ?? <NurseProfile>[];

                      if (campNurses.isEmpty) {
                        return const Text(
                          'No nurses assigned to active camp in settings.',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            color: Colors.blueGrey,
                          ),
                        );
                      }

                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: campNurses.map((nurse) {
                          final cleanNurse = nurse.displayName;
                          final isSelected =
                              result.attendingNurses.contains(cleanNurse) ||
                              result.attendingNurses.contains(nurse.name) ||
                              _isNameFuzzyMatch(
                                nurse.name,
                                result.attendingNurses,
                                result.examiningNurse,
                              );
                          return FilterChip(
                            avatar: CircleAvatar(
                              radius: 12,
                              backgroundColor: isSelected
                                  ? Colors.white
                                  : const Color(0xFF81005D)
                                        .withValues(alpha: 0.15),
                              child: Icon(
                                Icons.person,
                                size: 13,
                                color: isSelected
                                    ? const Color(0xFF81005D)
                                    : Colors.pink.shade700,
                              ),
                            ),
                            label: Text(
                              nurse.formattedLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: const Color(0xFFFCE7F3),
                            checkmarkColor: const Color(0xFF81005D),
                            onSelected: (selected) {
                              vm.toggleAttendingNurse(cleanNurse);
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ],
          // ── 11. CLINICAL NOTES & OUTTAKE REMARKS ───
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOcrSectionHeader(
                    icon: Icons.note_alt_outlined,
                    iconColor: AppTheme.primaryTeal,
                    title: 'Clinical Notes & Outtake Remarks (क्लिनिकल कैफियत / टिप्पणी)',
                    titleStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: AppTheme.primaryDark,
                    ),
                    dateChip: _buildStationDateChip(
                      context: context,
                      field: 'outtakeDate',
                      label: 'Outtake Date',
                      dateStr: result.outtakeDate,
                      onDateSelected: (d) =>
                          vm.updateStationDate('outtakeDate', d),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Handwritten clinical advice, counseling, or remarks from Station 6:',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    key: ValueKey(
                      'clinical_notes_${result.scannedAt.millisecondsSinceEpoch}',
                    ),
                    initialValue: result.clinicalNotes ?? '',
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Enter clinical advice, counselling notes, or outtake remarks written on form...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) => vm.updateClinicalNotes(val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
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
      {
        'key': 'firstName',
        'label': 'First Name',
        'section': 'Demographics',
        'tabIndex': 0,
        'value': demo['firstName']?.toString() ?? '—',
        'confKey': 'name',
      },
      {
        'key': 'surname',
        'label': 'Surname',
        'section': 'Demographics',
        'tabIndex': 0,
        'value': demo['surname']?.toString() ?? '—',
        'confKey': 'name',
      },
      {
        'key': 'age',
        'label': 'Patient Age',
        'section': 'Demographics',
        'tabIndex': 0,
        'value': demo['age']?.toString() ?? '—',
        'confKey': 'age',
      },
      {
        'key': 'maritalStatus',
        'label': 'Marital Status',
        'section': 'Demographics',
        'tabIndex': 0,
        'value': demo['maritalStatus']?.toString() ?? '—',
        'confKey': 'maritalStatus',
      },
      {
        'key': 'relativeName',
        'label': 'Husband / Father',
        'section': 'Demographics',
        'tabIndex': 0,
        'value': demo['relativeName']?.toString() ?? '—',
        'confKey': 'relative',
      },
      {
        'key': 'mobile',
        'label': 'Mobile No.',
        'section': 'Demographics',
        'tabIndex': 0,
        'value': demo['mobile']?.toString() ?? '—',
        'confKey': 'mobile',
      },
      {
        'key': 'contactPerson',
        'label': 'Contact Person',
        'section': 'Demographics',
        'tabIndex': 0,
        'value': demo['contactPerson']?.toString() ?? '—',
        'confKey': 'contactPerson',
      },
      {
        'key': 'contactMobile',
        'label': 'Contact Mobile',
        'section': 'Demographics',
        'tabIndex': 0,
        'value': demo['contactMobile']?.toString() ?? '—',
        'confKey': 'contactMobile',
      },
      {
        'key': 'maritalAge',
        'label': 'Age at Marriage',
        'section': 'Demographics',
        'tabIndex': 0,
        'value': demo['maritalAge']?.toString() ?? '—',
        'confKey': 'maritalAge',
      },
      {
        'key': 'province',
        'label': 'Province',
        'section': 'Demographics',
        'tabIndex': 0,
        'value': demo['province']?.toString() ?? '—',
        'confKey': 'location',
      },
      {
        'key': 'district',
        'label': 'District',
        'section': 'Demographics',
        'tabIndex': 0,
        'value': demo['district']?.toString() ?? '—',
        'confKey': 'location',
      },
      {
        'key': 'municipality',
        'label': 'Palika / Municipality',
        'section': 'Demographics',
        'tabIndex': 0,
        'value': demo['municipality']?.toString() ?? '—',
        'confKey': 'location',
      },
      {
        'key': 'ward',
        'label': 'Ward No.',
        'section': 'Demographics',
        'tabIndex': 0,
        'value': demo['ward']?.toString() ?? '—',
        'confKey': 'ward',
      },
      {
        'key': 'consentTreatment',
        'label': 'Consent: Treatment',
        'section': 'Demographics',
        'tabIndex': 0,
        'value': (demo['consentTreatment'] as bool?) == false ? 'No' : 'Yes',
        'confKey': 'consent',
      },
      {
        'key': 'consentStoreMedicalInfo',
        'label': 'Consent: Store Info',
        'section': 'Demographics',
        'tabIndex': 0,
        'value': (demo['consentStoreMedicalInfo'] as bool?) == false
            ? 'No'
            : 'Yes',
        'confKey': 'consent',
      },
      // ── Obstetrics ────────────────────────────────────────
      {
        'key': 'deliveries',
        'label': 'Deliveries (P)',
        'section': 'Obstetrics',
        'tabIndex': 1,
        'value': obs['deliveries']?.toString() ?? '—',
        'confKey': 'obstetrics',
      },
      {
        'key': 'livingChildren',
        'label': 'Living Children',
        'section': 'Obstetrics',
        'tabIndex': 1,
        'value': obs['livingChildren']?.toString() ?? '—',
        'confKey': 'obstetrics',
      },
      {
        'key': 'abortions',
        'label': 'Abortions',
        'section': 'Obstetrics',
        'tabIndex': 1,
        'value': obs['abortions']?.toString() ?? '—',
        'confKey': 'obstetrics',
      },
      // ── Visit Reasons ─────────────────────────────────────
      {
        'key': 'reasonsForVisit',
        'label': 'Reasons for Visit',
        'section': 'Visit Reasons',
        'tabIndex': 1,
        'value': (demo['reasonsForVisit'] as List?)?.join(', ') ?? '—',
        'confKey': 'reasonsForVisit',
      },
      // ── POP & Physical Examination ────────────────────────
      {
        'key': 'anteriorStage',
        'label': 'POP anterior wall',
        'section': 'POP Exam',
        'tabIndex': 2,
        'value': pop['anteriorStage']?.toString() ?? '—',
        'confKey': 'popStaging',
      },
      {
        'key': 'middleStage',
        'label': 'POP middle part',
        'section': 'POP Exam',
        'tabIndex': 2,
        'value': pop['middleStage']?.toString() ?? '—',
        'confKey': 'popStaging',
      },
      {
        'key': 'posteriorStage',
        'label': 'POP posterior wall',
        'section': 'POP Exam',
        'tabIndex': 2,
        'value': pop['posteriorStage']?.toString() ?? '—',
        'confKey': 'popStaging',
      },
      {
        'key': 'uterusInside',
        'label': 'Uterus Inside',
        'section': 'POP Exam',
        'tabIndex': 2,
        'value': (pop['uterusInside'] as bool?) == true ? 'Yes' : 'No',
        'confKey': 'popStaging',
      },
      {
        'key': 'pelvicTone',
        'label': 'Pelvic Floor Muscle',
        'section': 'POP Exam',
        'tabIndex': 2,
        'value': pop['pelvicFloorTone']?.toString() ?? '—',
        'confKey': 'popStaging',
      },
      {
        'key': 'vulvaRemarks',
        'label': 'Vulva Appearance',
        'section': 'POP Exam',
        'tabIndex': 2,
        'value': pop['vulvaRemarks']?.toString() ?? 'Normal',
        'confKey': 'popStaging',
      },
      {
        'key': 'vaginaRemarks',
        'label': 'Vagina Exam',
        'section': 'POP Exam',
        'tabIndex': 2,
        'value': pop['vaginaRemarks']?.toString() ?? 'Normal',
        'confKey': 'popStaging',
      },
      {
        'key': 'cervixRemarks',
        'label': 'Cervix Appearance',
        'section': 'POP Exam',
        'tabIndex': 2,
        'value': pop['cervixRemarks']?.toString() ?? 'Normal / Smooth',
        'confKey': 'popStaging',
      },
      {
        'key': 'uterusRemarks',
        'label': 'Uterus Exam',
        'section': 'POP Exam',
        'tabIndex': 2,
        'value': pop['uterusRemarks']?.toString() ?? 'Normal size',
        'confKey': 'popStaging',
      },
      {
        'key': 'examDate',
        'label': 'Examination Date',
        'section': 'POP Exam',
        'tabIndex': 2,
        'value': result.examDate ?? '—',
        'confKey': 'date',
      },
      // ── Vitals ────────────────────────────────────────────
      {
        'key': 'bp',
        'label': 'Blood Pressure',
        'section': 'Vitals',
        'tabIndex': 3,
        'value':
            '${vitals['systolicBp'] ?? '—'}/${vitals['diastolicBp'] ?? '—'} mmHg',
        'confKey': 'bp',
      },
      {
        'key': 'pulse',
        'label': 'Pulse Rate',
        'section': 'Vitals',
        'tabIndex': 3,
        'value': '${vitals['pulseRate'] ?? '—'} bpm',
        'confKey': 'pulse',
      },
      {
        'key': 'spo2',
        'label': 'SpO2',
        'section': 'Vitals',
        'tabIndex': 3,
        'value': '${vitals['spo2'] ?? '—'}%',
        'confKey': 'spo2',
      },
      {
        'key': 'glucose',
        'label': 'Blood Glucose',
        'section': 'Vitals',
        'tabIndex': 3,
        'value': '${vitals['bloodGlucose'] ?? '—'} mg/dL',
        'confKey': 'glucose',
      },
      {
        'key': 'urineTest',
        'label': 'Urine Test',
        'section': 'Vitals',
        'tabIndex': 3,
        'value': vitals['urineTest']?.toString() ?? '—',
        'confKey': 'labs',
      },
      {
        'key': 'pregnancyTest',
        'label': 'Pregnancy Test',
        'section': 'Vitals',
        'tabIndex': 3,
        'value': vitals['pregnancyTest']?.toString() ?? '—',
        'confKey': 'labs',
      },
      // ── Diagnoses & Treatment ─────────────────────────────
      {
        'key': 'diagnoses',
        'label': 'Diagnoses',
        'section': 'Treatment Plan',
        'tabIndex': 3,
        'value': result.diagnoses.isEmpty ? '—' : result.diagnoses.join(', '),
        'confKey': 'diagnoses',
      },
      {
        'key': 'counseling',
        'label': 'Spec Counseling',
        'section': 'Treatment Plan',
        'tabIndex': 3,
        'value': result.counseling.isEmpty
            ? 'None'
            : result.counseling.join(', '),
        'confKey': 'diagnoses',
      },
      {
        'key': 'ringPessary',
        'label': 'Pessary Fitting',
        'section': 'Treatment Plan',
        'tabIndex': 3,
        'value': result.ringPessary
            ? '${result.pessaryType ?? "Ring"} (${result.ringPessarySize != null ? "${result.ringPessarySize}mm" : "Fitted"})'
            : 'None',
        'confKey': 'diagnoses',
      },
      {
        'key': 'medications',
        'label': 'Medications',
        'section': 'Treatment Plan',
        'tabIndex': 3,
        'value': result.medications.isEmpty
            ? '—'
            : result.medications.join(', '),
        'confKey': 'medications',
      },
      {
        'key': 'referral',
        'label': 'Surgical Referral',
        'section': 'Treatment Plan',
        'tabIndex': 3,
        'value': result.surgicalReferral ?? 'None',
        'confKey': 'diagnoses',
      },
      {
        'key': 'followUp',
        'label': 'Follow-up',
        'section': 'Treatment Plan',
        'tabIndex': 3,
        'value': result.followUpDestination ?? '—',
        'confKey': 'diagnoses',
      },
      {
        'key': 'intakeDate',
        'label': 'Registration Date',
        'section': 'Demographics',
        'tabIndex': 0,
        'value':
            result.intakeDate ??
            demo['intakeDate']?.toString() ??
            demo['date']?.toString() ??
            '—',
        'confKey': 'date',
      },
      {
        'key': 'anamnesisDate',
        'label': 'Anamnesis Date',
        'section': 'Obstetric History',
        'tabIndex': 1,
        'value':
            result.effectiveAnamnesisDate ??
            result.anamnesisDate ??
            result.demographics['anamnesisDate']?.toString() ??
            result.intakeDate ??
            demo['intakeDate']?.toString() ??
            demo['date']?.toString() ??
            '—',
        'confKey': 'date',
      },
      {
        'key': 'treatmentLevel',
        'label': 'Consultation',
        'section': 'Demographics',
        'tabIndex': 0,
        'value':
            (result.treatmentLevel == 'counseling' ||
                result.treatmentLevel == 'council_level')
            ? 'Counseling (काउन्सिलिङ तह)'
            : ((result.treatmentLevel == 'gyno_checkup' ||
                      result.treatmentLevel == 'full_check_up')
                  ? 'Gynocheckup (गाइनो जाँच)'
                  : 'Unassigned'),
        'confKey': 'treatmentLevel',
      },
      {
        'key': 'examiningDoctor',
        'label': 'Examining Doctor',
        'section': 'Signatures',
        'tabIndex': 3,
        'value': result.examiningDoctor ?? 'Unassigned',
        'confKey': 'diagnoses',
      },
      if (ref.watch(userActiveCampProvider)?.showNurseOnForms ?? false)
        {
          'key': 'attendingNurse',
          'label': 'Attending Nurse',
          'section': 'Signatures',
          'tabIndex': 3,
          'value': result.attendingNurses.isNotEmpty
              ? result.attendingNurses.join(', ')
              : (result.examiningNurse ?? 'Unassigned'),
          'confKey': 'diagnoses',
        },
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
                        color: reviewed == 0
                            ? Colors.grey.shade700
                            : AppTheme.primaryDark,
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
                  label: const Text(
                    'Reset All',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade600,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
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
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 14,
                        color: AppTheme.primaryTeal,
                        margin: const EdgeInsets.only(right: 8),
                      ),
                      Text(
                        section.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryTeal,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final f in sections[section]!) ...[
                  Builder(
                    builder: (context) {
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              // Label + value
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          f['label'] as String,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.primaryDark,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: confBg(confKey),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            confLabel(confKey),
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: confColor(confKey),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      f['value'] as String,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        color: (f['value'] as String) == '—'
                                            ? Colors.grey.shade400
                                            : AppTheme.primaryDark,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),

                              // ✅ / ❌ buttons + Edit link
                              const SizedBox(width: 8),
                              if (verified == false)
                                TextButton.icon(
                                  onPressed: () =>
                                      _tabController.animateTo(tabIdx),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 13,
                                  ),
                                  label: const Text(
                                    'Edit',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red.shade700,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              _verifyButton(
                                icon: Icons.check_circle_outline,
                                color: Colors.green.shade600,
                                activeColor: Colors.green,
                                isActive: verified == true,
                                tooltip: 'Correct — OCR matched',
                                onTap: () => setState(
                                  () => _verifyMap[key] =
                                      _verifyMap[key] == true ? null : true,
                                ),
                              ),
                              const SizedBox(width: 4),
                              _verifyButton(
                                icon: Icons.cancel_outlined,
                                color: Colors.red.shade400,
                                activeColor: Colors.red,
                                isActive: verified == false,
                                tooltip: 'Wrong — OCR missed or incorrect',
                                onTap: () => setState(
                                  () => _verifyMap[key] =
                                      _verifyMap[key] == false ? null : false,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
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
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isActive
                ? activeColor.withValues(alpha: 0.12)
                : Colors.transparent,
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
        labelStyle: const TextStyle(fontSize: 12.5),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tier,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
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
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondaryLight,
                ),
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
                icon: const Icon(
                  Icons.remove,
                  size: 18,
                  color: Colors.blueGrey,
                ),
                onPressed: value > 0 ? () => onChanged(value - 1) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryDark,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.add,
                  size: 18,
                  color: AppTheme.primaryTeal,
                ),
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
    final int effectiveMax = value > maxStage ? value : maxStage;
    final int safeValue = value < 0
        ? 0
        : (value > effectiveMax ? effectiveMax : value);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
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

  bool _isNameFuzzyMatch(
    String campStaffName,
    List<String> detectedStaffList,
    String? primaryDetected,
  ) {
    final targets = <String>[
      ...detectedStaffList,
      if (primaryDetected != null && primaryDetected.trim().isNotEmpty)
        primaryDetected,
    ];
    if (targets.isEmpty) return false;

    String clean(String s) {
      return s
          .toLowerCase()
          .replaceAll(
            RegExp(
              r'\b(dr|dr\.|doctor|sister|sr|sr\.|nurse|staff\s*nurse)\b',
              caseSensitive: false,
            ),
            '',
          )
          .replaceAll(RegExp(r'[^a-z0-9]'), '')
          .trim();
    }

    final staffClean = clean(campStaffName);
    if (staffClean.isEmpty) return false;

    for (final rawTarget in targets) {
      final targetClean = clean(rawTarget);
      if (targetClean.isEmpty) continue;
      if (staffClean == targetClean) return true;
      if (staffClean.contains(targetClean) ||
          targetClean.contains(staffClean)) {
        if (targetClean.length >= 3 && staffClean.length >= 3) return true;
      }
      final staffTokens = campStaffName
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .map(clean)
          .where((t) => t.length >= 3)
          .toList();
      final targetTokens = rawTarget
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .map(clean)
          .where((t) => t.length >= 3)
          .toList();
      for (final st in staffTokens) {
        for (final tt in targetTokens) {
          if (st == tt ||
              (st.length >= 4 && (st.contains(tt) || tt.contains(st)))) {
            return true;
          }
        }
      }
    }
    return false;
  }

  Widget _buildOcrSectionHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    required TextStyle titleStyle,
    required Widget dateChip,
    Widget? extraChip,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 560;
        final titleRow = Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: titleStyle)),
          ],
        );

        final chipsRow = Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [dateChip, ?extraChip],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titleRow, const SizedBox(height: 8), chipsRow],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleRow),
            const SizedBox(width: 10),
            chipsRow,
          ],
        );
      },
    );
  }

  Widget _buildStationDateChip({
    required BuildContext context,
    required String label,
    required String? dateStr,
    required ValueChanged<String?> onDateSelected,
    String? field,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        _showStationDateEditorDialog(
          context: context,
          label: label,
          dateStr: dateStr,
          field: field,
          onDateSelected: onDateSelected,
        );
      },
      child: Chip(
        visualDensity: VisualDensity.compact,
        backgroundColor: (dateStr != null && dateStr.isNotEmpty)
            ? AppTheme.primaryLight
            : Colors.grey.shade100,
        avatar: Icon(
          Icons.event_note,
          size: 14,
          color: (dateStr != null && dateStr.isNotEmpty)
              ? AppTheme.primaryTeal
              : Colors.blueGrey,
        ),
        label: Text(
          dateStr != null && dateStr.isNotEmpty
              ? '$label: ${dateStr.replaceAll(RegExp(r'\s*BS', caseSensitive: false), '').trim()} BS'
              : '$label: Set Date',
          style: TextStyle(
            fontSize: 11,
            fontWeight: (dateStr != null && dateStr.isNotEmpty)
                ? FontWeight.bold
                : FontWeight.normal,
            color: (dateStr != null && dateStr.isNotEmpty)
                ? AppTheme.primaryTeal
                : Colors.blueGrey,
          ),
        ),
      ),
    );
  }

  void _showStationDateEditorDialog({
    required BuildContext context,
    required String label,
    required String? dateStr,
    required ValueChanged<String?> onDateSelected,
    String? field,
  }) {
    // Parse initial date components
    final todayNp = NepaliDateHelper.toNepali(DateTime.now());
    int selectedYear = todayNp.year;
    int selectedMonth = todayNp.month;
    int selectedDay = todayNp.day;

    final cleanStr = (dateStr ?? '')
        .replaceAll(RegExp(r'\s*BS', caseSensitive: false), '')
        .trim();
    if (cleanStr.isNotEmpty) {
      final parts = cleanStr.split(RegExp(r'[-/]'));
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) {
          selectedYear = y;
          selectedMonth = m.clamp(1, 12);
          selectedDay = d.clamp(1, 32);
        }
      }
    }

    final textController = TextEditingController(
      text:
          '${selectedYear.toString().padLeft(4, '0')}-${selectedMonth.toString().padLeft(2, '0')}-${selectedDay.toString().padLeft(2, '0')}',
    );

    // Only modify the edited station by default so distinct station dates are preserved.
    bool applyToAll = false;

    showDialog(
      context: context,
      builder: (dlgContext) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            void updateFromComponents(int y, int m, int d) {
              setDlgState(() {
                selectedYear = y;
                selectedMonth = m;
                selectedDay = d;
                textController.text =
                    '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
              });
            }

            void updateFromText(String val) {
              final clean = val
                  .replaceAll(RegExp(r'\s*BS', caseSensitive: false), '')
                  .trim();
              final parts = clean.split(RegExp(r'[-/]'));
              if (parts.length == 3) {
                final y = int.tryParse(parts[0]);
                final m = int.tryParse(parts[1]);
                final d = int.tryParse(parts[2]);
                if (y != null &&
                    m != null &&
                    d != null &&
                    m >= 1 &&
                    m <= 12 &&
                    d >= 1 &&
                    d <= 32) {
                  setDlgState(() {
                    selectedYear = y;
                    selectedMonth = m;
                    selectedDay = d;
                  });
                }
              }
            }

            // Calculate dual calendar representation
            String dualPreview = '';
            if (selectedYear >= 2070 && selectedYear <= 2120) {
              try {
                final safeDay = selectedDay > 30 ? 30 : selectedDay;
                final nepaliDt = NepaliDateTime(
                  selectedYear,
                  selectedMonth,
                  safeDay,
                );
                final engDt = NepaliDateHelper.toEnglish(nepaliDt);
                final nepMonthName = (selectedMonth >= 1 && selectedMonth <= 12)
                    ? NepaliDateHelper.nepaliMonthPureNp[selectedMonth - 1]
                    : '';
                dualPreview =
                    '🇳🇵 वि.सं. $selectedYear $nepMonthName ${selectedDay.toString().padLeft(2, '0')}  •  🌍 ${engDt.year}-${engDt.month.toString().padLeft(2, '0')}-${engDt.day.toString().padLeft(2, '0')} AD';
              } catch (_) {
                dualPreview =
                    '🇳🇵 Bikram Sambat: $selectedYear-${selectedMonth.toString().padLeft(2, '0')}-${selectedDay.toString().padLeft(2, '0')} BS';
              }
            } else {
              try {
                final safeDay = selectedDay > 28 ? 28 : selectedDay;
                final engDt = DateTime(selectedYear, selectedMonth, safeDay);
                final nepDt = NepaliDateHelper.toNepali(engDt);
                dualPreview =
                    '🌍 $selectedYear-${selectedMonth.toString().padLeft(2, '0')}-${selectedDay.toString().padLeft(2, '0')} AD  •  🇳🇵 वि.सं. ${nepDt.year}-${nepDt.month.toString().padLeft(2, '0')}-${nepDt.day.toString().padLeft(2, '0')} BS';
              } catch (_) {
                dualPreview =
                    '$selectedYear-${selectedMonth.toString().padLeft(2, '0')}-${selectedDay.toString().padLeft(2, '0')}';
              }
            }

            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 24.0,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.edit_calendar_rounded,
                      color: AppTheme.primaryTeal,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit $label',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                        const Text(
                          'फाराम मिति संशोधन (Bikram Sambat BS / AD)',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Dual Preview Card
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF86EFAC),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CURRENT CALENDAR EQUIVALENT / मिति मिलान:',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF15803D),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dualPreview,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF166534),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Manual Text Field
                    const Text(
                      'Direct Date Entry (मिति सिधै प्रविष्ट गर्नुहोस्):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: textController,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: Color(0xFF0F172A),
                      ),
                      decoration: InputDecoration(
                        hintText: 'YYYY-MM-DD (e.g. 2083-07-06)',
                        prefixIcon: const Icon(
                          Icons.event,
                          size: 20,
                          color: AppTheme.primaryTeal,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.check_circle_outline,
                            color: AppTheme.primaryTeal,
                          ),
                          tooltip: 'Apply typed date',
                          onPressed: () => updateFromText(textController.text),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onChanged: updateFromText,
                    ),
                    const SizedBox(height: 16),

                    // Dropdown Selectors
                    const Text(
                      'Quick Bikram Sambat (BS) Selectors (वि.सं. छनौट):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Month on its own row so full name is clearly visible
                    DropdownButtonFormField<int>(
                      initialValue: (selectedMonth >= 1 && selectedMonth <= 12)
                          ? selectedMonth
                          : 7,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Month / महिना (Bikram Sambat)',
                        labelStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryTeal,
                        ),
                        prefixIcon: const Icon(
                          Icons.calendar_month_rounded,
                          size: 20,
                          color: AppTheme.primaryTeal,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 1,
                          child: Text(
                            '01 - बैशाख (Baisakh)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 2,
                          child: Text(
                            '02 - जेठ (Jestha)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 3,
                          child: Text(
                            '03 - असार (Ashadh)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 4,
                          child: Text(
                            '04 - श्रावण (Shrawan)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 5,
                          child: Text(
                            '05 - भाद्र (Bhadra)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 6,
                          child: Text(
                            '06 - असोज (Ashwin)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 7,
                          child: Text(
                            '07 - कार्तिक (Kartik)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 8,
                          child: Text(
                            '08 - मंसिर (Mangsir)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 9,
                          child: Text(
                            '09 - पौष (Poush)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 10,
                          child: Text(
                            '10 - माघ (Magh)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 11,
                          child: Text(
                            '11 - फाल्गुन (Falgun)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 12,
                          child: Text(
                            '12 - चैत्र (Chaitra)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (m) {
                        if (m != null) {
                          updateFromComponents(selectedYear, m, selectedDay);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    // Year & Day side-by-side with equal width
                    Row(
                      children: [
                        // Year
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue:
                                (selectedYear >= 2075 && selectedYear <= 2090)
                                ? selectedYear
                                : 2083,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Year / वर्ष (BS)',
                              labelStyle: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            items: [
                              for (int y = 2078; y <= 2090; y++)
                                DropdownMenuItem(
                                  value: y,
                                  child: Text(
                                    '$y',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                            onChanged: (y) {
                              if (y != null) {
                                updateFromComponents(
                                  y,
                                  selectedMonth,
                                  selectedDay,
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Day
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue:
                                (selectedDay >= 1 && selectedDay <= 32)
                                ? selectedDay
                                : 6,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Day / गते',
                              labelStyle: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            items: [
                              for (int d = 1; d <= 32; d++)
                                DropdownMenuItem(
                                  value: d,
                                  child: Text(
                                    'गते ${d.toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                            onChanged: (d) {
                              if (d != null) {
                                updateFromComponents(
                                  selectedYear,
                                  selectedMonth,
                                  d,
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Apply to all stations checkbox
                    Material(
                      color: const Color(0xFFF8FAFC),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: applyToAll,
                          activeColor: AppTheme.primaryTeal,
                          title: const Text(
                            'Apply to all 6 stations (सबै ६ वटै स्टेशनहरूमा यो मिति मिलाउनुहोस्)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryDark,
                            ),
                          ),
                          subtitle: const Text(
                            'Syncs Intake, Exam, Lab, Conclusion, Treatment, & Outtake dates',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppTheme.textSecondaryLight,
                            ),
                          ),
                          onChanged: (val) {
                            setDlgState(() => applyToAll = val ?? true);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dlgContext),
                  child: const Text('Cancel (रद्द)'),
                ),
                TextButton(
                  onPressed: () {
                    if (applyToAll) {
                      ref
                          .read(ocrScanProvider.notifier)
                          .syncAllStationDates(null);
                    } else {
                      onDateSelected(null);
                    }
                    Navigator.pop(dlgContext);
                  },
                  child: const Text(
                    'Clear Date (हटाउनुहोस्)',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 16),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    final finalFormatted = textController.text.trim();
                    if (applyToAll) {
                      ref
                          .read(ocrScanProvider.notifier)
                          .syncAllStationDates(finalFormatted);
                    } else {
                      onDateSelected(finalFormatted);
                    }
                    Navigator.pop(dlgContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Date updated to $finalFormatted (${applyToAll ? "Synchronized to all 6 stations" : label})',
                        ),
                        backgroundColor: AppTheme.successGreen,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  label: const Text('Save Date (सुरक्षित गर्नुहोस्)'),
                ),
              ],
            );
          },
        );
      },
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
            Flexible(
              child: Text('Scan Committed!', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The photographed Yellow Form was verified and committed to the camp database:',
            ),
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
                  Text(
                    'Patient ID:\n${patient.patientId}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Name: ${patient.fullName}',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
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
