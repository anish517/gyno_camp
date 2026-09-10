import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Cross-platform offline OCR service.
///
/// - Android / iOS  -> Google ML Kit (on-device neural network)
///   - Dual-pass: Latin script + Devanagari script for Nepali forms
///   - Full-resolution images (no JPEG compression)
/// - Windows        -> Windows.Media.Ocr via PowerShell (built into Windows 10/11)
/// - macOS / Linux  -> Not supported, returns empty string (simulation mode)
class MlKitOcrService {
  TextRecognizer? _latinRecognizer;
  TextRecognizer? _devanagariRecognizer;

  TextRecognizer _getLatinRecognizer() {
    return _latinRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
  }

  TextRecognizer _getDevanagariRecognizer() {
    return _devanagariRecognizer ??= TextRecognizer(script: TextRecognitionScript.devanagiri);
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
  //
  // Strategy: Run TWO recognition passes (Latin + Devanagari) and merge results.
  // The Yellow Forms contain a mix of English labels, handwritten English values,
  // and Devanagari (Nepali) text. A single-script recognizer misses the other script.
  Future<String> _extractWithMlKit(XFile imageFile) async {
    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);

      // Pass 1: Latin script (English text, numbers, medical terms)
      final latinRecognizer = _getLatinRecognizer();
      final latinResult = await latinRecognizer.processImage(inputImage);
      final latinText = latinResult.text;

      if (kDebugMode) {
        debugPrint('[OCR] ── Latin Pass ──');
        debugPrint('[OCR] Blocks: ${latinResult.blocks.length}');
        debugPrint('[OCR] Text length: ${latinText.length} chars');
        if (latinText.isNotEmpty) {
          debugPrint('[OCR] First 500 chars:\n${latinText.substring(0, latinText.length.clamp(0, 500))}');
        }
      }

      // Pass 2: Devanagari script (Nepali text)
      String devanagariText = '';
      try {
        final devRecognizer = _getDevanagariRecognizer();
        final devResult = await devRecognizer.processImage(inputImage);
        devanagariText = devResult.text;

        if (kDebugMode) {
          debugPrint('[OCR] ── Devanagari Pass ──');
          debugPrint('[OCR] Blocks: ${devResult.blocks.length}');
          debugPrint('[OCR] Text length: ${devanagariText.length} chars');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[OCR] Devanagari pass failed (non-fatal): $e');
        // Non-fatal: continue with Latin results only
      }

      // Merge: Latin is primary (most form labels + values are English/numbers).
      // Append any Devanagari-unique content that isn't already captured.
      final mergedText = _mergeOcrResults(latinText, devanagariText);

      // Post-process: normalize common OCR artifacts
      final cleanedText = _postProcessOcrText(mergedText);

      if (kDebugMode) {
        debugPrint('[OCR] ── Final Merged & Cleaned ──');
        debugPrint('[OCR] Total length: ${cleanedText.length} chars');
        debugPrint('[OCR] Full text:\n$cleanedText');
      }

      return cleanedText;
    } catch (e) {
      if (kDebugMode) debugPrint('[OCR] ML Kit error: $e');
      rethrow;
    }
  }

  /// Merges Latin and Devanagari OCR results.
  /// Latin is the primary source; Devanagari lines are appended if they contain
  /// unique Nepali content not already present in the Latin output.
  String _mergeOcrResults(String latinText, String devanagariText) {
    if (devanagariText.trim().isEmpty) return latinText;
    if (latinText.trim().isEmpty) return devanagariText;

    // Check if Devanagari output has any actual Devanagari characters
    final hasDevanagari = RegExp(r'[\u0900-\u097F]').hasMatch(devanagariText);
    if (!hasDevanagari) {
      // Devanagari recognizer only found Latin chars — Latin pass is sufficient
      return latinText;
    }

    // Extract Devanagari-only lines (lines containing Devanagari characters)
    final devLines = devanagariText.split(RegExp(r'[\r\n]+'));
    final extraDevLines = <String>[];
    for (final line in devLines) {
      if (RegExp(r'[\u0900-\u097F]').hasMatch(line) && !latinText.contains(line.trim())) {
        extraDevLines.add(line.trim());
      }
    }

    if (extraDevLines.isEmpty) return latinText;

    return '$latinText\n\n--- Devanagari ---\n${extraDevLines.join('\n')}';
  }

  /// Post-process OCR text to fix common ML Kit artifacts from handwritten forms.
  String _postProcessOcrText(String text) {
    var cleaned = text;

    // Fix common digit/letter confusion in medical context
    // 'O' (letter O) → '0' (zero) when surrounded by digits
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(\d)[Oo](\d)'),
      (m) => '${m.group(1)}0${m.group(2)}',
    );

