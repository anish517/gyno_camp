import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/views/scanner/form_scan_view.dart';

void main() {
  group('FormScanView Vitals & Diagnoses Editing Tests', () {
    testWidgets('Vitals and Diagnoses tab enables manual editing for BP, Pulse, SpO2, Glucose, Diagnoses and Meds', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 3000);
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

      // Switch to Tab 4: Vitals & Diagnoses
      await tester.ensureVisible(find.text('4. Vitals & Diagnoses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4. Vitals & Diagnoses'));
      await tester.pumpAndSettle();

      // ── 1. Check Blood Pressure Fields & Live Validation ──────────────
      expect(find.text('Blood Pressure (रक्तचाप)'), findsOneWidget);
      expect(find.text('Systolic (सिस्टोलिक)'), findsOneWidget);
      expect(find.text('Diastolic (डायस्टोलिक)'), findsOneWidget);

      // Verify initial sample values (130 / 85 mmHg)
      final sysField = find.widgetWithText(TextFormField, 'Systolic (सिस्टोलिक)');
      expect(sysField, findsOneWidget);

      // Enter High Systolic BP (e.g. 175) to trigger Stage 2 Hypertension warning
      await tester.enterText(sysField, '175');
      await tester.pumpAndSettle();
      expect(find.textContaining('Stage 2 Hypertension warning'), findsOneWidget);

      // ── 2. Check Pulse Rate Field ─────────────────────────────────────
      expect(find.text('Pulse Rate'), findsOneWidget);
      final pulseField = find.widgetWithText(TextFormField, 'नाडी (bpm)');
      expect(pulseField, findsOneWidget);
      await tester.enterText(pulseField, '115'); // Tachycardia warning
      await tester.pumpAndSettle();
      expect(find.textContaining('Tachycardia warning'), findsOneWidget);

      // ── 3. Check SpO2 Field ───────────────────────────────────────────
      expect(find.text('SpO2 Saturation'), findsOneWidget);
      final spo2Field = find.widgetWithText(TextFormField, 'अक्सिजन (%)');
      expect(spo2Field, findsOneWidget);
      await tester.enterText(spo2Field, '88'); // Hypoxia alert
      await tester.pumpAndSettle();
      expect(find.textContaining('Hypoxia warning'), findsOneWidget);

      // ── 4. Check Blood Glucose Field ──────────────────────────────────
      expect(find.text('Blood Glucose / सुगर जाँच (RBS)'), findsOneWidget);
      final glucoseField = find.widgetWithText(TextFormField, 'Random Blood Glucose (रक्त ग्लुकोज)');
      expect(glucoseField, findsOneWidget);
      await tester.enterText(glucoseField, '240'); // Hyperglycemia
      await tester.pumpAndSettle();
      expect(find.textContaining('Abnormal (240 mg/dL)'), findsOneWidget);

      // ── 5. Check Diagnoses Editing (Delete, Standard FilterChip, Custom)
      expect(find.text('Diagnoses Detected (रोग पहिचान)'), findsOneWidget);
      expect(find.text('Standard Yellow Form Diagnoses (२१ वटा मानक रोगहरू):'), findsOneWidget);

      // Add a diagnosis using standard filter chip (e.g. cystitis)
      await tester.tap(find.widgetWithText(FilterChip, 'cystitis'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'cystitis'), findsOneWidget);

      // Remove a diagnosis via delete icon on InputChip
      final cystitisChip = find.widgetWithText(InputChip, 'cystitis');
      expect(cystitisChip, findsOneWidget);
      // Tap delete icon on the input chip
      final deleteIcon = find.descendant(of: cystitisChip, matching: find.byIcon(Icons.cancel));
      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'cystitis'), findsNothing);

      // Add custom diagnosis
      final customDxField = find.widgetWithText(TextField, 'Add custom or other diagnosis (अन्य रोग)...');
      expect(customDxField, findsOneWidget);
      await tester.enterText(customDxField, 'Severe Anemia');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add').first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Severe Anemia'), findsOneWidget);

      // ── 6. Check Prescriptions Editing (Quick chip, FilterChip, Custom)
      expect(find.text('Prescriptions Dispensed (औषधी)'), findsOneWidget);
      expect(find.text('Standard Yellow Form Medications (स्टेशन ५ औषधीहरू):'), findsOneWidget);

      // Toggle standard medication (e.g. metronidazol)
      await tester.tap(find.widgetWithText(FilterChip, 'metronidazol'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'metronidazol'), findsOneWidget);

      // Tap quick suggestion for Ring Pessary
      await tester.tap(find.text('Ring Pessary 65mm'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Ring Pessary 65mm'), findsOneWidget);

      // ── 7. Check Surgery Done & Route Card ─────────────────────────────
      expect(find.text('Surgery Done & Route (शल्यक्रिया भएको र विधि)'), findsOneWidget);
      final surgerySwitches = find.byType(Switch);
      expect(surgerySwitches, findsWidgets);

      // Tap surgery switch to enable
      await tester.tap(surgerySwitches.first);
      await tester.pumpAndSettle();

      // Verify the 3 surgical routes are available
      expect(find.widgetWithText(ChoiceChip, 'Open surgery'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Laparoscopy'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Vaginal route'), findsOneWidget);

      // Select Vaginal route
      await tester.tap(find.widgetWithText(ChoiceChip, 'Vaginal route'));
      await tester.pumpAndSettle();

      // ── 8. Check Ring Pessary Insertion Card ───────────────────────────
      expect(find.text('Ring Pessary Insertion (रिङ्ग पेसरी राखिएको)'), findsOneWidget);
      await tester.tap(surgerySwitches.last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, '70mm'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '70mm'));
      await tester.pumpAndSettle();

      // ── 9. Check Surgical Referral & Follow-up Destination ─────────────
      expect(find.text('Surgical Referral & Follow-up (शल्यक्रिया सिफारिस)'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Model Hospital'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Camp Follow-up Day (पुनः शिविर)'));
      await tester.pumpAndSettle();

      // ── 10. Switch to Tab 5: Verify Accuracy and verify display ─────────
      await tester.tap(find.text('✅ Verify Accuracy'));
      await tester.pumpAndSettle();

      expect(find.text('Surgery Done & Route'), findsOneWidget);
      expect(find.text('Ring Pessary'), findsWidgets);
    });
  });
}
