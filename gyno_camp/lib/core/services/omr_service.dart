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

  /// Page 1: Marital Status Options
  static List<OmrBox> get page1MaritalStatusBoxes => const [
    OmrBox(id: 'married', label: 'Married', normalizedRect: Rect.fromLTWH(0.24, 0.22, 0.05, 0.025)),
    OmrBox(id: 'unmarried', label: 'Unmarried', normalizedRect: Rect.fromLTWH(0.52, 0.22, 0.05, 0.025)),
    OmrBox(id: 'widow', label: 'Widow', normalizedRect: Rect.fromLTWH(0.80, 0.22, 0.05, 0.025)),
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
    OmrBox(id: 'anterior_0', label: 'Anterior Stage 0', normalizedRect: Rect.fromLTWH(0.60, 0.18, 0.04, 0.02)),
    OmrBox(id: 'anterior_1', label: 'Anterior Stage 1', normalizedRect: Rect.fromLTWH(0.68, 0.18, 0.04, 0.02)),
    OmrBox(id: 'anterior_2', label: 'Anterior Stage 2', normalizedRect: Rect.fromLTWH(0.76, 0.18, 0.04, 0.02)),
    OmrBox(id: 'anterior_3', label: 'Anterior Stage 3', normalizedRect: Rect.fromLTWH(0.84, 0.18, 0.04, 0.02)),
    OmrBox(id: 'anterior_4', label: 'Anterior Stage 4', normalizedRect: Rect.fromLTWH(0.92, 0.18, 0.04, 0.02)),

    // Middle / Apical Compartment
    OmrBox(id: 'middle_0', label: 'Middle Stage 0', normalizedRect: Rect.fromLTWH(0.60, 0.22, 0.04, 0.02)),
    OmrBox(id: 'middle_1', label: 'Middle Stage 1', normalizedRect: Rect.fromLTWH(0.68, 0.22, 0.04, 0.02)),
    OmrBox(id: 'middle_2', label: 'Middle Stage 2', normalizedRect: Rect.fromLTWH(0.76, 0.22, 0.04, 0.02)),
    OmrBox(id: 'middle_3', label: 'Middle Stage 3', normalizedRect: Rect.fromLTWH(0.84, 0.22, 0.04, 0.02)),
    OmrBox(id: 'middle_4', label: 'Middle Stage 4', normalizedRect: Rect.fromLTWH(0.92, 0.22, 0.04, 0.02)),

    // Posterior Compartment
    OmrBox(id: 'posterior_0', label: 'Posterior Stage 0', normalizedRect: Rect.fromLTWH(0.60, 0.26, 0.04, 0.02)),
    OmrBox(id: 'posterior_1', label: 'Posterior Stage 1', normalizedRect: Rect.fromLTWH(0.68, 0.26, 0.04, 0.02)),
    OmrBox(id: 'posterior_2', label: 'Posterior Stage 2', normalizedRect: Rect.fromLTWH(0.76, 0.26, 0.04, 0.02)),
    OmrBox(id: 'posterior_3', label: 'Posterior Stage 3', normalizedRect: Rect.fromLTWH(0.84, 0.26, 0.04, 0.02)),
    OmrBox(id: 'posterior_4', label: 'Posterior Stage 4', normalizedRect: Rect.fromLTWH(0.92, 0.26, 0.04, 0.02)),

    // Pelvic Floor Muscle Tone
    OmrBox(id: 'tone_normal', label: 'Normal Tone', normalizedRect: Rect.fromLTWH(0.60, 0.31, 0.045, 0.02)),
    OmrBox(id: 'tone_weak', label: 'Weak Tone', normalizedRect: Rect.fromLTWH(0.75, 0.31, 0.045, 0.02)),
    OmrBox(id: 'tone_torn', label: 'Torn Tone', normalizedRect: Rect.fromLTWH(0.88, 0.31, 0.045, 0.02)),
  ];

  /// Page 2: Clinical Diagnoses
  static List<OmrBox> get page2DiagnosesBoxes => const [
    OmrBox(id: 'Pelvic Organ Prolapse (POP)', label: 'POP', normalizedRect: Rect.fromLTWH(0.06, 0.65, 0.045, 0.02)),
    OmrBox(id: 'Cervicitis', label: 'Cervicitis', normalizedRect: Rect.fromLTWH(0.53, 0.65, 0.045, 0.02)),
    OmrBox(id: 'Vaginitis', label: 'Vaginitis', normalizedRect: Rect.fromLTWH(0.06, 0.68, 0.045, 0.02)),
    OmrBox(id: 'Pelvic Inflammatory Disease (PID)', label: 'PID', normalizedRect: Rect.fromLTWH(0.53, 0.68, 0.045, 0.02)),
    OmrBox(id: 'Urinary Tract Infection (UTI)', label: 'UTI', normalizedRect: Rect.fromLTWH(0.06, 0.71, 0.045, 0.02)),
    OmrBox(id: 'Hypertension', label: 'Hypertension', normalizedRect: Rect.fromLTWH(0.53, 0.71, 0.045, 0.02)),
    OmrBox(id: 'Diabetes Mellitus', label: 'Diabetes', normalizedRect: Rect.fromLTWH(0.06, 0.74, 0.045, 0.02)),
  ];
}
