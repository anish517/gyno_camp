import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  }) {
    return impl.saveFile(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
      targetDirectoryPath: targetDirectoryPath,
    );
  }

  /// Opens the file with the default device application (Mobile & Desktop).
  static Future<void> openFile(String filePath) async {
    try {
      if (kIsWeb) return;
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

  /// Shows unified, user-friendly feedback with 'Open' and 'Share/Print' actions on mobile devices.
  static void showDownloadFeedback(BuildContext context, DownloadResult result) {
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
