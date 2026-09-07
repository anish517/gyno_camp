import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
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
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Header Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryTeal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_stories, color: AppTheme.primaryTeal, size: 16),
                    SizedBox(width: 6),
                    Text(
                      '2-PAGE MEDICAL YELLOW FORM DIGITIZATION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: AppTheme.primaryTeal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Scan & Auto-Fill Yellow Form',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Capture both Page 1 (Front: Demographics) and Page 2 (Back: POP & Treatment).\nThe OCR engine will automatically merge both sides into one complete clinical intake.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: AppTheme.textSecondaryLight),
              ),
              const SizedBox(height: 24),

              // Dual-Slot Cards (Side-by-Side or Column)
              LayoutBuilder(
                builder: (context, box) {
                  final isWide = box.maxWidth >= 600;
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
                    onSample: () => ocrVm.loadSample('page1'),
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
                    onSample: () => ocrVm.loadSample('page2'),
                    onClear: () => ocrVm.clearSlot(2),
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: slot1),
                        const SizedBox(width: 16),
                        Expanded(child: slot2),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        slot1,
                        const SizedBox(height: 14),
                        slot2,
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 20),

              // Multi-File Quick Action & Primary Proceed Action
              if (ocrState.hasPage1 || ocrState.hasPage2) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.fact_check_outlined, size: 22),
                    label: Text(
                      ocrState.isDualReady
                          ? 'Review & Verify Dual-Page Form (दुवै पाना रुजु गर्नुहोस्)'
                          : 'Proceed with Captured Page(s) (रुजु गर्नुहोस्)',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => ocrVm.mergeAndProceed(),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Quick Actions Bar
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Select Both Images at Once (Multi-Select)'),
                    onPressed: () => ocrVm.pickBothPages(),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.description, size: 18),
                    label: const Text('Load Complete 2-Page Template'),
                    onPressed: () => ocrVm.loadSample('full'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
    required VoidCallback onSample,
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
        padding: const EdgeInsets.all(16.0),
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
                        radius: 13,
                        backgroundColor: isCaptured ? AppTheme.primaryTeal : Colors.grey.shade400,
                        child: Text('$pageNumber', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (isCaptured)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.successGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 14, color: AppTheme.successGreen),
                        SizedBox(width: 4),
                        Text('Captured', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.successGreen)),
                      ],
                    ),
                  )
                else
                  Text('Slot $pageNumber Empty', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondaryLight)),
            const SizedBox(height: 12),

            // If captured, show summary & clear button
            if (isCaptured && summaryText != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check, size: 16, color: AppTheme.primaryTeal),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        summaryText,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: onClear,
                      child: const Icon(Icons.close, size: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: Size.zero,
                    ),
                    icon: const Icon(Icons.camera_alt, size: 15),
                    label: const Text('Camera', style: TextStyle(fontSize: 11.5)),
                    onPressed: onCamera,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: Size.zero,
                    ),
                    icon: const Icon(Icons.photo, size: 15),
                    label: const Text('File', style: TextStyle(fontSize: 11.5)),
                    onPressed: onGallery,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Load Sample $pageNumber',
                  icon: const Icon(Icons.auto_fix_high, size: 18, color: AppTheme.primaryTeal),
                  onPressed: onSample,
                ),
              ],
            ),
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
        // Top Confidence & Warning Alert
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppTheme.primaryLight.withValues(alpha: 0.4),
          child: Row(
            children: [
              const Icon(Icons.verified_user, color: AppTheme.primaryTeal, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Review Extracted Data (${(result.overallConfidence * 100).toInt()}% Confidence). Cross-check before saving.',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryDark),
                ),
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
          ],
        ),

        // Tab Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDemographicsTab(result, ocrVm),
              _buildObstetricsTab(result, ocrVm),
              _buildPopStagingTab(result, ocrVm),
              _buildVitalsAndDiagnosesTab(result, ocrVm),
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
  Widget _buildDemographicsTab(OcrScanResultModel result, OcrScanViewModel vm) {
    final demo = result.demographics;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldWithConfidence(
            label: 'First Name (नाम)',
            value: demo['firstName']?.toString() ?? '',
            fieldKey: 'name',
            result: result,
            onChanged: (val) => vm.updateDemographic('firstName', val),
          ),
          const SizedBox(height: 12),
          _buildFieldWithConfidence(
            label: 'Surname (थर)',
            value: demo['surname']?.toString() ?? '',
            fieldKey: 'name',
            result: result,
            onChanged: (val) => vm.updateDemographic('surname', val),
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
                  onChanged: (val) => vm.updateDemographic('age', int.tryParse(val) ?? 35),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFieldWithConfidence(
                  label: 'Ward Number (वडा नं)',
                  value: demo['ward']?.toString() ?? '03',
                  fieldKey: 'ward',
                  result: result,
                  onChanged: (val) => vm.updateDemographic('ward', val),
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
            onChanged: (val) => vm.updateDemographic('mobile', val),
          ),
          const SizedBox(height: 12),
          _buildFieldWithConfidence(
            label: 'Husband / Father Name (श्रीमानको / बुबाको नाम)',
            value: demo['relativeName']?.toString() ?? '',
            fieldKey: 'relative',
            result: result,
            onChanged: (val) => vm.updateDemographic('relativeName', val),
          ),
          const SizedBox(height: 16),
          const Text('Primary Reasons for Visit (शिविरमा आउनुको कारण):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (demo['reasonsForVisit'] as List? ?? []).map((reason) {
              return Chip(
                avatar: const Icon(Icons.check, size: 16, color: AppTheme.primaryTeal),
                label: Text(reason.toString(), style: const TextStyle(fontSize: 12)),
                backgroundColor: AppTheme.primaryLight,
              );
            }).toList(),
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
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildNumericStepper(
                          label: 'Deliveries (Parity)',
                          value: obs['deliveries'] as int? ?? 3,
                          onChanged: (v) {
                            obs['deliveries'] = v;
                            vm.updateDemographic('deliveries', v);
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildNumericStepper(
                          label: 'Living Children',
                          value: obs['livingChildren'] as int? ?? 3,
                          onChanged: (v) {
                            obs['livingChildren'] = v;
                            vm.updateDemographic('livingChildren', v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNumericStepper(
                          label: 'Abortions / Miscarriages',
                          value: obs['abortions'] as int? ?? 0,
                          onChanged: (v) {
                            obs['abortions'] = v;
                            vm.updateDemographic('abortions', v);
                          },
                        ),
                      ),
                    ],
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    maxStage: 3,
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
                    maxStage: 3,
                    onChanged: (v) => vm.updatePopStage('posteriorStage', v),
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
    final pulseStatus = ClinicalValidationService.validatePulse(pulse);
    final spo2Status = ClinicalValidationService.validateSpO2(spo2);
    final glucoseStatus = ClinicalValidationService.validateGlucose(glucose);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Point-of-Care Vitals (भाइटल परीक्षण):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildVitalBox(
                  label: 'Blood Pressure',
                  value: '$sys / $dia mmHg',
                  status: bpStatus.severity,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildVitalBox(
                  label: 'Pulse Rate',
                  value: '$pulse bpm',
                  status: pulseStatus.severity,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildVitalBox(
                  label: 'SpO2 Saturation',
                  value: '$spo2%',
                  status: spo2Status.severity,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildVitalBox(
                  label: 'Blood Glucose',
                  value: '$glucose mg/dL',
                  status: glucoseStatus.severity,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Diagnoses Detected (रोग पहिचान):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: result.diagnoses.map((dx) {
              return Chip(
                avatar: const Icon(Icons.healing, size: 16, color: Colors.teal),
                label: Text(dx, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                backgroundColor: Colors.teal.shade50,
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          const Text('Prescriptions Dispensed (औषधी):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: result.medications.map((rx) {
              return Chip(
                avatar: const Icon(Icons.medication, size: 16, color: Colors.indigo),
                label: Text(rx, style: const TextStyle(fontSize: 12)),
                backgroundColor: Colors.indigo.shade50,
              );
            }).toList(),
          ),
          if (result.surgicalReferral != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_hospital, color: Colors.red, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Surgical Referral: ${result.surgicalReferral}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
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

  Widget _buildNumericStepper({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
        ),
        Text('$value', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => onChanged(value + 1),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
        DropdownButton<int>(
          value: value,
          items: List.generate(
            maxStage + 1,
            (i) => DropdownMenuItem(value: i, child: Text('Stage $i')),
          ),
          onChanged: (v) => v != null ? onChanged(v) : null,
        ),
      ],
    );
  }

  Widget _buildVitalBox({
    required String label,
    required String value,
    required ValidationSeverity status,
  }) {
    final color = status == ValidationSeverity.normal
        ? AppTheme.successGreen
        : status == ValidationSeverity.warning
            ? AppTheme.warningAmber
            : AppTheme.dangerRose;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
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
