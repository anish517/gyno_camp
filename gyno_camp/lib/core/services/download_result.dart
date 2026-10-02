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

  /// Backward-compatible string representation:
  /// provides clean human-readable text instead of raw path.
  @override
  String toString() => displayLocation.isNotEmpty ? '$filename ($displayLocation)' : filename;
}
