import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

/// Cross-platform offline OCR service.
///
/// - Android / iOS  -> Google ML Kit (on-device neural network)
/// - Windows        -> Windows.Media.Ocr via PowerShell (built into Windows 10/11)
/// - macOS / Linux  -> Not supported, returns empty string (simulation mode)
class MlKitOcrService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Extracts raw text from [imageFile].
  /// Returns empty string if OCR is unavailable on this platform.
  Future<String> extractText(XFile imageFile) async {
    // Web: dart:io Platform is unsupported — return empty (simulation mode)
    if (kIsWeb) return '';
    if (Platform.isAndroid || Platform.isIOS) {
      return _extractWithMlKit(imageFile);
    } else if (Platform.isWindows) {
      return _extractWithWindowsOcr(imageFile.path);
    }
    return ''; // macOS / Linux: not supported
  }

  // Android / iOS: Google ML Kit Text Recognition
  Future<String> _extractWithMlKit(XFile imageFile) async {
    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final result = await _recognizer.processImage(inputImage);
      return result.text;
    } catch (e) {
      if (kDebugMode) debugPrint('[OCR] ML Kit error: $e');
      return '';
    }
  }

  // Windows: Windows.Media.Ocr via bundled PowerShell script
  //
  // windows/scripts/ocr_image.ps1 uses the Windows.Media.Ocr.OcrEngine
  // that ships with every Windows 10/11 installation.
  // Fully offline, no cloud, no new package dependency.
  Future<String> _extractWithWindowsOcr(String imagePath) async {
    try {
      // Locate the PS1 script relative to the executable
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final scriptPath = p.join(exeDir, 'scripts', 'ocr_image.ps1');

      // Fallback: look next to pubspec during development (flutter run)
      final devScript = p.join(
        Directory.current.path,
        'windows',
        'scripts',
        'ocr_image.ps1',
      );
      final resolvedScript =
          File(scriptPath).existsSync() ? scriptPath : devScript;

      if (!File(resolvedScript).existsSync()) {
        if (kDebugMode) debugPrint('[OCR] Windows script not found at $resolvedScript');
        return '';
      }

      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy', 'Bypass',
          '-File', resolvedScript,
          '-ImagePath', imagePath,
        ],
        runInShell: false,
      );

      final text = (result.stdout as String).trim();
      if (result.exitCode == 0 && text.isNotEmpty) {
        if (kDebugMode) debugPrint('[OCR] Windows OCR extracted ${text.length} chars');
        return text;
      }
      if (kDebugMode) debugPrint('[OCR] Windows OCR failed: ${result.stderr}');
      return '';
    } catch (e) {
      if (kDebugMode) debugPrint('[OCR] Windows OCR exception: $e');
      return '';
    }
  }

  /// Frees ML Kit resources. Call when the scan screen is disposed.
  Future<void> dispose() => _recognizer.close();
}
