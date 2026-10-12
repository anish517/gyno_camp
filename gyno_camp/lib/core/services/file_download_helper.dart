import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_theme.dart';
import 'download_result.dart';
import 'file_download_helper_stub.dart'
    if (dart.library.html) 'file_download_helper_web.dart'
    if (dart.library.io) 'file_download_helper_io.dart' as impl;

export 'download_result.dart';

class FileDownloadHelper {
  /// Saves and initiates download for file bytes across Web, Mobile, and Desktop platforms.
  static Future<DownloadResult> saveAndDownloadFile({
    required List<int> bytes,
    required String filename,
    String? mimeType,
    String? targetDirectoryPath,
    bool autoOpen = false,
  }) async {
    final result = await impl.saveFile(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
      targetDirectoryPath: targetDirectoryPath,
      autoOpen: autoOpen,
    );
    if (autoOpen && !kIsWeb && result.isSuccess && result.filePath != null) {
      await openFile(result.filePath!);
    }
    return result;
  }

  /// Opens the file with the default device application (Mobile & Desktop).
  static Future<void> openFile(String filePath) async {
    try {
      if (kIsWeb) return;
      final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
      if (isTest) return;
      await OpenFilex.open(filePath);
    } catch (e) {
      debugPrint('[FileDownloadHelper] Could not open file: $e');
    }
  }

  /// Opens native platform share sheet allowing user to send or print the file.
  static Future<void> shareFile(String filePath, {String? text}) async {
    try {
      if (kIsWeb) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          subject: text ?? 'Gynocamp Document',
        ),
      );
    } catch (e) {
      debugPrint('[FileDownloadHelper] Could not share file: $e');
    }
  }

  /// Displays a prominent foreground bottom sheet directly over the active route/modal
  /// with 'Open & Review' and 'Share / Print' actions so the user never has to pop or go back.
  static Future<void> showForegroundReviewModal(
    BuildContext context,
    DownloadResult result,
  ) async {
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              elevation: 16,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Grab handle
                      Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      if (!result.isSuccess) ...[
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.dangerRose.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.error_outline_rounded, color: AppTheme.dangerRose, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Download Failed',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    result.errorMessage ?? 'An error occurred while generating file.',
                                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Dismiss', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.successGreen.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_circle_rounded, color: AppTheme.successGreen, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Document Ready for Review',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    result.filename,
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Saved to ${result.displayLocation}',
                                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFFF1F5F9),
                                foregroundColor: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        if (result.filePath != null && result.filePath!.isNotEmpty) ...[
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryTeal,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(Icons.visibility_rounded, size: 18),
                                  label: const Text('Open & Review', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                  onPressed: () {
                                    openFile(result.filePath!);
                                    Navigator.of(ctx).pop();
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF1E293B),
                                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.share_rounded, size: 18),
                                  label: const Text('Share / Print', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                  onPressed: () {
                                    shareFile(result.filePath!, text: result.filename);
                                    Navigator.of(ctx).pop();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryTeal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Shows unified, user-friendly feedback with 'Open' and 'Share/Print' actions on mobile devices.
  /// If [forceForegroundModal] is true, or if called within an active [Dialog], displays
  /// [showForegroundReviewModal] in the foreground so the feedback is never obscured by a modal barrier.
  static void showDownloadFeedback(
    BuildContext context,
    DownloadResult result, {
    bool forceForegroundModal = false,
  }) {
    if (!context.mounted) return;

    final isInsideDialog = context.findAncestorWidgetOfExactType<Dialog>() != null;
    if (forceForegroundModal || isInsideDialog) {
      showForegroundReviewModal(context, result);
      return;
    }
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    if (!result.isSuccess) {
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(result.errorMessage ?? 'Download failed')),
            ],
          ),
          backgroundColor: AppTheme.dangerRose,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (kIsWeb) {
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Downloaded: ${result.filename}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const Text('Saved to your browser\'s Downloads folder', style: TextStyle(fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.successGreen,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      // Mobile & Desktop
      final filePath = result.filePath;
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.filename, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                    Text('Saved to ${result.displayLocation}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ),
              if (filePath != null && filePath.isNotEmpty) ...[
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () => openFile(filePath),
                  child: const Text('Review', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.share_rounded, color: Colors.white, size: 18),
                  tooltip: 'Share or Print',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => shareFile(filePath, text: result.filename),
                ),
              ],
            ],
          ),
          backgroundColor: const Color(0xFF0F766E), // Deep Teal
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 7),
        ),
      );
    }
  }
}

/// Centralized utility for consistent, predictable document and report filenames.
class ReportFilenameHelper {
  /// Follow-up encounter slips: EncounterSlip_GC-DHN-2026-00042_20260401.pdf
  static String encounterSlip(String patientId, [DateTime? date]) {
    final ds = DateFormat('yyyyMMdd').format(date ?? DateTime.now());
    final cleanId = _clean(patientId);
    return 'EncounterSlip_${cleanId}_$ds.pdf';
  }

  /// Patient clinical dossiers: PatientDossier_GC-DHN-2026-00042_20260401.pdf
  static String patientDossier(String patientId, [DateTime? date]) {
    final ds = DateFormat('yyyyMMdd').format(date ?? DateTime.now());
    final cleanId = _clean(patientId);
    return 'PatientDossier_${cleanId}_$ds.pdf';
  }

  /// Camp summary PDF reports: CampReport_DHN_20260401_1430.pdf
  static String campSummary(String campCode, [DateTime? date]) {
    final ds = DateFormat('yyyyMMdd_HHmm').format(date ?? DateTime.now());
    final cleanCode = _clean(campCode);
    return 'CampReport_${cleanCode}_$ds.pdf';
  }

  /// Camp summary Excel registers: CampRegister_DHN_20260401_1430.xlsx
  static String campExcelRegister(String campCode, [DateTime? date]) {
    final ds = DateFormat('yyyyMMdd_HHmm').format(date ?? DateTime.now());
    final cleanCode = _clean(campCode);
    return 'CampRegister_${cleanCode}_$ds.xlsx';
  }

  /// Audit trail CSV report
  static String auditTrailCsv(String category, [DateTime? date]) {
    final ds = DateFormat('yyyyMMdd_HHmm').format(date ?? DateTime.now());
    final cleanCat = _clean(category.toLowerCase());
    return 'AuditTrail_${cleanCat}_$ds.csv';
  }

  /// Audit trail JSON vault
  static String auditTrailJson([DateTime? date]) {
    final ds = DateFormat('yyyyMMdd_HHmm').format(date ?? DateTime.now());
    return 'AuditTrail_Vault_$ds.json';
  }

  /// Database backup JSON snapshot
  static String databaseBackup([DateTime? date]) {
    final ds = DateFormat('yyyyMMdd_HHmm').format(date ?? DateTime.now());
    return 'Gynocamp_Backup_$ds.json';
  }

  static String _clean(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'Doc';
    return trimmed.replaceAll(RegExp(r'[^\w-]'), '_');
  }
}
