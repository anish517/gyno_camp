import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> saveFile({
  required List<int> bytes,
  required String filename,
  String? mimeType,
  String? targetDirectoryPath,
}) async {
  String dirPath = targetDirectoryPath ?? '';
  if (dirPath.isEmpty) {
    final isTest = Platform.environment.containsKey('FLUTTER_TEST') ||
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTest) {
      dirPath = Directory.systemTemp.path;
    } else {
      try {
        final appDir = await getApplicationDocumentsDirectory().timeout(const Duration(milliseconds: 500));
        dirPath = appDir.path;
      } catch (_) {
        dirPath = Directory.systemTemp.path;
      }
    }
  }

  final reportsDir = Directory(p.join(dirPath, 'gynocamp_reports'));
  if (!reportsDir.existsSync()) {
    reportsDir.createSync(recursive: true);
  }

  final file = File(p.join(reportsDir.path, filename));
  await file.writeAsBytes(bytes);
  return file.path;
}