    // Fix 'l' (lowercase L) → '1' when surrounded by digits
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(\d)[lI|](\d)'),
      (m) => '${m.group(1)}1${m.group(2)}',
    );

    // Normalize common label OCR errors
    cleaned = cleaned
        .replaceAll(RegExp(r'\bNarne\b', caseSensitive: false), 'Name')
        .replaceAll(RegExp(r'\bNane\b', caseSensitive: false), 'Name')
        .replaceAll(RegExp(r'\bAqe\b', caseSensitive: false), 'Age')
        .replaceAll(RegExp(r'\bMob[i1]le\b', caseSensitive: false), 'Mobile')
        .replaceAll(RegExp(r'\bD[i1]str[i1]ct\b', caseSensitive: false), 'District')
        .replaceAll(RegExp(r'\bMun[i1]c[i1]pal[i1]ty\b', caseSensitive: false), 'Municipality')
        .replaceAll(RegExp(r'\bWarcl\b', caseSensitive: false), 'Ward')
        .replaceAll(RegExp(r'\bPat[i1]ent\b', caseSensitive: false), 'Patient')
        .replaceAll(RegExp(r'\bHusbancl\b', caseSensitive: false), 'Husband')
        .replaceAll(RegExp(r'\bDe[l1][i1]ver[i1]es\b', caseSensitive: false), 'Deliveries')
        .replaceAll(RegExp(r'\bL[i1]v[i1]ng\b', caseSensitive: false), 'Living')
        .replaceAll(RegExp(r'\bAbort[i1]ons\b', caseSensitive: false), 'Abortions')
        .replaceAll(RegExp(r'\bAnter[i1]or\b', caseSensitive: false), 'Anterior')
        .replaceAll(RegExp(r'\bPoster[i1]or\b', caseSensitive: false), 'Posterior')
        .replaceAll(RegExp(r'\bM[i1]ddle\b', caseSensitive: false), 'Middle')
        .replaceAll(RegExp(r'\bPu[l1]se\b', caseSensitive: false), 'Pulse')
        .replaceAll(RegExp(r'\bG[l1]ucose\b', caseSensitive: false), 'Glucose')
        .replaceAll(RegExp(r'\bB[l1]ood\b', caseSensitive: false), 'Blood')
        .replaceAll(RegExp(r'\bPressure\b', caseSensitive: false), 'Pressure');

    // Normalize BP separator: "130 / 85" or "130| 85" → "130/85"
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(\d{2,3})\s*[/|\\]\s*(\d{2,3})\s*(?:mmHg|mm\s*Hg)?', caseSensitive: false),
      (m) => '${m.group(1)}/${m.group(2)} mmHg',
    );

    // Normalize mobile number: fix OCR mangling of 98/97 prefix
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\b[qgQG]([78]\d{8})\b'),
      (m) => '9${m.group(1)}',
    );

    // Collapse excessive whitespace but preserve newlines
    cleaned = cleaned.replaceAll(RegExp(r'[ \t]{3,}'), '  ');

    // Remove null/garbage characters
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

    return cleaned.trim();
  }

  // Windows: Windows.Media.Ocr via bundled PowerShell script
  //
  // windows/scripts/ocr_image.ps1 uses the Windows.Media.Ocr.OcrEngine
  // that ships with every Windows 10/11 installation.
  // Fully offline, no cloud, no new package dependency.
  Future<String> _extractWithWindowsOcr(String imagePath) async {
    try {
      // Normalize path: requires a full absolute Windows path with backslashes.
      final normalizedPath = File(imagePath).absolute.path;

      // Check candidate locations for ocr_image.ps1
      final exeDir = Directory(Platform.resolvedExecutable).parent.path;
      final candidates = [
        '$exeDir\\scripts\\ocr_image.ps1',
        '$exeDir\\data\\flutter_assets\\windows\\scripts\\ocr_image.ps1',
        '${Directory.current.path}\\windows\\scripts\\ocr_image.ps1',
        '${Directory.current.path}\\gyno_camp\\windows\\scripts\\ocr_image.ps1',
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
        workingDirectory: Directory.current.path,
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () => ProcessResult(0, 1, '', 'Windows OCR process timed out after 25s'),
      );

      final text = (result.stdout as String).trim();
      if (result.exitCode == 0 && text.isNotEmpty) {
        if (kDebugMode) debugPrint('[OCR-Win] Extracted ${text.length} chars');
        return _postProcessOcrText(text);
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
      await _latinRecognizer?.close();
      _latinRecognizer = null;
      await _devanagariRecognizer?.close();
      _devanagariRecognizer = null;
    }
  }
}
