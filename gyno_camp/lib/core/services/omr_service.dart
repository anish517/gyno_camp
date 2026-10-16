import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Defines an OMR region of interest (ROI) on a normalized document coordinate plane (0.0 to 1.0).
class OmrBox {
  final String id;
  final Rect normalizedRect;
  final String label;

  const OmrBox({
    required this.id,
    required this.normalizedRect,
    required this.label,
  });
}

/// The result of an OMR analysis on a single checkbox or bubble.
class OmrResult {
  final String id;
  final String label;
  final bool isMarked;
  final double inkDensity; // Fraction of dark pixels (0.0 - 1.0)
  final double confidence; // Confidence in the classification (0.0 - 1.0)

  const OmrResult({
    required this.id,
    required this.label,
    required this.isMarked,
    required this.inkDensity,
    required this.confidence,
  });

  @override
  String toString() => 'OmrResult($id: ${isMarked ? "MARKED" : "EMPTY"}, ink=${(inkDensity * 100).toStringAsFixed(1)}%, conf=${(confidence * 100).toStringAsFixed(0)}%)';
}

/// Offline pure-Dart Optical Mark Recognition (OMR) service.
///
/// Measures physical ink density inside checkbox boundaries rather than
/// relying on character OCR to transcribe graphical checkmarks (✓, ✗, ☒, ●).
class OmrService {
  /// Default luminance threshold: pixels with luminance < this value are considered ink.
  static const int defaultLuminanceThreshold = 135;

  /// Minimum ink density (14%) to classify as marked with high confidence.
  static const double markedThreshold = 0.14;

  /// Maximum ink density (6%) to classify as unmarked with high confidence.
  static const double unmarkedThreshold = 0.06;

  /// Margin inset (18%) to ignore the printed checkbox outer square border.
  static const double borderInsetRatio = 0.18;

  const OmrService();

