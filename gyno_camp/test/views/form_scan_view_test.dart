import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/views/scanner/form_scan_view.dart';

void main() {
  group('FormScanView Widget Tests', () {
    testWidgets('FormScanView renders capture prompt with action buttons and demo samples', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const FormScanView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Capture Paper Yellow Form'), findsOneWidget);
      expect(find.text('Capture with Camera'), findsOneWidget);
      expect(find.text('Select from Device Gallery / File'), findsOneWidget);
      expect(find.text('Load Full Yellow Form'), findsOneWidget);
    });

    testWidgets('Tapping Load Full Yellow Form renders verification tabs and commit button', (WidgetTester tester) async {
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

      // Tap sample loader
      await tester.tap(find.text('Load Full Yellow Form'));
      await tester.pumpAndSettle();

      // Check tabs
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
  });
}
