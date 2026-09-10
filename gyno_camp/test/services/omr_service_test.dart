import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:gyno_camp/core/services/omr_service.dart';

void main() {
  group('OmrService Tests', () {
    const omrService = OmrService();

    test('evaluates completely blank checkbox as unmarked', () {
      // 100x100 white image
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));

      const box = OmrBox(
        id: 'test_blank',
        label: 'Blank Checkbox',
        normalizedRect: Rect.fromLTWH(0.2, 0.2, 0.6, 0.6),
      );

      final result = omrService.evaluateSingleBox(image, box);

      expect(result.isMarked, isFalse);
      expect(result.inkDensity, 0.0);
      expect(result.confidence, 0.95);
    });

    test('evaluates checkbox with drawn X as marked with high confidence', () {
      // 100x100 white image
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));

      // Draw a black "X" in the center (from 30,30 to 70,70 and 30,70 to 70,30)
      final black = img.ColorRgb8(0, 0, 0);
      for (int i = 30; i <= 70; i++) {
        // Thick stroke: 3 pixels wide
        for (int d = -1; d <= 1; d++) {
          image.setPixel(i, (i + d).clamp(0, 99), black);
          image.setPixel(i, (100 - i + d).clamp(0, 99), black);
        }
      }

      const box = OmrBox(
        id: 'test_x',
        label: 'Marked Checkbox',
        normalizedRect: Rect.fromLTWH(0.2, 0.2, 0.6, 0.6),
      );

      final result = omrService.evaluateSingleBox(image, box);

      expect(result.isMarked, isTrue);
      expect(result.inkDensity, greaterThan(0.14));
      expect(result.confidence, greaterThanOrEqualTo(0.85));
    });

    test('border inset ignores outer printed box frame', () {
      // 100x100 white image
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));

      // Draw a black border rectangle at x: 20..80, y: 20..80 (thickness 2px)
      final black = img.ColorRgb8(0, 0, 0);
      for (int x = 20; x <= 80; x++) {
        image.setPixel(x, 20, black);
        image.setPixel(x, 21, black);
        image.setPixel(x, 79, black);
        image.setPixel(x, 80, black);
      }
      for (int y = 20; y <= 80; y++) {
        image.setPixel(20, y, black);
        image.setPixel(21, y, black);
        image.setPixel(79, y, black);
        image.setPixel(80, y, black);
      }

      const box = OmrBox(
        id: 'test_border_only',
        label: 'Unmarked Checkbox with Border',
        normalizedRect: Rect.fromLTWH(0.2, 0.2, 0.6, 0.6),
      );

      final result = omrService.evaluateSingleBox(image, box);

      // Inset should skip the border lines, leaving interior ink density ~ 0
      expect(result.isMarked, isFalse);
      expect(result.inkDensity, lessThan(0.06));
    });

    test('evaluateDecodedImage evaluates all boxes in list', () {
      final image = img.Image(width: 200, height: 200);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));

      // Mark only the first box
      final black = img.ColorRgb8(0, 0, 0);
      for (int py = 20; py <= 40; py++) {
        for (int px = 20; px <= 40; px++) {
          image.setPixel(px, py, black);
        }
      }

      final boxes = [
        const OmrBox(id: 'box_a', label: 'Box A', normalizedRect: Rect.fromLTWH(0.1, 0.1, 0.2, 0.2)),
        const OmrBox(id: 'box_b', label: 'Box B', normalizedRect: Rect.fromLTWH(0.5, 0.5, 0.2, 0.2)),
      ];

      final results = omrService.evaluateDecodedImage(image, boxes);

      expect(results.length, 2);
      expect(results['box_a']!.isMarked, isTrue);
      expect(results['box_b']!.isMarked, isFalse);
    });
  });
}
