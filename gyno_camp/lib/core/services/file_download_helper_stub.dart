import 'download_result.dart';

Future<DownloadResult> saveFile({
  required List<int> bytes,
  required String filename,
  String? mimeType,
  String? targetDirectoryPath,
}) async {
  return DownloadResult(
    isSuccess: true,
    filename: filename,
    displayLocation: 'Memory',
  );
}
