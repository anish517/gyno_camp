import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'download_result.dart';

Future<DownloadResult> saveFile({
  required List<int> bytes,
  required String filename,
  String? mimeType,
  String? targetDirectoryPath,
}) async {
  try {
    final defaultMime = filename.endsWith('.pdf')
        ? 'application/pdf'
        : filename.endsWith('.xlsx')
            ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            : filename.endsWith('.json')
                ? 'application/json'
                : filename.endsWith('.csv')
                    ? 'text/csv'
                    : 'application/octet-stream';

    final jsArray = [Uint8List.fromList(bytes).toJS].toJS;
    final blob = web.Blob(
      jsArray,
      web.BlobPropertyBag(type: mimeType ?? defaultMime),
    );

    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = filename
      ..style.display = 'none';

    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();

    // Delay revocation so the browser download engine has time to read the blob stream
    Future.delayed(const Duration(seconds: 2), () {
      web.URL.revokeObjectURL(url);
    });

    return DownloadResult(
      isSuccess: true,
      filename: filename,
      filePath: null,
      displayLocation: 'browser Downloads folder',
      mimeType: mimeType ?? defaultMime,
      canOpenLocally: false,
    );
  } catch (e) {
    return DownloadResult(
      isSuccess: false,
      filename: filename,
      displayLocation: 'Browser',
      errorMessage: 'Download failed: $e',
    );
  }
}
