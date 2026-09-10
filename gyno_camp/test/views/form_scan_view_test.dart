import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/views/scanner/form_scan_view.dart';

void main() {
  group('FormScanView Widget Tests', () {
    testWidgets('FormScanView renders dual-slot capture prompt with Page 1 and Page 2 cards', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const FormScanView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Scan & Auto-Fill Yellow Form'), findsOneWidget);
      expect(find.text('Page 1 (Front Page)'), findsOneWidget);
      expect(find.text('Page 2 (Back Page)'), findsOneWidget);
      expect(find.text('Select Both Images at Once (Multi-Select)'), findsOneWidget);
      expect(find.text('Load Complete 2-Page Template'), findsOneWidget);
    });

    testWidgets('Tapping Load Complete 2-Page Template renders dual-page inspection and verification tabs', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const FormScanView(),
          ),
        ),
      );
      await tester.pump();

      // Tap complete template loader
      await tester.tap(find.text('Load Complete 2-Page Template'));
      await tester.pumpAndSettle();

      // Check inspection tabs
      expect(find.text('📄 Page 1 (Front: Demographics)'), findsOneWidget);
      expect(find.text('🩺 Page 2 (Back: POP & Vitals)'), findsOneWidget);

      // Check 4 clinical verification tabs
      expect(find.text('1. Demographics'), findsOneWidget);
      expect(find.text('2. Obstetric History'), findsOneWidget);
      expect(find.text('3. POP Staging'), findsOneWidget);
      expect(find.text('4. Vitals & Diagnoses'), findsOneWidget);

      // Check extracted fields in Demographics
      expect(find.text('First Name (नाम)'), findsOneWidget);
      expect(find.text('Surname (थर)'), findsOneWidget);

      // Check bottom commit button
      expect(find.text('Verify & Commit to Camp Database (दर्ता सम्पन्न गर्नुहोस्)'), findsOneWidget);
    });

    testWidgets('Obstetric history tab renders full-width steppers and back button returns to capture slots', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const FormScanView(),
          ),
        ),
      );
      await tester.pump();

      // Load 2-page template
      await tester.tap(find.text('Load Complete 2-Page Template'));
      await tester.pumpAndSettle();

      // Switch to Obstetric History tab
      await tester.tap(find.text('2. Obstetric History'));
      await tester.pumpAndSettle();

      // Verify full-width steppers with complete labels
      expect(find.text('Deliveries / Parity (सुत्केरी संख्या)'), findsOneWidget);
      expect(find.text('Living Children (जीवित बालबच्चा)'), findsOneWidget);
      expect(find.text('Abortions / Miscarriages (गर्भपतन)'), findsOneWidget);

      // Verify back button to return to capture slots
      expect(find.byTooltip('Return to Document Upload Slots'), findsOneWidget);
      await tester.tap(find.byTooltip('Return to Document Upload Slots'));
      await tester.pumpAndSettle();

      // We should now be back on the dual-slot capture prompt
      expect(find.text('Scan & Auto-Fill Yellow Form'), findsOneWidget);
      expect(find.text('Page 1 (Front Page)'), findsOneWidget);
      expect(find.text('Page 2 (Back Page)'), findsOneWidget);
    });
  });
}
