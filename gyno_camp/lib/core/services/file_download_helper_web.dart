import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<String> saveFile({
  required List<int> bytes,
  required String filename,
  String? mimeType,
  String? targetDirectoryPath,
}) async {
  final defaultMime = filename.endsWith('.pdf')
      ? 'application/pdf'
      : filename.endsWith('.xlsx')
          ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
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

  return 'Downloads (Browser): $filename';
}
