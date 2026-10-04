import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'download_result.dart';

Future<DownloadResult> saveFile({
  required List<int> bytes,
  required String filename,
  String? mimeType,
  String? targetDirectoryPath,
}) async {
  try {
    String dirPath = targetDirectoryPath ?? '';
    String displayLocation = 'Downloads';

    if (dirPath.isEmpty) {
      final isTest = Platform.environment.containsKey('FLUTTER_TEST') ||
          WidgetsBinding.instance.runtimeType.toString().contains('Test');

      if (isTest) {
        dirPath = p.join(Directory.systemTemp.path, 'gynocamp_reports');
        displayLocation = 'Temp';
      } else if (Platform.isAndroid) {
        // Android 10+ (API 29) scoped storage: direct writes to
        // /storage/emulated/0/Download require MANAGE_EXTERNAL_STORAGE which
        // most apps don't have. Use app-scoped external storage instead —
        // always writable, no extra permission needed.

        // Priority 1: App external storage (Android/data/<pkg>/files/Downloads/)
        try {
          final extDir = await getExternalStorageDirectory();
          if (extDir != null) {
            final gynoDir = Directory(p.join(extDir.path, 'Gynocamp'));
            if (!gynoDir.existsSync()) gynoDir.createSync(recursive: true);
            dirPath = gynoDir.path;
            displayLocation = 'Downloads/Gynocamp';
          }
        } catch (_) {}

        // Priority 2: getExternalStorageDirectories downloads type
        if (dirPath.isEmpty) {
          try {
            final extDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
            if (extDirs != null && extDirs.isNotEmpty) {
              final gynoDir = Directory(p.join(extDirs.first.path, 'Gynocamp'));
              if (!gynoDir.existsSync()) gynoDir.createSync(recursive: true);
              dirPath = gynoDir.path;
              displayLocation = 'Downloads/Gynocamp';
            }
          } catch (_) {}
        }
      } else if (Platform.isIOS) {
        // iOS: Application documents directory (visible in Files if UIFileSharingEnabled is configured)
        final docDir = await getApplicationDocumentsDirectory();
        final gynoDir = Directory(p.join(docDir.path, 'Gynocamp'));
        if (!gynoDir.existsSync()) gynoDir.createSync(recursive: true);
        dirPath = gynoDir.path;
        displayLocation = 'Files/Gynocamp';
      } else {
        // Desktop (Windows, macOS, Linux)
        try {
          final downloadDir = await getDownloadsDirectory();
          if (downloadDir != null) {
            final gynoDir = Directory(p.join(downloadDir.path, 'Gynocamp'));
            if (!gynoDir.existsSync()) gynoDir.createSync(recursive: true);
            dirPath = gynoDir.path;
            displayLocation = 'Downloads/Gynocamp';
          }
        } catch (_) {}
      }

      // Final fallback if dirPath is still not resolved
      if (dirPath.isEmpty) {
        try {
          final appDir = await getApplicationDocumentsDirectory();
          final gynoDir = Directory(p.join(appDir.path, 'gynocamp_reports'));
          if (!gynoDir.existsSync()) gynoDir.createSync(recursive: true);
          dirPath = gynoDir.path;
          displayLocation = 'Documents';
        } catch (_) {
          dirPath = Directory.systemTemp.path;
          displayLocation = 'Temp';
        }
      }
    }

    final targetDir = Directory(dirPath);
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    final file = File(p.join(dirPath, filename));
    await file.writeAsBytes(bytes, flush: true);

    return DownloadResult(
      isSuccess: true,
      filename: filename,
      filePath: file.path,
      displayLocation: displayLocation,
      mimeType: mimeType,
      canOpenLocally: true,
    );
  } catch (e) {
    return DownloadResult(
      isSuccess: false,
      filename: filename,
      displayLocation: 'None',
      errorMessage: 'Failed to save file: $e',
    );
  }
}