  /// Analyzes a list of [OmrBox] targets on an image file.
  Future<Map<String, OmrResult>> evaluateImageFile(
    String filePath,
    List<OmrBox> boxes, {
    int luminanceThreshold = defaultLuminanceThreshold,
  }) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return {};
      final bytes = await file.readAsBytes();
      return evaluateImageBytes(bytes, boxes, luminanceThreshold: luminanceThreshold);
    } catch (e) {
      if (kDebugMode) debugPrint('[OMR] Error reading image file: $e');
      return {};
    }
  }

  /// Analyzes a list of [OmrBox] targets on in-memory image bytes.
  Map<String, OmrResult> evaluateImageBytes(
    Uint8List bytes,
    List<OmrBox> boxes, {
    int luminanceThreshold = defaultLuminanceThreshold,
  }) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      if (kDebugMode) debugPrint('[OMR] Failed to decode image bytes');
      return {};
    }
    return evaluateDecodedImage(image, boxes, luminanceThreshold: luminanceThreshold);
  }

  /// Analyzes a list of [OmrBox] targets on an already-decoded [img.Image].
  Map<String, OmrResult> evaluateDecodedImage(
    img.Image image,
    List<OmrBox> boxes, {
    int luminanceThreshold = defaultLuminanceThreshold,
  }) {
    final results = <String, OmrResult>{};
    for (final box in boxes) {
      results[box.id] = evaluateSingleBox(image, box, luminanceThreshold: luminanceThreshold);
    }
    return results;
  }

  /// Evaluates ink density for a single [OmrBox].
  OmrResult evaluateSingleBox(
    img.Image image,
    OmrBox box, {
    int luminanceThreshold = defaultLuminanceThreshold,
  }) {
    final rect = box.normalizedRect;
    final imgW = image.width;
    final imgH = image.height;

    // Convert normalized coordinates (0.0 - 1.0) to pixel coordinates
    final rawX = (rect.left * imgW).round();
    final rawY = (rect.top * imgH).round();
    final rawW = (rect.width * imgW).round();
    final rawH = (rect.height * imgH).round();

    // Bounds safety clamping
    final x = rawX.clamp(0, imgW - 1);
    final y = rawY.clamp(0, imgH - 1);
    final w = rawW.clamp(1, imgW - x);
    final h = rawH.clamp(1, imgH - y);

    // Apply border inset to exclude the printed outer border frame
    final insetX = (w * borderInsetRatio).round();
    final insetY = (h * borderInsetRatio).round();

    final innerX = (x + insetX).clamp(0, imgW - 1);
    final innerY = (y + insetY).clamp(0, imgH - 1);
    final innerW = max(1, w - 2 * insetX).clamp(1, imgW - innerX);
    final innerH = max(1, h - 2 * insetY).clamp(1, imgH - innerY);

    // Count dark ink pixels in the interior region
    int darkPixels = 0;
    final totalPixels = innerW * innerH;

    for (int py = innerY; py < innerY + innerH; py++) {
      for (int px = innerX; px < innerX + innerW; px++) {
        final pixel = image.getPixel(px, py);
        if (pixel.luminance < luminanceThreshold) {
          darkPixels++;
        }
      }
    }

    final inkDensity = totalPixels > 0 ? (darkPixels / totalPixels) : 0.0;

    final bool isMarked;
    final double confidence;

    if (inkDensity >= markedThreshold) {
      isMarked = true;
      // High ink density gives high confidence
      confidence = min(0.98, 0.85 + (inkDensity * 0.15));
    } else if (inkDensity <= unmarkedThreshold) {
      isMarked = false;
      confidence = 0.95;
    } else {
      // Borderline ink density (e.g. faint pencil, slight smudge, or small dot)
      isMarked = inkDensity >= 0.10;
      confidence = 0.70;
    }

    return OmrResult(
      id: box.id,
      label: box.label,
      isMarked: isMarked,
      inkDensity: inkDensity,
      confidence: confidence,
    );
  }

  // ===========================================================================
  // CALIBRATED YELLOW FORM OMR COORDINATE REGIONS
  //
  // Coordinates are normalized relative to full page bounds (0.0 to 1.0).
  // Calibrated against the MoHP Nepal Gynaecological Camp Standard Yellow Form.
  // ===========================================================================

  /// Page 1: Consultation (Triage Strip)
  static List<OmrBox> get page1TreatmentLevelBoxes => const [
    OmrBox(id: 'counseling', label: 'Counseling', normalizedRect: Rect.fromLTWH(0.24, 0.14, 0.048, 0.024)),
    OmrBox(id: 'gyno_checkup', label: 'Gynocheckup', normalizedRect: Rect.fromLTWH(0.56, 0.14, 0.048, 0.024)),
  ];

  /// Page 1: Marital Status Options
  static List<OmrBox> get page1MaritalStatusBoxes => const [
    OmrBox(id: 'married', label: 'Married', normalizedRect: Rect.fromLTWH(0.24, 0.22, 0.05, 0.025)),
    OmrBox(id: 'unmarried', label: 'Unmarried', normalizedRect: Rect.fromLTWH(0.48, 0.22, 0.05, 0.025)),
    OmrBox(id: 'widow', label: 'Widow', normalizedRect: Rect.fromLTWH(0.70, 0.22, 0.05, 0.025)),
    OmrBox(id: 'divorced', label: 'Divorced', normalizedRect: Rect.fromLTWH(0.88, 0.22, 0.05, 0.025)),
  ];

  /// Page 1: 8 Chief Complaints / Reasons for Visit
  static List<OmrBox> get page1VisitReasonsBoxes => const [
    OmrBox(id: 'something hanging out', label: 'Prolapse / Something hanging out', normalizedRect: Rect.fromLTWH(0.06, 0.42, 0.045, 0.022)),
    OmrBox(id: 'discharge and or itching', label: 'Vaginal discharge and/or itching', normalizedRect: Rect.fromLTWH(0.53, 0.42, 0.045, 0.022)),
    OmrBox(id: 'problems passing urine', label: 'Problems passing urine', normalizedRect: Rect.fromLTWH(0.06, 0.45, 0.045, 0.022)),
    OmrBox(id: 'problems passing stool', label: 'Problems passing stool', normalizedRect: Rect.fromLTWH(0.53, 0.45, 0.045, 0.022)),
    OmrBox(id: 'menstrual problem', label: 'Menstrual problem', normalizedRect: Rect.fromLTWH(0.06, 0.48, 0.045, 0.022)),
    OmrBox(id: 'infertility', label: 'Infertility', normalizedRect: Rect.fromLTWH(0.53, 0.48, 0.045, 0.022)),
    OmrBox(id: 'pain', label: 'Pelvic / Abdominal Pain', normalizedRect: Rect.fromLTWH(0.06, 0.51, 0.045, 0.022)),
    OmrBox(id: 'checkup', label: 'General Checkup', normalizedRect: Rect.fromLTWH(0.53, 0.51, 0.045, 0.022)),
  ];

  /// Page 2: Pelvic Organ Prolapse Compartment Staging
  static List<OmrBox> get page2PopStagingBoxes => const [
    // Anterior Compartment
    OmrBox(id: 'anterior_0', label: 'Anterior Stage 0', normalizedRect: Rect.fromLTWH(0.59, 0.175, 0.048, 0.024)),
    OmrBox(id: 'anterior_1', label: 'Anterior Stage 1', normalizedRect: Rect.fromLTWH(0.67, 0.175, 0.048, 0.024)),
    OmrBox(id: 'anterior_2', label: 'Anterior Stage 2', normalizedRect: Rect.fromLTWH(0.75, 0.175, 0.048, 0.024)),
    OmrBox(id: 'anterior_3', label: 'Anterior Stage 3', normalizedRect: Rect.fromLTWH(0.83, 0.175, 0.048, 0.024)),
    OmrBox(id: 'anterior_4', label: 'Anterior Stage 4', normalizedRect: Rect.fromLTWH(0.91, 0.175, 0.048, 0.024)),

    // Middle / Apical Compartment
    OmrBox(id: 'middle_0', label: 'Middle Stage 0', normalizedRect: Rect.fromLTWH(0.59, 0.215, 0.048, 0.024)),
    OmrBox(id: 'middle_1', label: 'Middle Stage 1', normalizedRect: Rect.fromLTWH(0.67, 0.215, 0.048, 0.024)),
    OmrBox(id: 'middle_2', label: 'Middle Stage 2', normalizedRect: Rect.fromLTWH(0.75, 0.215, 0.048, 0.024)),
    OmrBox(id: 'middle_3', label: 'Middle Stage 3', normalizedRect: Rect.fromLTWH(0.83, 0.215, 0.048, 0.024)),
    OmrBox(id: 'middle_4', label: 'Middle Stage 4', normalizedRect: Rect.fromLTWH(0.91, 0.215, 0.048, 0.024)),

    // Posterior Compartment
    OmrBox(id: 'posterior_0', label: 'Posterior Stage 0', normalizedRect: Rect.fromLTWH(0.59, 0.255, 0.048, 0.024)),
    OmrBox(id: 'posterior_1', label: 'Posterior Stage 1', normalizedRect: Rect.fromLTWH(0.67, 0.255, 0.048, 0.024)),
    OmrBox(id: 'posterior_2', label: 'Posterior Stage 2', normalizedRect: Rect.fromLTWH(0.75, 0.255, 0.048, 0.024)),
    OmrBox(id: 'posterior_3', label: 'Posterior Stage 3', normalizedRect: Rect.fromLTWH(0.83, 0.255, 0.048, 0.024)),
    OmrBox(id: 'posterior_4', label: 'Posterior Stage 4', normalizedRect: Rect.fromLTWH(0.91, 0.255, 0.048, 0.024)),

    // Pelvic Floor Muscle Tone
    OmrBox(id: 'tone_normal', label: 'Normal Tone', normalizedRect: Rect.fromLTWH(0.59, 0.305, 0.048, 0.024)),
    OmrBox(id: 'tone_weak', label: 'Weak Tone', normalizedRect: Rect.fromLTWH(0.74, 0.305, 0.048, 0.024)),
    OmrBox(id: 'tone_torn', label: 'Hypertonic Tone', normalizedRect: Rect.fromLTWH(0.87, 0.305, 0.048, 0.024)),
  ];

  /// Page 2: Station 4 Highest POP Stage Checkboxes
  static List<OmrBox> get page2PopHighestBoxes => const [
    OmrBox(id: 'highest_pop_0', label: 'Highest Stage 0', normalizedRect: Rect.fromLTWH(0.48, 0.585, 0.045, 0.022)),
    OmrBox(id: 'highest_pop_1', label: 'Highest Stage 1', normalizedRect: Rect.fromLTWH(0.58, 0.585, 0.045, 0.022)),
    OmrBox(id: 'highest_pop_2', label: 'Highest Stage 2', normalizedRect: Rect.fromLTWH(0.68, 0.585, 0.045, 0.022)),
    OmrBox(id: 'highest_pop_3', label: 'Highest Stage 3', normalizedRect: Rect.fromLTWH(0.78, 0.585, 0.045, 0.022)),
    OmrBox(id: 'highest_pop_4', label: 'Highest Stage 4', normalizedRect: Rect.fromLTWH(0.88, 0.585, 0.045, 0.022)),
  ];

  /// Page 2: Clinical Diagnoses (All 21 Diagnoses across 4 Columns)
  static List<OmrBox> get page2DiagnosesBoxes => const [
    // Column 1 (6 diagnoses)
    OmrBox(id: 'atrophy vagina', label: 'Atrophy Vagina', normalizedRect: Rect.fromLTWH(0.06, 0.615, 0.045, 0.018)),
    OmrBox(id: 'bacterial vaginosis', label: 'Bacterial Vaginosis', normalizedRect: Rect.fromLTWH(0.06, 0.633, 0.045, 0.018)),
    OmrBox(id: 'candid infection', label: 'Candid Infection', normalizedRect: Rect.fromLTWH(0.06, 0.651, 0.045, 0.018)),
    OmrBox(id: 'trichomonas', label: 'Trichomonas', normalizedRect: Rect.fromLTWH(0.06, 0.669, 0.045, 0.018)),
    OmrBox(id: 'PID', label: 'PID', normalizedRect: Rect.fromLTWH(0.06, 0.687, 0.045, 0.018)),
    OmrBox(id: 'cervicitis', label: 'Cervicitis', normalizedRect: Rect.fromLTWH(0.06, 0.705, 0.045, 0.018)),

    // Column 2 (6 diagnoses)
    OmrBox(id: 'cervical polyp', label: 'Cervical Polyp', normalizedRect: Rect.fromLTWH(0.30, 0.615, 0.045, 0.018)),
    OmrBox(id: 'cervical carcinoma', label: 'Cervical Carcinoma', normalizedRect: Rect.fromLTWH(0.30, 0.633, 0.045, 0.018)),
    OmrBox(id: 'condylomata', label: 'Condylomata', normalizedRect: Rect.fromLTWH(0.30, 0.651, 0.045, 0.018)),
    OmrBox(id: 'fistula', label: 'Fistula', normalizedRect: Rect.fromLTWH(0.30, 0.669, 0.045, 0.018)),
    OmrBox(id: 'infertility', label: 'Infertility', normalizedRect: Rect.fromLTWH(0.30, 0.687, 0.045, 0.018)),
    OmrBox(id: 'myoma', label: 'Myoma', normalizedRect: Rect.fromLTWH(0.30, 0.705, 0.045, 0.018)),

    // Column 3 (5 diagnoses)
    OmrBox(id: 'cystitis', label: 'Cystitis', normalizedRect: Rect.fromLTWH(0.53, 0.615, 0.045, 0.018)),
    OmrBox(id: 'stress incontinence', label: 'Stress Incontinence', normalizedRect: Rect.fromLTWH(0.53, 0.633, 0.045, 0.018)),
    OmrBox(id: 'urge incontinence', label: 'Urge Incontinence', normalizedRect: Rect.fromLTWH(0.53, 0.651, 0.045, 0.018)),
    OmrBox(id: 'weak pelvic floor muscle', label: 'Weak Pelvic Floor', normalizedRect: Rect.fromLTWH(0.53, 0.669, 0.045, 0.018)),
    OmrBox(id: 'hypertonic pelvic floor muscle', label: 'Hypertonic Pelvic Floor', normalizedRect: Rect.fromLTWH(0.53, 0.687, 0.045, 0.018)),

    // Column 4 (4 diagnoses)
    OmrBox(id: 'lichen sclerosis', label: 'Lichen Sclerosis', normalizedRect: Rect.fromLTWH(0.76, 0.615, 0.045, 0.018)),
    OmrBox(id: 'ovarian tumor', label: 'Ovarian Tumor', normalizedRect: Rect.fromLTWH(0.76, 0.633, 0.045, 0.018)),
    OmrBox(id: 'menstrual disorder', label: 'Menstrual Disorder', normalizedRect: Rect.fromLTWH(0.76, 0.651, 0.045, 0.018)),
    OmrBox(id: 'pregnancy', label: 'Pregnancy', normalizedRect: Rect.fromLTWH(0.76, 0.669, 0.045, 0.018)),
  ];
}
