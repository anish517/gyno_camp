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
  TextRecognizer? _recognizer;

  TextRecognizer _getOrCreateRecognizer() {
    return _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
  }

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
      final recognizer = _getOrCreateRecognizer();
      final result = await recognizer.processImage(inputImage);
      return result.text;
    } catch (e) {
      if (kDebugMode) debugPrint('[OCR] ML Kit error: $e');
      rethrow;
    }
  }

  // Windows: Windows.Media.Ocr via bundled PowerShell script
  //
  // windows/scripts/ocr_image.ps1 uses the Windows.Media.Ocr.OcrEngine
  // that ships with every Windows 10/11 installation.
  // Fully offline, no cloud, no new package dependency.
  Future<String> _extractWithWindowsOcr(String imagePath) async {
    try {
      // Normalize path: requires a full absolute Windows path with backslashes.
      final normalizedPath = imagePath.replaceAll('/', '\\');

      // Check candidate locations for ocr_image.ps1
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final candidates = [
        p.join(exeDir, 'scripts', 'ocr_image.ps1'),
        p.join(exeDir, 'data', 'flutter_assets', 'windows', 'scripts', 'ocr_image.ps1'),
        p.join(Directory.current.path, 'windows', 'scripts', 'ocr_image.ps1'),
        p.join(Directory.current.path, 'gyno_camp', 'windows', 'scripts', 'ocr_image.ps1'),
        'F:\\gyno_camp\\gyno_camp\\windows\\scripts\\ocr_image.ps1',
      ];

      String? resolvedScript;
      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          resolvedScript = candidate;
          break;
        }
      }

      if (resolvedScript == null) {
        if (kDebugMode) {
          debugPrint('[OCR-Win] Script not found in candidates: $candidates');
        }
        throw Exception('ocr_image.ps1 not found in candidates: $candidates');
      }

      if (kDebugMode) debugPrint('[OCR-Win] Running OCR on: $normalizedPath using $resolvedScript');

      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy', 'Bypass',
          '-File', resolvedScript,
          '-ImagePath', normalizedPath,
        ],
        runInShell: false,
      );

      final text = (result.stdout as String).trim();
      if (result.exitCode == 0 && text.isNotEmpty) {
        if (kDebugMode) debugPrint('[OCR-Win] Extracted ${text.length} chars');
        return text;
      }
      final err = (result.stderr as String).trim();
      if (kDebugMode) debugPrint('[OCR-Win] Script failed (exit ${result.exitCode}): $err');
      if (err.isNotEmpty) throw Exception('Windows OCR script error: $err');
      return '';
    } catch (e) {
      if (kDebugMode) debugPrint('[OCR-Win] Exception: $e');
      rethrow;
    }
  }

  /// Frees ML Kit resources. Only active on mobile platforms.
  Future<void> dispose() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await _recognizer?.close();
      _recognizer = null;
    }
  }
}
