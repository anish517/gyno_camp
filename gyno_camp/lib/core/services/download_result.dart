import 'package:flutter/foundation.dart';

class DownloadResult {
  final bool isSuccess;
  final String filename;
  final String? filePath;
  final String displayLocation;
  final String? mimeType;
  final bool canOpenLocally;
  final String? errorMessage;

  const DownloadResult({
    required this.isSuccess,
    required this.filename,
    this.filePath,
    required this.displayLocation,
    this.mimeType,
    this.canOpenLocally = false,
    this.errorMessage,
  });

  /// Creates a successful DownloadResult from an existing saved file path.
  factory DownloadResult.fromSavedPath({
    required String savedPath,
    required String filename,
    String? mimeType,
  }) {
    return DownloadResult(
      isSuccess: true,
      filename: filename,
      filePath: kIsWeb ? null : savedPath,
      displayLocation: kIsWeb ? "browser's Downloads folder" : savedPath,
      mimeType: mimeType,
      canOpenLocally: !kIsWeb,
    );
  }

  /// Backward-compatible string representation:
  /// provides clean human-readable text instead of raw path.
  @override
  String toString() => displayLocation.isNotEmpty ? '$filename ($displayLocation)' : filename;
}
