import 'file_download_helper_stub.dart'
    if (dart.library.html) 'file_download_helper_web.dart'
    if (dart.library.io) 'file_download_helper_io.dart' as impl;

class FileDownloadHelper {
  static Future<String> saveAndDownloadFile({
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
}
